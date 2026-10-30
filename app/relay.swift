// Phone control: this Mac checks in with the Tube Timer relay every few seconds (status up, parents' commands down),
// and the 📱 Phones tab pairs parents' phones with a code / QR.
import Cocoa
import SwiftUI
import CoreImage

/// The hosted relay. Leave a custom one in the 📱 Phones tab to use your own.
let kDefaultRelayURL = "https://tube-timer-parents.up.railway.app"

final class Relay: ObservableObject {
    static let shared = Relay()
    private let d = UserDefaults.standard

    @Published var url: String { didSet { d.set(url, forKey: "relayURL") } }
    @Published var lastSync: Date?
    @Published var lastError = ""
    @Published var phones: [[String: String]]          // [{hash, name, added}] — hashes only, never keys
    @Published var pairCode: String?
    @Published var pairExpires: Date?
    @Published var pairError = ""

    let hid: String          // this household's id (random)
    private let macKey: String
    private var inFlight = false
    private var results: [[String: Any]] = []

    private init() {
        func secret(_ key: String, _ bytes: Int) -> String {
            if let s = UserDefaults.standard.string(forKey: key) { return s }
            var b = [UInt8](repeating: 0, count: bytes)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &b)
            let s = b.map { String(format: "%02x", $0) }.joined()
            UserDefaults.standard.set(s, forKey: key)
            return s
        }
        hid = secret("relayHID", 16)
        macKey = secret("relayKey", 32)
        url = (d.string(forKey: "relayURL") ?? kDefaultRelayURL).trimmingCharacters(in: .whitespaces)
        phones = d.array(forKey: "relayPhones") as? [[String: String]] ?? []
    }

    var base: String { url.trimmingCharacters(in: CharacterSet(charactersIn: " /")) }
    var online: Bool { lastSync.map { Date().timeIntervalSince($0) < 15 } ?? false }

    private func post(_ path: String, _ body: [String: Any], done: @escaping ([String: Any]?, String?) -> Void) {
        guard let u = URL(string: base + path), let data = try? JSONSerialization.data(withJSONObject: body) else {
            done(nil, "The sync server address isn't valid."); return
        }
        var req = URLRequest(url: u, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("Bearer \(macKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = data
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let problem: String? = err != nil ? "Can't reach the sync server." :
                (200..<300).contains(code) ? nil : (json?["error"] as? String ?? "Sync server error \(code)")
            DispatchQueue.main.async { done(json, problem) }
        }.resume()
    }

    /// Status up, commands down. Called every 3 seconds.
    func sync() {
        guard !base.isEmpty, !inFlight else { return }
        inFlight = true
        let sending = results
        results = []
        let body: [String: Any] = ["hid": hid, "status": Limiter.shared.statusSnapshot(), "results": sending, "parents": phones]
        post("/api/sync", body) { [weak self] json, problem in
            guard let self = self else { return }
            self.inFlight = false
            if let problem = problem { self.lastError = problem; self.results = sending + self.results; return }
            self.lastError = ""
            self.lastSync = Date()
            if let parents = json?["parents"] as? [[String: Any]] {
                let list = parents.map { p in ["hash": p["hash"] as? String ?? "", "name": p["name"] as? String ?? "Parent",
                                               "added": p["added"] as? String ?? ""] }
                if list != self.phones { self.phones = list; self.d.set(list, forKey: "relayPhones") }
            }
            let commands = json?["commands"] as? [[String: Any]] ?? []
            for c in commands {
                let id = c["id"] as? String ?? "", type = c["type"] as? String ?? ""
                let args = c["args"] as? [String: Any] ?? [:], from = c["from"] as? String ?? "A parent"
                Limiter.shared.runRemote(type, args, from: from) { ok, message in
                    self.results.append(["id": id, "ok": ok, "message": message])
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.sync() }   // report back quickly
                }
            }
        }
    }

    /// Ask the relay for a 6-digit pairing code.
    func startPairing() {
        pairError = ""
        sync()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {   // make sure the relay knows this Mac first
            self.post("/api/pair/start", ["hid": self.hid]) { json, problem in
                if let problem = problem { self.pairError = problem; return }
                self.pairCode = json?["code"] as? String
                self.pairExpires = Date().addingTimeInterval(Double(json?["minutes"] as? Int ?? 10) * 60)
            }
        }
    }

    func forgetPhones() {
        post("/api/phones/reset", ["hid": hid]) { _, problem in
            if let problem = problem { self.pairError = problem; return }
            self.phones = []; self.d.set([[String: String]](), forKey: "relayPhones")
        }
    }

    var pairLink: String { "\(base)/app/?pair=\(pairCode ?? "")" }
}

