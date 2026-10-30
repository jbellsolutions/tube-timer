// Kid requests (a channel, or 10 more minutes) and the parent's "add a channel".
import Cocoa
import SwiftUI

struct KidRequest: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var kind: String          // "channel" or "time"
    var channel = ""
    var note = ""
    var time = Date()
    var status = "pending"    // pending, approved, denied
}

let kMaxPendingRequests = 5

/// Works out a channel's name from a video link, a channel link or @handle, or just a typed name.
func resolveChannel(_ input: String, done: @escaping (String?) -> Void) {
    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { done(nil); return }
    let str = #""((?:[^"\\]|\\.)*)""#
    if let id = videoID(text) {
        fetchPage("https://www.youtube.com/watch?v=\(id)") { html in
            done(firstMatch(#""ownerChannelName":"# + str, html).map(unescapeJSON))
        }
    } else if text.contains("youtube.com/") || text.hasPrefix("@") {
        let url = text.hasPrefix("@") ? "https://www.youtube.com/\(text)" : (text.hasPrefix("http") ? text : "https://" + text)
        fetchPage(url) { html in
            let name = firstMatch(#"<meta property="og:title" content="([^"]*)""#, html)
                .map { $0.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'")
                        .replacingOccurrences(of: "&quot;", with: "\"") }
            done(name.flatMap { $0.isEmpty ? nil : $0 })
        }
    } else {
        done(text)
    }
}

extension Limiter {
    var pendingRequests: [KidRequest] { requests.filter { $0.status == "pending" } }

    static func loadRequests() -> [KidRequest] {
        UserDefaults.standard.data(forKey: "kidRequests").flatMap { try? JSONDecoder().decode([KidRequest].self, from: $0) } ?? []
    }

    func saveRequests() {
        if let data = try? JSONEncoder().encode(requests) { UserDefaults.standard.set(data, forKey: "kidRequests") }
    }

    func isChannelAllowed(_ name: String) -> Bool {
        allowChannels.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .contains(name.lowercased().trimmingCharacters(in: .whitespaces))
    }

    /// The kid asks for a channel or for 10 more minutes. Returns a message for the kid.
    @discardableResult
    func addRequest(kind: String, channel: String = "", note: String = "") -> String {
        if kind == "channel" && channel.isEmpty { return "Which channel? Type its name or paste a link." }
        if kind == "channel" && isChannelAllowed(channel) { return "\(channel) is already allowed!" }
        if pendingRequests.contains(where: { $0.kind == kind && $0.channel.lowercased() == channel.lowercased() }) {
            return "You already asked for that. A parent will check it soon."
        }
        if pendingRequests.count >= kMaxPendingRequests {
            return "You have \(kMaxPendingRequests) requests waiting. Ask a parent to check them first!"
        }
        requests.insert(KidRequest(kind: kind, channel: channel, note: note), at: 0)
        if requests.count > 30 { requests.removeLast() }
        saveRequests(); changed()
        return kind == "time" ? "Sent! A parent will see your request for 10 more minutes."
                              : "Sent! A parent will see your request for \(channel)."
    }

    func removing(_ name: String, from list: String) -> String {
        list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.lowercased() != name.lowercased() }.joined(separator: ", ")
    }

    /// Parent: always allow a channel (and take it off the block and fun lists).
    func allowChannel(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        var names = allowChannels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !names.contains(where: { $0.lowercased() == n.lowercased() }) { names.append(n) }
        allowChannels = names.joined(separator: ", ")
        blockChannels = removing(n, from: blockChannels)
        funChannels = removing(n, from: funChannels)          // a channel lives on one list only
        changed()
    }

    /// Parent: put a channel on the 30-minute fun track (and take it off the block list).
    func allowFunChannel(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        var names = funChannels.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !names.contains(where: { $0.lowercased() == n.lowercased() }) { names.append(n) }
        funChannels = names.joined(separator: ", ")
        blockChannels = removing(n, from: blockChannels)
        allowChannels = removing(n, from: allowChannels)      // a channel lives on one list only
        changed()
    }

    /// Parent approves (as learning, or as fun) or denies a request.
    func decide(_ id: String, approve: Bool, asFun: Bool = false) {
        guard let i = requests.firstIndex(where: { $0.id == id }) else { return }
        requests[i].status = approve ? (asFun ? "approved-fun" : "approved") : "denied"
        if approve {
            if requests[i].kind == "time" { addExtra() }
            else if asFun { allowFunChannel(requests[i].channel) }
            else { allowChannel(requests[i].channel) }
        }
        saveRequests(); changed()
    }
}

/// Parent's requests inbox + "add a channel", shown in the 🎓 Videos tab.
struct RequestsView: View {
    @ObservedObject var m = Limiter.shared
    @State private var addText = ""
    @State private var addMsg = ""

    private func add(asFun: Bool) {
        let input = addText
        addMsg = "Looking it up…"
        resolveChannel(input) { name in
            guard let n = name else { addMsg = "Couldn't find that channel. Try pasting one of its video links."; return }
            if asFun { m.allowFunChannel(n); addMsg = "✅ \(n) is on the fun track (\(m.funMin) min a day)." }
            else { m.allowChannel(n); addMsg = "✅ \(n) is now always allowed." }
            addText = ""
        }
    }

    private func when(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"; return f.string(from: d)
    }

    var body: some View {
        GroupBox(label: Text("📬 Requests & channels")) {
            VStack(alignment: .leading, spacing: 8) {
                if m.pendingRequests.isEmpty {
                    Text("No requests waiting. Your kid can ask for a channel or 10 more minutes with the kid PIN.")
                        .font(.caption).foregroundColor(.secondary)
                }
                ForEach(m.pendingRequests) { r in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.kind == "time" ? "⏱ 10 more minutes" : "📺 Channel: \(r.channel)").bold()
                            Text((r.note.isEmpty ? "" : "“\(r.note)” · ") + when(r.time)).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(r.kind == "time" ? "Approve" : "Allow") { m.decide(r.id, approve: true) }
                        if r.kind == "channel" { Button("As fun") { m.decide(r.id, approve: true, asFun: true) } }
                        Button("Deny") { m.decide(r.id, approve: false) }
                    }
                }
                Divider()
                Text("➕ Allow a channel (learning), or add it to the fun track").font(.subheadline).bold()
                HStack {
                    TextField("Paste a channel or video link, or type a channel name", text: $addText)
                    Button("Add") { add(asFun: false) }.disabled(addText.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Add as fun") { add(asFun: true) }.disabled(addText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !addMsg.isEmpty { Text(addMsg).font(.caption) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
        }
    }
}