// MARK: - Commands from the phones

extension Limiter {
    func blockChannel(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        func without(_ s: String) -> String {
            s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0.lowercased() != n.lowercased() }.joined(separator: ", ")
        }
        allowChannels = without(allowChannels); funChannels = without(funChannels)
        blockChannels = without(blockChannels) + (without(blockChannels).isEmpty ? "" : ", ") + n
        changed()
    }

    func removeChannel(_ name: String, from list: String) {
        let drop = { (s: String) in s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.lowercased() != name.lowercased() }.joined(separator: ", ") }
        switch list {
        case "allow": allowChannels = drop(allowChannels)
        case "fun": funChannels = drop(funChannels)
        default: blockChannels = drop(blockChannels)
        }
        changed()
    }

    /// Runs one command from a parent's phone and reports back a short message.
    func runRemote(_ type: String, _ args: [String: Any], from: String, done: @escaping (Bool, String) -> Void) {
        let int = { (k: String, lo: Int, hi: Int) -> Int? in (args[k] as? NSNumber).map { min(hi, max(lo, $0.intValue)) } }
        switch type {
        case "add10":
            addExtra()
            done(true, "✅ Added 10 minutes. \(fmt(timeLeft)) left now.")
        case "endBreak":
            if inYouTubeOffHours {
                done(false, "It's YouTube bedtime. Use +10 minutes for a short pass.")
            } else {
                lockedUntil = 0; lockReason = ""; lockIsDaily = false
                party.hide(); nope.hide(); changed()
                done(true, "✅ Break ended.")
            }
        case "lockNow":
            let m = int("minutes", 1, 240) ?? 30
            lock(until: now + Double(m * 60), daily: false, reason: "\(from) paused YouTube for \(m) minutes.")
            done(true, "⏸ YouTube paused for \(m) minutes.")
        case "resetToday":
            resetToday()
            done(true, "✅ Today's time is reset.")
        case "setEnabled":
            enabled = (args["on"] as? Bool) ?? true
            done(true, enabled ? "✅ Tube Timer is on." : "Tube Timer is off.")
        case "approve", "deny":
            guard let id = args["id"] as? String, let r = requests.first(where: { $0.id == id && $0.status == "pending" }) else {
                done(false, "That request was already handled."); return
            }
            let asFun = (args["asFun"] as? Bool) ?? false
            decide(id, approve: type == "approve", asFun: asFun)
            let what = r.kind == "time" ? "10 more minutes" : r.channel
            done(true, type == "deny" ? "Denied: \(what)" : (asFun ? "✅ \(what) is on the fun track." : "✅ Approved: \(what)"))
        case "allowChannel", "funChannel", "blockChannel":
            let input = args["input"] as? String ?? ""
            resolveChannel(input) { name in
                guard let n = name, !n.isEmpty else { done(false, "Couldn't find that channel. Try one of its video links."); return }
                switch type {
                case "allowChannel": self.allowChannel(n); done(true, "✅ \(n) is always allowed.")
                case "funChannel": self.allowFunChannel(n); done(true, "✅ \(n) is on the fun track.")
                default: self.blockChannel(n); done(true, "🚫 \(n) is blocked.")
                }
            }
        case "removeChannel":
            let name = args["name"] as? String ?? ""
            removeChannel(name, from: args["list"] as? String ?? "")
            done(true, "Removed \(name).")
        case "setLimits":
            if let v = int("dailyMin", 5, 600) { dailyMin = v }
            if let v = int("sessionMin", 1, 240) { sessionMin = v }
            if let v = int("lockoutMin", 1, 240) { lockoutMin = v }
            if let v = int("funMin", 0, 180) { funMin = v }
            done(true, "✅ Limits saved.")
        case "setBedtime":
            if let s = int("start", 0, 1439), let e = int("end", 0, 1439) {
                UserDefaults.standard.set(s, forKey: "offStart"); UserDefaults.standard.set(e, forKey: "offEnd")
                changed()
                done(true, "✅ Bedtime is \(timeText(s)) to \(timeText(e)).")
            } else { done(false, "Bedtime times weren't valid.") }
        default:
            done(false, "This Mac doesn't know that command yet. Update Tube Timer.")
        }
    }
}

// MARK: - 📱 Phones tab

func qrImage(_ text: String) -> NSImage? {
    guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    f.setValue(Data(text.utf8), forKey: "inputMessage")
    f.setValue("M", forKey: "inputCorrectionLevel")
    guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
    let rep = NSCIImageRep(ciImage: out)
    let img = NSImage(size: rep.size)
    img.addRepresentation(rep)
    return img
}

struct PhonesView: View {
    @ObservedObject var r = Relay.shared
    @State private var tick = Date()
    @State private var showServer = false
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let _ = tick
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Control Tube Timer from your iPhone (or any phone): see his time, give +10, pause YouTube, answer requests, and change channels and limits.")
                    .font(.callout).foregroundColor(.secondary)
                HStack {
                    Circle().fill(r.online ? Color.green : (r.lastError.isEmpty ? Color.gray : Color.orange)).frame(width: 10, height: 10)
                    Text(r.online ? "Connected to the sync server" : (r.lastError.isEmpty ? "Connecting…" : r.lastError)).font(.callout)
                }
                GroupBox(label: Text("📱 Pair a phone")) {
                    VStack(alignment: .leading, spacing: 10) {
                        if let code = r.pairCode, let exp = r.pairExpires, exp > Date() {
                            HStack(alignment: .top, spacing: 16) {
                                if let img = qrImage(r.pairLink) {
                                    Image(nsImage: img).interpolation(.none).resizable().frame(width: 160, height: 160)
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("1. Scan this with the iPhone camera, or open \(r.base)/app and type:").font(.callout)
                                    Text(code.prefix(3) + " " + code.suffix(3)).font(.system(size: 34, weight: .heavy, design: .monospaced))
                                    Text("2. Enter who it is (Dad, Mom) and tap Pair.").font(.callout)
                                    Text("3. In Safari tap Share ⬆︎ → Add to Home Screen.").font(.callout)
                                    Text("Code works for \(Int(max(0, exp.timeIntervalSinceNow / 60)) + 1) more min, one phone.")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Button("📱 Pair a phone") { r.startPairing() }.controlSize(.large)
                        }
                        if !r.pairError.isEmpty { Text(r.pairError).font(.caption).foregroundColor(.orange) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                GroupBox(label: Text("Paired phones")) {
                    VStack(alignment: .leading, spacing: 6) {
                        if r.phones.isEmpty { Text("No phones yet.").font(.caption).foregroundColor(.secondary) }
                        ForEach(r.phones, id: \.self) { p in Text("📱 " + (p["name"] ?? "Parent")) }
                        if !r.phones.isEmpty { Button("Unpair all phones") { r.forgetPhones() } }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                DisclosureGroup("Sync server", isExpanded: $showServer) {
                    TextField(kDefaultRelayURL, text: $r.url).font(.caption)
                    Text("Phones and this Mac talk through this server. Only the household's status and your commands pass through it; keys are never stored there.")
                        .font(.caption).foregroundColor(.secondary)
                }.font(.callout)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .onReceive(clock) { tick = $0 }
    }
}
