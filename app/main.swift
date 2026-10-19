// Tube Timer - a Mac menu bar app that limits YouTube time, keeps it to learning videos,
// and makes kids get up and move. https://github.com/jbellsolutions/tube-timer
import Cocoa
import SwiftUI
import WebKit

let kGapSec: Double = 5 * 60     // this long away from YouTube starts a fresh sitting
let kWarnSec: Double = 60        // "1 minute left" warning
let kExtraSec: Double = 10 * 60
let kKidExtrasPerDay = 2         // the kid PIN can add 10 minutes this many times a day
let kReshowSec: Double = 5 * 60  // party length when YouTube is reopened during a lock
let kEarnMinutes = 20          // fun minutes earned per video + quiz
let kMaxEarnsPerDay = 2
let kPartyMusicSeconds = 60    // dance-party music plays about a minute, then it's time to move

// MARK: - Daily schedule (the Mac's local time; minutes after midnight, set in the app)

let kScheduleDefaults: [String: Any] = [
    "funStart": 16 * 60,        // fun (entertainment) videos allowed from 4:00 PM...
    "funEnd": 20 * 60 + 30,     // ...until 8:30 PM on weekdays
    "weekendFunAllDay": true,   // weekends: fun allowed whenever YouTube is on
    "offStart": 21 * 60,        // YouTube off from 9:00 PM...
    "offEnd": 6 * 60,           // ...until 6:00 AM
]
var kFunStart: Int { UserDefaults.standard.integer(forKey: "funStart") }
var kFunEnd: Int { UserDefaults.standard.integer(forKey: "funEnd") }
var kOffStart: Int { UserDefaults.standard.integer(forKey: "offStart") }
var kOffEnd: Int { UserDefaults.standard.integer(forKey: "offEnd") }

func minutesNow() -> Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}
/// "4:00 PM" from minutes after midnight.
func timeText(_ m: Int) -> String {
    let d = Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date())!
    let f = DateFormatter(); f.dateFormat = "h:mm a"
    return f.string(from: d)
}
var funWindowText: String { "\(timeText(kFunStart))–\(timeText(kFunEnd))" }
var offHoursText: String { "\(timeText(kOffStart))–\(timeText(kOffEnd))" }
var isWeekend: Bool { Calendar.current.isDateInWeekend(Date()) }
/// In the fun window (weekdays) or a weekend day. The YouTube-off hours still apply on top.
var inFunWindow: Bool {
    if isWeekend && UserDefaults.standard.bool(forKey: "weekendFunAllDay") { return true }
    let m = minutesNow(); return m >= kFunStart && m < kFunEnd
}
var inYouTubeOffHours: Bool {
    let m = minutesNow()
    if kOffStart == kOffEnd { return false }  // same time = no off hours
    return kOffStart > kOffEnd ? (m >= kOffStart || m < kOffEnd) : (m >= kOffStart && m < kOffEnd)
}
/// When the YouTube-off hours end next.
func offHoursEnd() -> Double {
    let now = Date()
    var end = Calendar.current.date(bySettingHour: kOffEnd / 60, minute: kOffEnd % 60, second: 0, of: now)!
    if end <= now { end = Calendar.current.date(byAdding: .day, value: 1, to: end)! }
    return end.timeIntervalSince1970
}

// MARK: - Editable content (suggestions, quizzes, party songs)

/// Loads a content JSON file. A copy in ~/Library/Application Support/Tube Timer/ overrides the built-in one.
func loadContent(_ name: String) -> Any? {
    let custom = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Tube Timer/\(name).json")
    for url in [custom, Bundle.main.url(forResource: name, withExtension: "json")].compactMap({ $0 }) {
        if let data = try? Data(contentsOf: url), let obj = try? JSONSerialization.jsonObject(with: data) { return obj }
    }
    return nil
}

struct Content {
    var slots: [[String: Any]] = []           // [{label, videos: [{id, title, channel}]}]
    var channelHandles: [String] = []         // @handles of always-allowed channels (also feed suggestions)
    var alwaysAllowedChannels: [String] = []  // lowercase channel names
    var songs: [[String: Any]] = []           // [{id, start}]
    var challenges: [[String: Any]] = []
    var allowedVideoIDs: Set<String> = []

    static func load() -> Content {
        var c = Content()
        if let s = loadContent("suggestions") as? [String: Any] {
            c.slots = s["slots"] as? [[String: Any]] ?? []
            c.channelHandles = s["channelHandles"] as? [String] ?? []
            c.alwaysAllowedChannels = (s["alwaysAllowedChannels"] as? [String] ?? []).map { $0.lowercased() }
        }
        c.songs = (loadContent("party-songs") as? [String: Any])?["songs"] as? [[String: Any]] ?? []
        c.challenges = loadContent("challenges") as? [[String: Any]] ?? []
        let slotIDs = c.slots.flatMap { ($0["videos"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String } }
        c.allowedVideoIDs = Set(slotIDs)
        return c
    }
}
let content = Content.load()

let kUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

let allCategories = ["Education", "Science & Technology", "Music", "Howto & Style", "Pets & Animals", "Autos & Vehicles", "Travel & Events",
                     "Film & Animation", "Gaming", "Entertainment", "People & Blogs", "Comedy", "Sports", "News & Politics"]

/// Learning / creative / music words. A title or tag with one of these counts as learning (unless it's brain-rot, below).
let learningTopics = [
    // space
    "space", "planet", "solar system", "galaxy", "galaxies", "universe", "star", "moon", "mars", "jupiter", "saturn", "venus",
    "mercury", "neptune", "uranus", "pluto", "earth", "sun", "comet", "asteroid", "meteor", "black hole", "nebula", "rocket",
    "nasa", "spacex", "astronaut", "telescope", "satellite", "orbit", "gravity", "rocketry", "starship", "particle",
    // science + nature
    "science", "scientific", "experiment", "physics", "chemistry", "biology", "geology", "volcano", "earthquake", "tornado",
    "hurricane", "weather", "climate", "dinosaur", "fossil", "rock", "mineral", "crystal", "ocean", "animal", "wildlife",
    "nature", "insect", "shark", "whale", "plant", "human body", "brain", "atom", "molecule", "electricity", "magnet",
    "energy", "engine", "engineering", "invention", "machine", "robot", "coding", "programming", "technology",
    "airplane", "jet", "aircraft", "helicopter", "car", "train", "submarine", "bridge",
    // learning
    "how it works", "how does", "how do", "why do", "why does", "what if", "what happens", "explained", "fact", "quiz",
    "trivia", "riddle", "puzzle", "brain teaser", "learn", "learning", "lesson", "tutorial", "how to", "educational",
    "math", "maths", "multiplication", "division", "fraction", "geometry", "algebra", "counting", "reading", "read aloud",
    "story", "storytime", "book", "spelling", "phonics", "alphabet", "history", "geography", "map", "country", "countries", "flag",
    // art + making things
    "art", "drawing", "draw", "paint", "painting", "sketch", "doodle", "coloring", "colouring", "craft", "diy", "origami",
    "paper airplane", "paper plane", "sculpture", "clay", "lego", "folding surprise",
    // music
    "music", "song", "piano", "guitar", "drum", "violin", "instrument", "sing", "singing", "dance", "dancing", "shuffle",
    "phonk", "beat", "melody", "chord", "orchestra", "band", "cover", "remix",
]
/// A clear learning angle in the title. These win even over brain-rot words ("Minecraft Quiz" is fine).
let strongLearningTopics = [
    "quiz", "trivia", "learn", "learning", "lesson", "educational", "education", "science", "scientific", "experiment",
    "math", "maths", "explained", "how it works", "how does", "why do", "why does", "fact", "tutorial", "history",
    "geography", "physics", "chemistry", "biology", "geology", "engineering", "spelling", "phonics", "multiplication",
    "fraction", "geometry", "algebra", "can you name", "test your", "guess the", "how to draw", "documentary",
]
/// Passive "brain-rot" signals. These count as fun time even if a learning word shows up too.
let junkTopics = [
    "minecraft", "roblox", "fortnite", "among us", "skibidi", "sigma", "rizz", "gyatt", "ohio", "fanum", "brainrot",
    "brain rot", "prank", "pranked", "gone wrong", "secret room", "secret base", "hide and seek", "last to leave",
    "24 hours", "100 days", "noob", "hacker", "pro vs", "poor vs rich", "rich vs poor", "$1 vs", "millionaire", "mukbang",
    "reaction", "reacts", "try not to laugh", "funny moments", "troll", "trolling", "squid game", "build challenge",
    "seconds vs", "minute vs", "$10,000", "$100,000", "$1,000,000", "wins $",
]

/// Version 2 allowlist: a video must clearly be one of these, or it's blocked.
let allowedTopics = [
    // paper airplanes, drawing, arts & crafts
    "paper airplane", "paper plane", "paper jet", "origami", "how to draw", "learn to draw", "drawing", "draw",
    "directed drawing", "art lesson", "art for kids", "arts and crafts", "craft", "papercraft", "paper craft",
    // piano and learning a skill
    "piano lesson", "piano tutorial", "learn piano", "how to play piano", "play piano", "piano for beginners",
    "piano for kids", "easy piano", "music lesson", "music theory", "tutorial", "lesson", "how to make", "step by step",
    // science, space, What If
    "science", "experiment", "science max", "what if", "space", "planet", "solar system", "astronaut", "nasa", "rocket",
    "galaxy", "moon", "mars", "jupiter", "saturn", "black hole", "earth science", "volcano", "geology", "weather",
    // school subjects
    "math", "maths", "addition", "subtraction", "multiplication", "division", "fraction", "counting", "number bond",
    "reading", "read aloud", "read by", "read along", "storytime", "phonics", "spelling", "writing", "handwriting", "alphabet", "grammar",
]

/// What If and real space exploration count as science, even when the title sounds dramatic
/// ("What if you fell into a black hole?", "Could you survive on Mars?").
let spaceScienceTopics = [
    "what if", "space", "planet", "solar system", "astronaut", "nasa", "rocket", "galaxy", "galaxies", "universe",
    "black hole", "moon", "mars", "jupiter", "saturn", "venus", "mercury", "neptune", "uranus", "pluto", "comet",
    "asteroid", "meteor", "nebula", "star", "astronomy", "telescope", "spacecraft", "satellite", "space station",
    "exoplanet", "big bang", "sun",
]

/// Version 2: anything about video games is off-limits (no gameplay, POV, Let's Plays, game channels).
let gameTopics = [
    "minecraft", "roblox", "fortnite", "among us", "gameplay", "game play", "let's play", "lets play", "playthrough",
    "walkthrough", "speedrun", "speedrunner", "gamer", "gaming", "video game", "videogame", "pov", "mod", "mods",
    "modded", "bedwars", "skyblock", "pvp", "fnaf", "five nights", "poppy playtime", "rainbow friends", "banban",
    "sonic", "mario", "pokemon", "zelda", "call of duty", "gta", "fall guys", "stumble guys", "brookhaven", "adopt me",
    "toca boca", "geometry dash", "solar smash", "noob", "hacker", "admin commands", "one block", "herobrine",
]
/// Version 2: overstimulating / no-value signals (blocked, not fun time).
let overstimTopics = [
    "insane", "extreme", "craziest", "crazy", "wildest", "ytp", "youtube poop", "scream", "screaming", "survived",
    "survive", "last to", "overnight in", "chaos", "nuke", "nuking", "destroying", "eating challenge", "unboxing",
]
/// Titles that shout: mostly capital letters, "!!", or a pile of emoji.
func looksOverstimulating(_ title: String) -> Bool {
    let letters = title.filter(\.isLetter)
    let caps = letters.filter(\.isUppercase)
    let emoji = title.unicodeScalars.filter { $0.properties.isEmojiPresentation }.count
    return (letters.count >= 10 && Double(caps.count) / Double(letters.count) > 0.6)
        || title.contains("!!") || title.contains("?!") || emoji >= 3
}

/// True if any term appears in `text` as a whole word/phrase (plural "s"/"es" allowed). Terms with symbols use plain contains.
func matchesAny(_ text: String, _ terms: [String]) -> Bool {
    let lower = text.lowercased()
    return terms.contains { t in
        guard !t.isEmpty else { return false }
        if t.allSatisfy({ $0.isLetter || $0.isNumber || $0 == " " }) {
            let p = "\\b" + NSRegularExpression.escapedPattern(for: t) + "(?:s|es)?\\b"
            return lower.range(of: p, options: .regularExpression) != nil
        }
        return lower.contains(t)
    }
}

// MARK: - Helpers

struct Browser { let bundleID: String; let name: String; let safari: Bool }

let knownBrowsers = [
    Browser(bundleID: "com.google.Chrome", name: "Google Chrome", safari: false),
    Browser(bundleID: "com.brave.Browser", name: "Brave", safari: false),
    Browser(bundleID: "com.microsoft.edgemac", name: "Microsoft Edge", safari: false),
    Browser(bundleID: "company.thebrowser.Browser", name: "Arc", safari: false),
    Browser(bundleID: "com.apple.Safari", name: "Safari", safari: true),
]

/// Runs AppleScript in-process so macOS attributes the Automation permission to this app.
func runScript(_ src: String) -> (out: String?, err: Int?) {
    var err: NSDictionary?
    let out = NSAppleScript(source: src)?.executeAndReturnError(&err)
    if let err = err { return (nil, err[NSAppleScript.errorNumber] as? Int ?? -1) }
    return (out?.stringValue, nil)
}

func isYouTube(_ url: String) -> Bool { url.contains("youtube.com") || url.contains("youtu.be") }

func firstMatch(_ pattern: String, _ s: String) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern),
          let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
          let r = Range(m.range(at: 1), in: s) else { return nil }
    return String(s[r])
}

func videoID(_ url: String) -> String? {
    guard isYouTube(url) else { return nil }
    return firstMatch(#"(?:[?&]v=|/shorts/|youtu\.be/|/live/|/embed/)([A-Za-z0-9_-]{11})"#, url)
}

func unescapeJSON(_ s: String) -> String {
    (try? JSONSerialization.jsonObject(with: Data("\"\(s)\"".utf8), options: .fragmentsAllowed)) as? String ?? s
}

func fetchPage(_ url: String, _ done: @escaping (String) -> Void) {
    var req = URLRequest(url: URL(string: url)!, timeoutInterval: 15)
    req.setValue(kUA, forHTTPHeaderField: "User-Agent")
    req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
    req.setValue("CONSENT=YES+1", forHTTPHeaderField: "Cookie")
    URLSession.shared.dataTask(with: req) { data, _, _ in
        let s = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        DispatchQueue.main.async { done(s) }
    }.resume()
}

// MARK: - YouTube page cleanup (version 2)

/// Hides the algorithm: suggestions, Shorts, end screens, comments, and any thumbnail from a blocked channel or with
/// game / brain-rot words. Turns autoplay off and YouTube's Restricted Mode on. __RULES__ is filled in by the app.
let youtubeCleanerJS = #"""
(function(){
  window.__ttRules = __RULES__;
  try {  /* YouTube's own Restricted Mode: f2=8000000 in the PREF cookie (set once per tab) */
    var m = document.cookie.match(/(?:^|; )PREF=([^;]*)/), pref = m ? decodeURIComponent(m[1]) : '';
    if (pref.indexOf('f2=8000000') < 0 && !sessionStorage.getItem('ttRestricted')) {
      sessionStorage.setItem('ttRestricted', '1');
      pref = pref.replace(/(^|&)f2=[^&]*/g, '').replace(/^&/, '');
      document.cookie = 'PREF=' + (pref ? pref + '&' : '') + 'f2=8000000; domain=.youtube.com; path=/; max-age=31536000';
      location.reload(); return 'restricted';
    }
  } catch (e) {}
  if (window.__ttV === 2) return 'ok';
  window.__ttV = 2;
  var st = document.createElement('style');
  st.textContent = ['#related', 'ytd-watch-next-secondary-results-renderer', 'ytd-reel-shelf-renderer',
    'ytd-rich-shelf-renderer', 'ytd-rich-section-renderer', 'ytd-reel-item-renderer', 'ytm-shorts-lockup-view-model',
    'grid-shelf-view-model', '.ytp-endscreen-content', '.ytp-ce-element', '.ytp-pause-overlay', '.ytp-suggested-action',
    '#comments', 'ytd-chips-shelf-with-video-shelf-renderer', 'yt-chip-cloud-renderer',
    'ytd-guide-entry-renderer:has(a[title="Shorts"])', 'ytd-mini-guide-entry-renderer[aria-label="Shorts"]',
    'ytd-guide-entry-renderer:has(a[href^="/feed/trending"])', 'ytd-guide-entry-renderer:has(a[href^="/gaming"])',
    'ytd-guide-section-renderer:has(a[href^="/feed/explore"])',
    /* ads and promos (they advertise games too) */
    'ytd-ad-slot-renderer', 'ytd-search-pyv-renderer', 'ytd-in-feed-ad-layout-renderer', 'ytd-promoted-sparkles-web-renderer',
    'ytd-promoted-video-renderer', 'ytd-display-ad-renderer', 'ytd-banner-promo-renderer', 'ytd-statement-banner-renderer',
    '#masthead-ad', '#player-ads'].join(',') + '{display:none!important}';
  document.documentElement.appendChild(st);
  function bad(title, ch) {
    var R = window.__ttRules, c = ch.toLowerCase();
    if (R.channels.some(function (x) { return x && c.indexOf(x) >= 0; })) return true;
    if (window.__ttRe && window.__ttRe.test(title + ' | ' + ch)) return true;
    var L = title.replace(/[^A-Za-z]/g, ''), U = title.replace(/[^A-Z]/g, '');
    return (L.length >= 10 && U.length / L.length > 0.6) || title.indexOf('!!') >= 0;
  }
  function sweep() {
    var R = window.__ttRules, key = JSON.stringify(R.words);
    if (window.__ttKey !== key) {
      window.__ttKey = key;
      var parts = R.words.map(function (w) { return w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); });
      window.__ttRe = new RegExp('\\b(?:' + parts.join('|') + ')(?:s|es)?\\b', 'i');
    }
    document.querySelectorAll('ytd-video-renderer, ytd-rich-item-renderer, ytd-compact-video-renderer, ' +
      'ytd-grid-video-renderer, ytd-playlist-renderer, ytd-channel-renderer, ytd-radio-renderer, yt-lockup-view-model')
      .forEach(function (el) {
        var t = el.querySelector('#video-title, #video-title-link, .yt-lockup-metadata-view-model__title, #channel-title, h3');
        var c = el.querySelector('ytd-channel-name, #channel-name, .yt-content-metadata-view-model__metadata-text');
        var hide = bad(t ? t.textContent.trim() : '', c ? c.textContent.trim() : '') || !!el.querySelector('a[href^="/shorts/"]');
        el.style.display = hide ? 'none' : '';
      });
    var auto = document.querySelector('.ytp-autonav-toggle-button[aria-checked="true"]');
    if (auto) auto.click();
  }
  sweep(); setInterval(sweep, 800);
  return 'installed';
})()
"""#

// MARK: - Optional Claude AI judge (used only when the parent adds an Anthropic API key)

let aiRules = """
You screen YouTube videos for a parent of a 6-year-old. Use a strict ALLOWLIST: a video is allowed only if it is \
genuinely educational or tutorial quality, at a level right for a 6-7 year old, in one of these areas:
- paper airplanes (how to fold and fly them)
- drawing and arts & crafts lessons (e.g. Art for Kids Hub, how-to-draw, origami)
- learning piano or another real skill, taught as a lesson or tutorial (e.g. Hoffman Academy)
- science explained (e.g. Science Max, SciShow Kids), including "What If" videos and exploring space \
(planets, stars, black holes, astronauts, rockets)
- school subjects: math, reading, writing, spelling, phonics

Everything else is blocked, including: any entertainment (even gentle cartoons, vlogs, toy or preschool shows like \
Blippi), anything about video games, music videos and performances that aren't lessons, challenges, pranks, \
reactions, overstimulating or flashy content, anything above a 6-7 year old's level, and anything scary or mean.

Answer "learning" only for clear educational/tutorial content in the list above; otherwise "blocked". When in doubt, \
"blocked". Give a short, kid-friendly reason (under 15 words).
"""

/// OpenRouter model for the smart filter (parent can change it in the controls).
/// Default: Perplexity Decider V1.2, a decision model that answers with a probability instead of text.
var aiModel: String {
    let m = UserDefaults.standard.string(forKey: "aiModel")?.trimmingCharacters(in: .whitespaces) ?? ""
    return m.isEmpty ? "perplexity/pplx-decider-v1.2" : m
}
let kChatFallbackModel = "anthropic/claude-haiku-5.5"
let kDecisionThreshold = 0.6     // allowed only when the decision model is at least 60% sure

/// Decision models (Perplexity Decider, Cloudflare Clef, TypeSafe Jev…) use OpenRouter's Decisions API, not chat.
func isDecisionModel(_ m: String) -> Bool {
    let m = m.lowercased()
    return m.contains("pplx-decider") || m.hasPrefix("cloudflare/clef") || m.hasPrefix("typesafe/jev") || m.contains("decision")
}

/// Asks an OpenRouter decision model one yes/no question: is this video on the allowlist?
func decideClassify(_ v: VideoInfo, key: String, model: String, done: @escaping (VideoKind?, String) -> Void) {
    let body: [String: Any] = [
        "model": model,
        "state": ["video": ["title": v.title, "channel": v.channel, "youtube_category": v.category,
                            "tags": String(v.tags.prefix(400)), "description": v.description]],
        "questions": ["allowed": [
            "type": "noul",
            "instructions": "Is the video in `video` genuinely educational or tutorial content, right for a 6-7 year old, in one of the parent's allowed areas? Judge from its title, channel, category, tags and description.",
            "criteria": [
                "true": "Yes: a real lesson, tutorial or explanation for a young child about paper airplanes; drawing or arts and crafts (like Art for Kids Hub or origami); learning piano or another skill (like Hoffman Academy); science explained, including What If videos and exploring space (planets, stars, black holes, astronauts, rockets) (like Science Max, SciShow Kids or What If); or math, reading, writing, spelling or phonics.",
                "false": "No: any entertainment (cartoons, vlogs, toy or preschool shows like Blippi, music videos or performances that aren't lessons), anything about video games, challenges, pranks, reactions, flashy or overstimulating content, anything above a 6-7 year old's level, or anything scary or mean.",
            ],
        ] as [String: Any]],
    ]
    var req = URLRequest(url: URL(string: "https://openrouter.ai/api/alpha/decisions")!, timeoutInterval: 30)
    req.httpMethod = "POST"
    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    req.setValue("https://github.com/jbellsolutions/tube-timer", forHTTPHeaderField: "HTTP-Referer")
    req.setValue("Tube Timer", forHTTPHeaderField: "X-Title")
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    URLSession.shared.dataTask(with: req) { data, _, _ in
        var kind: VideoKind?, reason = ""
        if let data = data, let resp = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let answer = (resp["answers"] as? [String: Any])?["allowed"] as? [String: Any],
           let p = (answer["noul"] as? NSNumber)?.doubleValue {
            kind = p >= kDecisionThreshold ? .learning : .blocked
            reason = "\(Int((p * 100).rounded()))% sure it's on the learning list"
        }
        DispatchQueue.main.async { done(kind, reason) }
    }.resume()
}

/// Classifies a video with the smart filter. OpenRouter key + decision model -> Decisions API (Haiku if that fails);
/// otherwise Claude Haiku by chat. Calls back on the main thread with nil if anything goes wrong.
func aiClassify(_ v: VideoInfo, key: String, done: @escaping (VideoKind?, String) -> Void) {
    if key.hasPrefix("sk-or-") && isDecisionModel(aiModel) {
        decideClassify(v, key: key, model: aiModel) { kind, reason in
            if kind != nil { done(kind, reason) } else { chatClassify(v, key: key, model: kChatFallbackModel, done: done) }
        }
    } else {
        chatClassify(v, key: key, model: isDecisionModel(aiModel) ? kChatFallbackModel : aiModel, done: done)
    }
}

/// Asks a chat model (Claude Haiku by default). An OpenRouter key (sk-or-…) goes through OpenRouter; an Anthropic
/// key (sk-ant-…) goes straight to Anthropic.
func chatClassify(_ v: VideoInfo, key: String, model: String, done: @escaping (VideoKind?, String) -> Void) {
    let video = """
    Title: \(v.title)
    Channel: \(v.channel)
    YouTube category: \(v.category)
    Tags: \(v.tags.prefix(400))
    Description: \(v.description)
    """
    let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "verdict": ["type": "string", "enum": ["learning", "blocked"]] as [String: Any],
            "reason": ["type": "string"],
        ],
        "required": ["verdict", "reason"],
        "additionalProperties": false,
    ]
    let openRouter = key.hasPrefix("sk-or-")
    var req: URLRequest
    let body: [String: Any]
    if openRouter {
        req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!, timeoutInterval: 30)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("https://github.com/jbellsolutions/tube-timer", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("Tube Timer", forHTTPHeaderField: "X-Title")
        body = [
            "model": model,
            "max_tokens": 1024,
            "reasoning": ["effort": "low"],
            "messages": [["role": "system", "content": aiRules], ["role": "user", "content": video]],
            "response_format": ["type": "json_schema",
                                "json_schema": ["name": "verdict", "strict": true, "schema": schema] as [String: Any]] as [String: Any],
        ]
    } else {
        req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 30)
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        body = [
            "model": "claude-haiku-5-5",
            "max_tokens": 1024,
            "system": aiRules,
            "messages": [["role": "user", "content": video]],
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema] as [String: Any]] as [String: Any],
        ]
    }
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    URLSession.shared.dataTask(with: req) { data, _, _ in
        var kind: VideoKind?, reason = ""
        var text: String?
        if let data = data, let resp = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if openRouter {
                text = ((resp["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
            } else if resp["stop_reason"] as? String != "refusal" {
                text = (resp["content"] as? [[String: Any]])?.first(where: { $0["type"] as? String == "text" })?["text"] as? String
            }
        }
        // The answer is JSON; take the {...} part in case anything else came with it.
        if let t = text, let a = t.firstIndex(of: "{"), let b = t.lastIndex(of: "}"),
           let out = try? JSONSerialization.jsonObject(with: Data(t[a...b].utf8)) as? [String: Any] {
            reason = out["reason"] as? String ?? ""
            switch out["verdict"] as? String {
            case "learning": kind = .learning
            case "blocked", "fun": kind = .blocked
            default: break
            }
        }
        DispatchQueue.main.async { done(kind, reason) }
    }.resume()
}

/// A JavaScript string literal for text passed into a page.
func jsString(_ s: String) -> String {
    (try? String(data: JSONSerialization.data(withJSONObject: [s]), encoding: .utf8)).flatMap { $0 }.map { String($0.dropFirst().dropLast()) } ?? "''"
}

func fmt(_ secs: Double) -> String {
    let s = Int(max(0, secs.rounded())), h = s / 3600, m = (s % 3600) / 60, x = s % 60
    if h > 0 { return "\(h)h \(m)m" }
    return m >= 10 ? "\(m)m" : "\(m)m \(x)s"
}

/// Countdown style: "23:41" or "1:02:03".
func clockStr(_ secs: Double) -> String {
    let s = Int(max(0, secs.rounded())), h = s / 3600, m = (s % 3600) / 60, x = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, x) : String(format: "%d:%02d", m, x)
}

let speaker = NSSpeechSynthesizer()
func speak(_ text: String) { speaker.stopSpeaking(); speaker.startSpeaking(text) }

// MARK: - Open at login (LaunchAgent that just opens the app)

let loginLabel = "com.tubetimer.app"
let loginPlist = NSHomeDirectory() + "/Library/LaunchAgents/\(loginLabel).plist"
var opensAtLogin: Bool { FileManager.default.fileExists(atPath: loginPlist) }
func setOpenAtLogin(_ on: Bool) {
    if on {
        try? FileManager.default.createDirectory(atPath: (loginPlist as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        let plist: NSDictionary = [
            "Label": loginLabel,
            "ProgramArguments": ["/usr/bin/open", "-g", "-a", Bundle.main.bundlePath, "--args", "--login"],
            "RunAtLoad": true,
        ]
        plist.write(toFile: loginPlist, atomically: true)
    } else {
        try? FileManager.default.removeItem(atPath: loginPlist)
    }
}

// MARK: - Suggested learning videos

struct Suggestion { let id, title, channel: String }

final class Suggestions {
    static let shared = Suggestions()
    private(set) var pool: [Suggestion] = []
    private(set) var channelNames: Set<String> = []  // lowercased, always allowed

    func refresh() {
        var fresh: [Suggestion] = [], names = Set<String>(), left = content.channelHandles.count
        for handle in content.channelHandles {
            fetchPage("https://www.youtube.com/@\(handle)/videos") { [weak self] html in
                let (name, vids) = Self.parse(html)
                if let name = name { names.insert(name.lowercased()) }
                fresh += vids.prefix(20).map { Suggestion(id: $0.0, title: $0.1, channel: name ?? handle) }
                left -= 1
                if left == 0, let self = self {
                    if !fresh.isEmpty { self.pool = fresh }
                    self.channelNames.formUnion(names)
                }
            }
        }
    }

    /// Pulls (channel name, [(videoId, title)]) out of a channel's /videos page.
    static func parse(_ html: String) -> (String?, [(String, String)]) {
        guard let a = html.range(of: "var ytInitialData = "),
              let b = html.range(of: ";</script>", range: a.upperBound..<html.endIndex),
              let obj = try? JSONSerialization.jsonObject(with: Data(html[a.upperBound..<b.lowerBound].utf8)) else { return (nil, []) }
        var vids: [(String, String)] = []
        func walk(_ o: Any) {
            if let d = o as? [String: Any] {
                if let l = d["lockupViewModel"] as? [String: Any],
                   l["contentType"] as? String == "LOCKUP_CONTENT_TYPE_VIDEO", let id = l["contentId"] as? String,
                   let meta = (l["metadata"] as? [String: Any])?["lockupMetadataViewModel"] as? [String: Any],
                   let title = (meta["title"] as? [String: Any])?["content"] as? String {
                    vids.append((id, title))
                }
                d.values.forEach(walk)
            } else if let arr = o as? [Any] {
                arr.forEach(walk)
            }
        }
        walk(obj)
        let name = (((obj as? [String: Any])?["metadata"] as? [String: Any])?["channelMetadataRenderer"] as? [String: Any])?["title"] as? String
        return (name, vids)
    }
}

// MARK: - Limiter (rules + state)

struct VideoInfo {
    let id, title, channel, category: String
    var tags = ""
    var description = ""
    var familySafe = true
}
enum VideoKind { case learning, fun, blocked }

final class Limiter: ObservableObject {
    static let shared = Limiter()
    private let d = UserDefaults.standard

    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "enabled"); if !enabled { party.hide(); nope.hide() }; changed() } }
    @Published var dailyMin: Int { didSet { d.set(dailyMin, forKey: "dailyMin"); changed() } }
    @Published var sessionMin: Int { didSet { d.set(sessionMin, forKey: "sessionMin"); changed() } }
    @Published var lockoutMin: Int { didSet { d.set(lockoutMin, forKey: "lockoutMin"); changed() } }
    @Published var filterOn: Bool { didSet { d.set(filterOn, forKey: "filterOn") } }
    @Published var allowedCats: [String] { didSet { d.set(allowedCats, forKey: "allowedCats") } }
    @Published var allowChannels: String { didSet { d.set(allowChannels, forKey: "allowChannels") } }
    @Published var blockChannels: String { didSet { d.set(blockChannels, forKey: "blockChannels") } }
    @Published var allowTopics: String { didSet { d.set(allowTopics, forKey: "allowTopics") } }
    @Published var blockTopics: String { didSet { d.set(blockTopics, forKey: "blockTopics") } }
    @Published var apiKey: String { didSet { d.set(apiKey, forKey: "apiKey") } }
    @Published var youtubeHome: String { didSet { d.set(youtubeHome, forKey: "youtubeHome") } }
    @Published var onYouTube = false          // a YouTube tab is in front (timer box shows)
    @Published var playDetection = "basic"    // "precise" when Chrome lets us check the video itself
    var aiVerdicts: [String: String]          // video ID -> learning / fun / blocked (from Claude)
    var aiReasons: [String: String] = [:]
    @Published var earnedToday: Int            // video + quiz challenges passed today (max 2)
    @Published var earnLog: [String]           // his "explain it" answers, for the parent to read
    @Published var funMin: Int { didSet { d.set(funMin, forKey: "funMin"); changed() } }
    // Saturday + Sunday use these instead.
    @Published var weekendFunMin: Int { didSet { d.set(weekendFunMin, forKey: "weekendFunMin"); changed() } }
    @Published var weekendDailyMin: Int { didSet { d.set(weekendDailyMin, forKey: "weekendDailyMin"); changed() } }
    @Published var weekendSessionMin: Int { didSet { d.set(weekendSessionMin, forKey: "weekendSessionMin"); changed() } }
    var funMinToday: Int { isWeekend ? weekendFunMin : funMin }
    var dailyMinToday: Int { dailyMin }       // version 2: weekends are the same as school days
    var sessionMinToday: Int { sessionMin }
    @Published var pin: String { didSet { d.set(pin, forKey: "pin") } }
    @Published var kidPin: String { didSet { d.set(kidPin, forKey: "kidPin") } }
    @Published var kidExtrasToday: Int = 0
    @Published var actionMessage = ""          // confirmation shown under the +10 / Reset buttons
    var bedtimePassUntil: Double = 0           // +10 during YouTube-off hours gives a short pass
    @Published var funSec: Double
    @Published var watchingFun = false
    var approvedFun: Set<String>   // entertainment videos he chose to spend fun time on today
    var funWarned: Bool
    var lastTickAt = Date().timeIntervalSince1970
    private var pendingFun: (id: String, url: String, browser: String)?

    @Published var dailySec: Double
    @Published var sessionSec: Double
    @Published var lockedUntil: Double
    @Published var lockReason: String
    @Published var watching = false
    @Published var needsPermission: [String] = []   // browser names macOS hasn't allowed yet
    @Published var recentBlocks: [String] = []
    var lockIsDaily: Bool
    var dailyBonus: Double
    var sessionBonus: Double
    var lastWatch: Double
    var day: String
    var warned: Bool
    var partyUntil: Double = 0
    var partyIsPreview = false
    var nopeIsPreview = false
    var earnIsPreview = false
    var nopeBrowser: String?
    private var verdicts: [String: VideoInfo] = [:]
    private var pending: Set<String> = []
    private var failedAt: [String: Double] = [:]
    private var lastTick = Date().timeIntervalSince1970
    var onChange: (() -> Void)?

    init() {
        d.register(defaults: kScheduleDefaults)
        d.register(defaults: [
            "enabled": true, "dailyMin": 60, "sessionMin": 30, "lockoutMin": 30,
            "filterOn": true,
            "allowedCats": ["Education", "Science & Technology", "Music", "Howto & Style", "Pets & Animals",
                            "Autos & Vehicles", "Travel & Events"],
            "allowChannels": "", "blockChannels": "",
            "funMin": 20,
            "weekendFunMin": 120, "weekendDailyMin": 120, "weekendSessionMin": 60,
            "allowTopics": "paper airplane, paper plane, paper jet, origami, how to draw, drawing, coloring, colouring, folding surprise, arts and crafts, craft",
        ])
        allowTopics = d.string(forKey: "allowTopics") ?? ""
        blockTopics = d.string(forKey: "blockTopics")
            ?? "kiss, kissed, kissing, crush, dating, girlfriend, boyfriend, sexy, twerk, nsfw, 18+, horror, jumpscare, gore"
        apiKey = d.string(forKey: "apiKey") ?? ""
        youtubeHome = d.string(forKey: "youtubeHome") ?? "https://www.youtube.com/results?search_query=science+for+kids"
        aiVerdicts = d.dictionary(forKey: "aiVerdicts") as? [String: String] ?? [:]
        earnedToday = d.integer(forKey: "earnedToday")
        earnLog = d.stringArray(forKey: "earnLog") ?? []
        funMin = d.integer(forKey: "funMin")
        weekendFunMin = d.integer(forKey: "weekendFunMin")
        weekendDailyMin = d.integer(forKey: "weekendDailyMin")
        weekendSessionMin = d.integer(forKey: "weekendSessionMin")
        pin = d.string(forKey: "pin") ?? ""
        kidPin = d.string(forKey: "kidPin") ?? "1234"
        kidExtrasToday = d.integer(forKey: "kidExtrasToday")
        bedtimePassUntil = d.double(forKey: "bedtimePassUntil")
        funSec = d.double(forKey: "funSec")
        approvedFun = Set(d.stringArray(forKey: "approvedFun") ?? [])
        funWarned = d.bool(forKey: "funWarned")
        enabled = d.bool(forKey: "enabled")
        dailyMin = d.integer(forKey: "dailyMin")
        sessionMin = d.integer(forKey: "sessionMin")
        lockoutMin = d.integer(forKey: "lockoutMin")
        filterOn = d.bool(forKey: "filterOn")
        var cats = d.stringArray(forKey: "allowedCats") ?? []
        if !d.bool(forKey: "relaxedFilterV1") {  // one-time: be more relaxed about learning-ish categories
            for c in ["Howto & Style", "Pets & Animals", "Autos & Vehicles", "Travel & Events"] where !cats.contains(c) {
                cats.append(c)
            }
            d.set(cats, forKey: "allowedCats")
            d.set(true, forKey: "relaxedFilterV1")
        }
        allowedCats = cats.filter { $0 != "Gaming" }
        allowChannels = d.string(forKey: "allowChannels") ?? ""
        var blocked = d.string(forKey: "blockChannels") ?? ""
        if !d.bool(forKey: "benAndCamFunV1") {  // one-time: Ben and Cam moves from "blocked" to fun time
            blocked = blocked.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.lowercased() != "ben and cam" }.joined(separator: ", ")
            d.set(blocked, forKey: "blockChannels")
            d.set(true, forKey: "benAndCamFunV1")
        }
        if !d.bool(forKey: "v2Defaults") {  // one-time for version 2
            var names = blocked.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            for n in ["Ben Azelart", "Brent Rivera", "Lexi Rivera", "Cash", "Ben and Cam"]
            where !names.contains(where: { $0.lowercased() == n.lowercased() }) { names.append(n) }
            blocked = names.joined(separator: ", ")
            d.set(blocked, forKey: "blockChannels")
            d.set(true, forKey: "v2Defaults")
        }
        if !d.bool(forKey: "v2BlockBlippi") {
            if !blocked.lowercased().contains("blippi") { blocked += blocked.isEmpty ? "Blippi" : ", Blippi" }
            d.set(blocked, forKey: "blockChannels")
            d.set(true, forKey: "v2BlockBlippi")
        }
        blockChannels = blocked
        dailySec = d.double(forKey: "dailySec")
        sessionSec = d.double(forKey: "sessionSec")
        lockedUntil = d.double(forKey: "lockedUntil")
        lockReason = d.string(forKey: "lockReason") ?? ""
        lockIsDaily = d.bool(forKey: "lockIsDaily")
        dailyBonus = d.double(forKey: "dailyBonus")
        sessionBonus = d.double(forKey: "sessionBonus")
        lastWatch = d.double(forKey: "lastWatch")
        day = d.string(forKey: "day") ?? ""
        warned = d.bool(forKey: "warned")
    }

    var now: Double { Date().timeIntervalSince1970 }
    var isLocked: Bool { now < lockedUntil }
    var dailyLimit: Double { Double(dailyMinToday * 60) + dailyBonus }
    var sessionLimit: Double { Double(sessionMinToday * 60) + sessionBonus }
    var timeLeft: Double { max(0, min(dailyLimit - dailySec, sessionLimit - sessionSec)) }
    var funLimit: Double { Double((funMinToday + earnedToday * kEarnMinutes) * 60) }
    var funLeft: Double { max(0, funLimit - funSec) }
    var canEarn: Bool { earnedToday < kMaxEarnsPerDay }
    /// Smooth per-second countdowns for the on-screen timer (state itself updates every 5 s).
    var liveTimeLeft: Double { max(0, timeLeft - (watching ? now - lastTickAt : 0)) }
    var liveFunLeft: Double { max(0, funLeft - (watchingFun ? now - lastTickAt : 0)) }

    var menuTitle: String {
        if !enabled { return "off" }
        if isLocked { return "🔒 " + fmt(lockedUntil - now) }
        return fmt(timeLeft)
    }

    func start() {
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    func tick() {
        let t = now
        let dt = min(max(t - lastTick, 0), 15)  // cap so sleep/wake doesn't count as watching
        lastTick = t
        lastTickAt = t
        rollDay()
        defer { save(); changed() }
        watchingFun = false

        if party.isShowing && (t >= partyUntil || (!partyIsPreview && !isLocked)) { party.hide() }
        guard enabled else { watching = false; onYouTube = false; return }
        let running = runningBrowsers()

        // YouTube is off overnight (default 9 PM–6 AM), no matter what.
        if inYouTubeOffHours && t >= bedtimePassUntil {
            let end = offHoursEnd()
            if lockedUntil < end {
                lockedUntil = end; lockIsDaily = false
                lockReason = "YouTube is off from \(offHoursText). Good night! 🌙"
            }
        }

        if isLocked {
            watching = false; onYouTube = false
            if closeTabs(running, matching: nil) > 0 && !party.isShowing {
                partyUntil = min(lockedUntil, t + kReshowSec)
                showParty()
            }
            return
        }
        if !lockReason.isEmpty { lockReason = ""; lockIsDaily = false }  // lock just expired

        var ytTabs: [(Browser, String)] = []
        for b in running { if let u = activeURL(b), isYouTube(u) { ytTabs.append((b, u)) } }
        if filterOn {   // version 2: no algorithm feeds, and a cleaned-up page
            ytTabs = ytTabs.filter { !steerAwayFromFeeds($0.0, $0.1) }
            for (b, _) in ytTabs { cleanUpPage(b) }
        }
        onYouTube = !ytTabs.isEmpty
        if filterOn && !nope.isShowing && !earn.isShowing {
            for (b, u) in ytTabs { if let id = videoID(u) { checkVideo(id, url: u, in: b) } }
        }
        // Only count time while a video is actually playing (not paused, not just browsing).
        var mediaActive: Bool?
        let playingTabs = ytTabs.filter { (b, _) in
            if let p = isPlaying(b) { playDetection = "precise"; return p }
            playDetection = "basic"
            if mediaActive == nil { mediaActive = browserMediaActive() }
            return mediaActive!
        }
        watching = !playingTabs.isEmpty
        guard watching, !nope.isShowing, !earn.isShowing else { return }
        let funTab = filterOn ? playingTabs.first { videoID($0.1).map { approvedFun.contains($0) } ?? false } : nil
        watchingFun = funTab != nil

        if lastWatch > 0 && t - lastWatch > kGapSec { sessionSec = 0; sessionBonus = 0; warned = false }
        lastWatch = t
        sessionSec += dt
        dailySec += dt

        let dayLeft = dailyLimit - dailySec, sessLeft = sessionLimit - sessionSec
        if dayLeft <= 0 {
            lock(until: nextMidnight(), daily: true,
                 reason: "You used all \(dailyMinToday) minutes of YouTube for today. See you tomorrow!")
        } else if sessLeft <= 0 {
            lock(until: t + Double(lockoutMin * 60), daily: false,
                 reason: "That's \(sessionMinToday) minutes in a row. Take a \(lockoutMin) minute break!")
        } else if min(dayLeft, sessLeft) <= kWarnSec && !warned {
            warned = true
            showWarning()
        }

        // Entertainment ("fun") time
        guard let (fb, fu) = funTab, !isLocked, let fid = videoID(fu) else { return }
        if !inFunWindow, let v = verdicts[fid] {      // 8:30 PM: fun time is over for today
            watchingFun = false
            blockVideo(v, in: fb, mode: "notnow")
            return
        }
        funSec += dt
        if funLeft <= 0, let v = verdicts[fid] {
            watchingFun = false
            blockVideo(v, in: fb, mode: "funover")
        } else if funLeft <= kWarnSec && !funWarned {
            funWarned = true
            banner.show("🎉 1 minute of fun time left!")
            speak("One minute of fun time left!")
        }
    }

    func lock(until: Double, daily: Bool, reason: String) {
        lockedUntil = until; lockIsDaily = daily; lockReason = reason
        sessionSec = 0; sessionBonus = 0; warned = false
        nope.hide()
        _ = closeTabs(runningBrowsers(), matching: nil)
        partyUntil = min(until, now + Double(lockoutMin * 60))
        showParty()
    }

    func showParty(preview: Bool = false) {
        party.hide()
        let t = now
        partyIsPreview = preview
        if preview { partyUntil = t + 20 }
        party.show(params: [
            "until": preview ? t + 60 : lockedUntil,
            "partyUntil": partyUntil,
            "reason": preview ? "This is just a preview. It closes by itself in 20 seconds." : lockReason,
            "daily": preview ? false : lockIsDaily,
            "songs": content.songs.shuffled(),
            "musicSeconds": kPartyMusicSeconds,
        ])
    }

    func showWarning() {
        banner.show("⏰ Hey! You've got 1 minute left for YouTube!")
        speak("Hey! You've got one minute left for YouTube.")
    }

    /// mode: "nope" (not allowed), "funover" (fun time used up) or "ask" (are you sure you want to use fun time?)
    func showNope(_ v: VideoInfo, mode: String = "nope", preview: Bool = false) {
        party.hide(); nope.hide()
        nopeIsPreview = preview
        let skin = d.integer(forKey: "skin") + 1
        d.set(skin, forKey: "skin")
        nope.show(params: ["mode": mode, "channel": v.channel, "category": v.category, "title": v.title, "skin": skin,
                           "funLeft": funLeft, "funMin": Int(funLimit / 60),
                           "canEarn": canEarn, "earnMinutes": kEarnMinutes,
                           "slots": content.slots, "funWindow": funWindowText])
        switch mode {
        case "ask": speak("Hold up! That's an entertainment video. Are you sure you want to use your fun time?")
        case "funover": speak("Ah ah ah! Your fun time is all used up for today!")
        case "notnow": speak("Ah ah ah! Fun videos are only from \(timeText(kFunStart)) to \(timeText(kFunEnd)).")
        default: speak("Ah ah ah! Ah ah ah! You didn't say the magic word!")
        }
    }

    /// Opens the "earn fun time" screen: a learning video plays inside the app, then 5 questions.
    func showEarn(preview: Bool = false) {
        let all = content.challenges
        guard canEarn || preview, !all.isEmpty else { return }
        nope.hide(); party.hide(); earn.hide()
        earnIsPreview = preview
        // Rotate through the challenges; quitting halfway gives the same one next time.
        let challenge = all[d.integer(forKey: "earnIndex") % all.count]
        earn.show(params: ["challenge": challenge, "earnMinutes": kEarnMinutes, "used": earnedToday, "inWindow": inFunWindow,
                           "funWindow": funWindowText])
    }

    /// He watched the video and passed the questions.
    func completeEarn(explanation: String) {
        guard !earnIsPreview else { return }
        let all = content.challenges
        let i = d.integer(forKey: "earnIndex")
        let title = all.isEmpty ? "" : all[i % all.count]["title"] as? String ?? ""
        d.set(i + 1, forKey: "earnIndex")
        earnedToday += 1
        funWarned = false
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"
        earnLog.insert("\(f.string(from: Date())) · \(title)\n“\(explanation)”", at: 0)
        if earnLog.count > 20 { earnLog.removeLast() }
        save(); changed()
        speak("You earned \(kEarnMinutes) more minutes of fun time!")
    }

    private var pinFails = 0
    private var pinBlockedUntil: Double = 0

    /// The 🔒 Parent button on a lockout screen: check the PIN, then end the break / close the screen, or turn Tube Timer off.
    func parentAction(_ value: String, from overlay: Overlay) {
        guard let data = value.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
        if now < pinBlockedUntil {
            overlay.evalJS("parentResult(false, 'Too many wrong tries. Wait a few minutes.')"); return
        }
        if o["pin"] == kidPin && !kidPin.isEmpty && o["pin"] != pin {
            pinFails = 0
            if o["action"] == "kid10" {
                let msg = kidExtra()
                if kidExtrasToday > 0 && msg.hasPrefix("+10") { banner.show("🧒 " + msg) }
                else { overlay.evalJS("parentResult(false, \(jsString(msg)))") }
            } else {
                overlay.evalJS("parentResult(false, 'The kid PIN can only add 10 minutes.')")
            }
            return
        }
        guard !pin.isEmpty, o["pin"] == pin else {
            pinFails += 1
            if pinFails >= 3 { pinFails = 0; pinBlockedUntil = now + 5 * 60 }
            overlay.evalJS("parentResult(false, 'Wrong PIN')"); return
        }
        pinFails = 0
        if o["action"] == "kid10" {
            addExtra()                      // parent PIN: +10 with no daily limit
        } else if o["action"] == "off" {
            enabled = false                 // hides every overlay; turn back on from the controls
        } else if overlay === party {
            lockedUntil = 0; lockReason = ""; lockIsDaily = false
            party.hide()
        } else {
            overlay.hide()
        }
        save(); changed()
    }

    /// He said "yes, use my fun time" on the ask screen.
    func approveFun() {
        nope.hide()
        guard !nopeIsPreview, let p = pendingFun, let url = URL(string: p.url) else { return }
        pendingFun = nil
        approvedFun.insert(p.id)
        nopeBrowser = p.browser
        save()
        openInBrowser(url)
    }

    /// Called when the kid picks a suggestion (or a search) on the "Ah ah ah" screen.
    func pickFromNope(_ url: URL) {
        nope.hide()
        guard !nopeIsPreview else { return }
        openInBrowser(url)
    }

    private func openInBrowser(_ url: URL) {
        if let id = nopeBrowser, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// Unlocks and adds 10 minutes to today and to this sitting. During YouTube-off hours it's a 10-minute pass.
    func addExtra() {
        let t = now
        lockedUntil = 0; lockReason = ""; lockIsDaily = false; warned = false
        dailyBonus = max(dailyBonus, dailySec - Double(dailyMinToday * 60)) + kExtraSec      // also covers going over
        sessionBonus = max(sessionBonus, sessionSec - Double(sessionMinToday * 60)) + kExtraSec
        if inYouTubeOffHours { bedtimePassUntil = max(bedtimePassUntil, t) + kExtraSec }
        party.hide(); nope.hide()
        flash("✅ Added 10 minutes. \(fmt(timeLeft)) left now.")
        save(); changed()
    }

    /// The kid PIN: +10 minutes, twice a day. Returns a message for the kid.
    @discardableResult
    func kidExtra() -> String {
        guard kidExtrasToday < kKidExtrasPerDay else {
            return "You already used your \(kKidExtrasPerDay) extra 10 minutes today."
        }
        kidExtrasToday += 1
        addExtra()
        return "+10 minutes! (\(kKidExtrasPerDay - kidExtrasToday) left today)"
    }

    private func flash(_ text: String) {
        actionMessage = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.actionMessage == text { self?.actionMessage = "" }
        }
    }

    func resetToday() {
        dailySec = 0; sessionSec = 0; dailyBonus = 0; sessionBonus = 0
        funSec = 0; approvedFun = []; funWarned = false; earnedToday = 0
        lockedUntil = 0; lockReason = ""; lockIsDaily = false; warned = false
        bedtimePassUntil = 0
        party.hide(); nope.hide()
        flash("✅ Today's time is reset. \(fmt(timeLeft)) left.")
        save(); changed()
    }

    // MARK: video filter

    private func list(_ s: String) -> [String] {
        s.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Hard rules that always win (allow/block lists, family-safe flag). nil = rules don't decide.
    func ruleKind(_ v: VideoInfo) -> VideoKind? {
        let ch = v.channel.lowercased()
        if content.allowedVideoIDs.contains(v.id) { return .learning }
        if list(blockChannels).contains(where: { ch.contains($0) }) { return .blocked }
        // Title only: creators stuff tags with other people's names ("ben azelart girlfriend"), which isn't the video.
        if !v.familySafe || matchesAny(v.title, list(blockTopics)) { return .blocked }
        if list(allowChannels).contains(where: { ch.contains($0) }) || Suggestions.shared.channelNames.contains(ch)
            || content.alwaysAllowedChannels.contains(ch) { return .learning }
        return nil
    }

    func kind(_ v: VideoInfo) -> VideoKind {
        if let k = ruleKind(v) { return k }
        switch aiVerdicts[v.id] {
        case "learning": return .learning
        case "fun", "blocked": return .blocked
        default: break
        }
        // Version 2 allowlist (no AI verdict): games, brain-rot and shouting are out; then the video has to clearly
        // be paper airplanes, drawing/crafts, piano or a skill tutorial, science/space/What If, or a school subject.
        let titleAndChannel = v.title + " | " + v.channel
        if v.category == "Gaming" || matchesAny(titleAndChannel, gameTopics) { return .blocked }
        if matchesAny(v.title, spaceScienceTopics) && !matchesAny(titleAndChannel, junkTopics) { return .learning }
        if matchesAny(titleAndChannel, junkTopics + overstimTopics) || looksOverstimulating(v.title) { return .blocked }
        if matchesAny(v.title, allowedTopics + list(allowTopics)) { return .learning }
        return .blocked
    }

    private func handle(_ v: VideoInfo, url: String, in b: Browser) {
        switch kind(v) == .fun ? .blocked : kind(v) {
        case .learning: return
        case .blocked: blockVideo(v, in: b, mode: "nope")
        case .fun:   // (not used in version 2; kept so version 1's flow still compiles)
            if !inFunWindow { blockVideo(v, in: b, mode: "notnow") }
            else if funLeft <= 0 { blockVideo(v, in: b, mode: "funover") }
            else if !approvedFun.contains(v.id) {
                _ = closeTabs(runningBrowsers(), matching: v.id)
                pendingFun = (v.id, url, b.bundleID)
                nopeBrowser = b.bundleID
                showNope(v, mode: "ask")
            }
        }
    }

    private func checkVideo(_ id: String, url: String, in b: Browser) {
        if content.allowedVideoIDs.contains(id) { return }
        if let v = verdicts[id] {
            handle(v, url: url, in: b)
            return
        }
        guard !pending.contains(id), now - (failedAt[id] ?? 0) > 60 else { return }
        pending.insert(id)
        fetchPage("https://www.youtube.com/watch?v=\(id)") { [weak self] html in
            guard let self = self else { return }
            self.pending.remove(id)
            let str = #""((?:[^"\\]|\\.)*)""#
            guard let category = firstMatch(#""category":"# + str, html).map(unescapeJSON),
                  let channel = firstMatch(#""ownerChannelName":"# + str, html).map(unescapeJSON) else {
                self.failedAt[id] = self.now  // couldn't tell - let it play, retry in a minute
                return
            }
            let title = firstMatch(#""videoDetails":\{"videoId":"[^"]+","title":"# + str, html).map(unescapeJSON) ?? ""
            var v = VideoInfo(id: id, title: title, channel: channel, category: category)
            if let kw = firstMatch(#""keywords":\[([^\]]*)\]"#, html),
               let arr = try? JSONSerialization.jsonObject(with: Data("[\(kw)]".utf8)) as? [String] {
                v.tags = arr.joined(separator: ", ")
            }
            v.description = String((firstMatch(#""shortDescription":"# + str, html).map(unescapeJSON) ?? "").prefix(600))
            v.familySafe = firstMatch(#""isFamilySafe":(true|false)"#, html) != "false"
            let decide = {
                self.verdicts[id] = v
                if self.enabled && self.filterOn && !self.isLocked && !nope.isShowing && !party.isShowing {
                    self.handle(v, url: url, in: b)
                }
            }
            // Ask Claude only when the simple rules can't settle it (saves money, and their answer is final anyway).
            if !self.apiKey.isEmpty && self.aiVerdicts[id] == nil && self.ruleKind(v) == nil {
                aiClassify(v, key: self.apiKey) { kind, reason in
                    if let kind = kind {
                        self.aiVerdicts[id] = kind == .learning ? "learning" : kind == .fun ? "fun" : "blocked"
                        self.aiReasons[id] = reason
                        self.d.set(self.aiVerdicts, forKey: "aiVerdicts")
                    }
                    decide()
                }
            } else {
                decide()
            }
        }
    }

    private func blockVideo(_ v: VideoInfo, in b: Browser, mode: String) {
        _ = closeTabs(runningBrowsers(), matching: v.id)
        guard !nope.isShowing && !party.isShowing else { return }
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        let why = aiReasons[v.id].map { "  🤖 " + $0 } ?? ""
        recentBlocks.insert("\(f.string(from: Date()))  \(v.channel) (\(v.category))\(v.title.isEmpty ? "" : " – " + v.title)\(why)", at: 0)
        if recentBlocks.count > 8 { recentBlocks.removeLast() }
        nopeBrowser = b.bundleID
        showNope(v, mode: mode)
    }

    // MARK: day / persistence

    private func rollDay() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        guard day != today else { return }
        day = today; dailySec = 0; dailyBonus = 0
        funSec = 0; approvedFun = []; funWarned = false; earnedToday = 0; kidExtrasToday = 0
        if lockIsDaily { lockedUntil = 0; lockReason = ""; lockIsDaily = false }
    }

    private func nextMidnight() -> Double {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!.timeIntervalSince1970
    }

    private func save() {
        let vals: [String: Any] = [
            "dailySec": dailySec, "sessionSec": sessionSec, "lockedUntil": lockedUntil, "lockReason": lockReason,
            "lockIsDaily": lockIsDaily, "dailyBonus": dailyBonus, "sessionBonus": sessionBonus,
            "lastWatch": lastWatch, "day": day, "warned": warned,
            "funSec": funSec, "approvedFun": Array(approvedFun), "funWarned": funWarned,
            "earnedToday": earnedToday, "earnLog": earnLog,
            "kidExtrasToday": kidExtrasToday, "bedtimePassUntil": bedtimePassUntil,
        ]
        vals.forEach { d.set($1, forKey: $0) }
    }

    private func changed() { onChange?() }

    // MARK: browser access

    private func runningBrowsers() -> [Browser] {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        return knownBrowsers.filter { ids.contains($0.bundleID) }
    }

    private func track(_ b: Browser, _ err: Int?) {
        let denied = err == -1743
        if denied && !needsPermission.contains(b.name) { needsPermission.append(b.name) }
        if !denied && err == nil { needsPermission.removeAll { $0 == b.name } }
    }

    private func activeURL(_ b: Browser) -> String? {
        let tab = b.safari ? "current tab" : "active tab"
        let r = runScript("""
        tell application id "\(b.bundleID)"
          try
            if (count of windows) is 0 then return ""
            return URL of \(tab) of front window
          end try
          return ""
        end tell
        """)
        track(b, r.err)
        return r.out
    }

    /// No algorithm feeds: Home, Trending/Explore, Gaming and the Shorts feed go to the parent's start page,
    /// and a Short opens as a normal video (no endless swiping). Returns true if it redirected the tab.
    private func steerAwayFromFeeds(_ b: Browser, _ url: String) -> Bool {
        guard let c = URLComponents(string: url), let host = c.host, host.hasSuffix("youtube.com"),
              !host.hasPrefix("music.") else { return false }
        let path = c.path
        var target: String?
        if path.hasPrefix("/shorts/"), let id = videoID(url) {
            target = "https://www.youtube.com/watch?v=\(id)"
        } else if path.isEmpty || path == "/" || path == "/shorts" || path.hasPrefix("/feed/trending")
                    || path.hasPrefix("/feed/explore") || path.hasPrefix("/gaming") {
            target = youtubeHome
        }
        guard let t = target, let safe = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(["\""])) else { return false }
        let tab = b.safari ? "current tab" : "active tab"
        _ = runScript("tell application id \"\(b.bundleID)\" to set URL of \(tab) of front window to \"\(safe)\"")
        return true
    }

    /// Puts the cleaner script into the YouTube page (hides suggestions, Shorts, blocked thumbnails; autoplay off).
    private func cleanUpPage(_ b: Browser) {
        let rules: [String: Any] = ["channels": list(blockChannels),
                                    "words": gameTopics + junkTopics + overstimTopics + list(blockTopics)]
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else { return }
        let js = youtubeCleanerJS.replacingOccurrences(of: "__RULES__", with: json)
            .replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let src = b.safari
            ? "tell application id \"\(b.bundleID)\" to do JavaScript \"\(js)\" in current tab of front window"
            : "tell application id \"\(b.bundleID)\" to execute active tab of front window javascript \"\(js)\""
        _ = runScript(src)
    }

    /// Asks the browser whether a video on its front tab is playing. nil = can't tell (Chrome/Safari
    /// "Allow JavaScript from Apple Events" is off), so the caller falls back to `browserMediaActive()`.
    private func isPlaying(_ b: Browser) -> Bool? {
        let js = "(function(){return Array.from(document.querySelectorAll('video')).some(function(v){return !v.paused && !v.ended && v.readyState > 2})?'1':'0'})()"
        let src = b.safari
            ? "tell application id \"\(b.bundleID)\" to do JavaScript \"\(js)\" in current tab of front window"
            : "tell application id \"\(b.bundleID)\" to execute active tab of front window javascript \"\(js)\""
        switch runScript(src).out {
        case "1": return true
        case "0": return false
        default: return nil
        }
    }

    /// Fallback: browsers tell macOS "video/audio is playing" (a power assertion) while media plays, and drop it when paused.
    private func browserMediaActive() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g", "assertions"]
        let pipe = Pipe()
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return true }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        let owners = ["Chrome", "Safari", "WebKit", "Brave", "Edge", "Arc"]
        return out.split(separator: "\n").contains { line in
            line.contains("pid ") && owners.contains { line.contains($0) }
                && (line.contains("PreventUserIdleDisplaySleep") || line.localizedCaseInsensitiveContains("audio")
                    || line.localizedCaseInsensitiveContains("video"))
        }
    }

    /// Closes YouTube tabs (all of them, or only ones for one video ID). Returns how many closed.
    private func closeTabs(_ browsers: [Browser], matching id: String?) -> Int {
        let cond = id.map { "u contains \"\($0)\"" } ?? "u contains \"youtube.com\" or u contains \"youtu.be\""
        var closed = 0
        for b in browsers {
            let r = runScript("""
            tell application id "\(b.bundleID)"
              set n to 0
              repeat with w in windows
                try
                  repeat with i from (count of tabs of w) to 1 by -1
                    try
                      set u to (URL of tab i of w) as text
                      if \(cond) then
                        close tab i of w
                        set n to n + 1
                      end if
                    end try
                  end repeat
                end try
              end repeat
              return n as text
            end tell
            """)
            track(b, r.err)
            closed += Int(r.out ?? "") ?? 0
        }
        return closed
    }
}

// MARK: - Full-screen overlays (party + "ah ah ah")

final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class Overlay: NSObject, WKScriptMessageHandler {
    let page: String
    var onMessage: ((String, String) -> Void)?
    private var windows: [NSWindow] = []
    var isShowing: Bool { !windows.isEmpty }

    init(page: String) { self.page = page }

    func show(params: [String: Any]) {
        guard windows.isEmpty, let url = Bundle.main.url(forResource: page, withExtension: "html"),
              let html = try? String(contentsOf: url) else { return }
        for (i, screen) in NSScreen.screens.enumerated() {
            var p = params
            p["primary"] = i == 0
            let json = String(data: try! JSONSerialization.data(withJSONObject: p), encoding: .utf8)!
            let cfg = WKWebViewConfiguration()
            cfg.mediaTypesRequiringUserActionForPlayback = []
            cfg.userContentController.add(self, name: "msg")
            cfg.userContentController.addUserScript(WKUserScript(source: "window.PARAMS=\(json);",
                                                                 injectionTime: .atDocumentStart, forMainFrameOnly: true))
            let web = WKWebView(frame: screen.frame, configuration: cfg)
            // An https base URL (instead of file://) lets the embedded YouTube player work.
            web.loadHTMLString(html, baseURL: URL(string: "https://youtubelimit.local/"))

            let w = KeyWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.isReleasedWhenClosed = false
            w.contentView = web
            w.setFrame(screen.frame, display: true)
            w.makeKeyAndOrderFront(nil)
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        updateKiosk()
    }

    func hide() {
        guard isShowing else { return }
        for w in windows {
            (w.contentView as? WKWebView)?.configuration.userContentController.removeScriptMessageHandler(forName: "msg")
            w.contentView = nil
            w.orderOut(nil)
        }
        windows = []
        updateKiosk()
    }

    func evalJS(_ js: String) {
        for w in windows { (w.contentView as? WKWebView)?.evaluateJavaScript(js) }
    }

    func userContentController(_ u: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        onMessage?(kind, body["value"] as? String ?? "")
    }
}

let party = Overlay(page: "party")
let nope = Overlay(page: "nope")
let earn = Overlay(page: "earn")

/// While an overlay is up: hide Dock/menu bar and block Cmd-Tab so it can't be clicked away.
func updateKiosk() {
    let on = party.isShowing || nope.isShowing || earn.isShowing
    NSApp.presentationOptions = on ? [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication, .disableAppleMenu] : []
}

// MARK: - "1 minute left" banner

final class Banner {
    private var window: NSWindow?

    func show(_ text: String) {
        window?.orderOut(nil)
        guard let screen = NSScreen.main else { return }
        let host = NSHostingView(rootView:
            Text(text)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 36).padding(.vertical, 22)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color.orange))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.black, lineWidth: 4))
                .padding(20))
        let size = host.fittingSize, f = screen.visibleFrame
        let w = NSWindow(contentRect: NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height - 10, width: size.width, height: size.height),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .statusBar
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        w.contentView = host
        w.orderFrontRegardless()
        window = w
        NSSound(named: "Glass")?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak w] in
            guard let w = w, self?.window === w else { return }
            w.orderOut(nil)
            self?.window = nil
        }
    }
}

let banner = Banner()

// MARK: - On-screen timer (shown while YouTube is open)

struct HUDView: View {
    @ObservedObject var m = Limiter.shared
    @State private var tickNow = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let _ = tickNow
        VStack(alignment: .leading, spacing: 4) {
            Text("📺 YouTube  \(clockStr(m.liveTimeLeft)) left" + (m.watching ? "" : "  ⏸"))
        }
        .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
        .foregroundColor(.white)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(m.watchingFun ? Color.yellow : Color.orange, lineWidth: 3))
        .padding(6)
        .onReceive(clock) { tickNow = $0 }
    }
}

final class HUD {
    private var window: NSWindow?

    func setVisible(_ on: Bool) {
        if !on { window?.orderOut(nil); window = nil; return }
        guard window == nil, let screen = NSScreen.main else { return }
        let host = NSHostingView(rootView: HUDView())
        let size = NSSize(width: 290, height: host.fittingSize.height), f = screen.visibleFrame
        let w = NSWindow(contentRect: NSRect(x: f.maxX - size.width - 12, y: f.maxY - size.height - 8, width: size.width, height: size.height),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .statusBar
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.isReleasedWhenClosed = false
        w.contentView = host
        w.orderFrontRegardless()
        window = w
    }
}

let hud = HUD()

// MARK: - Parent PIN

/// First run (or no PIN yet): the parent picks a 4-digit PIN. Returns true once one is saved.
@discardableResult
func createPIN() -> Bool {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = "👋 Welcome to Tube Timer!"
    a.informativeText = "Create a 4-digit parent PIN. You'll need it to change settings, add time, or turn Tube Timer off. Keep it secret from your kids!"
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
    a.accessoryView = field
    a.addButton(withTitle: "Save PIN")
    a.addButton(withTitle: "Later")
    a.window.initialFirstResponder = field
    guard a.runModal() == .alertFirstButtonReturn else { return false }
    let pin = field.stringValue
    guard pin.count == 4, pin.allSatisfy(\.isNumber) else {
        let bad = NSAlert()
        bad.messageText = "The PIN must be exactly 4 digits."
        bad.runModal()
        return createPIN()
    }
    Limiter.shared.pin = pin
    pinUnlockedUntil = Date().timeIntervalSince1970 + 10 * 60
    return true
}

/// One-time: carry everything over from the app's earlier name ("YouTube Limit", com.homebase.youtubelimit).
func migrateFromOldName() {
    let d = UserDefaults.standard
    guard !d.bool(forKey: "migratedFromOldName") else { return }
    d.set(true, forKey: "migratedFromOldName")
    let oldDomain = "com.homebase.youtubelimit" as CFString
    if let keys = CFPreferencesCopyKeyList(oldDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String],
       let old = CFPreferencesCopyMultiple(keys as CFArray, oldDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any] {
        for (k, v) in old where d.object(forKey: k) == nil { d.set(v, forKey: k) }
    }
    let oldLogin = NSHomeDirectory() + "/Library/LaunchAgents/com.homebase.youtubelimit.plist"
    if FileManager.default.fileExists(atPath: oldLogin) {
        try? FileManager.default.removeItem(atPath: oldLogin)
        setOpenAtLogin(true)
    }
}

var pinUnlockedUntil: Double = 0

/// Runs `action` only after the parent PIN is entered (stays unlocked for 10 minutes).
func requirePIN(_ action: @escaping () -> Void) {
    if Date().timeIntervalSince1970 < pinUnlockedUntil { action(); return }
    if Limiter.shared.pin.isEmpty { if createPIN() { action() }; return }
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = "🔒 Parent PIN"
    a.informativeText = "Enter the 4-digit PIN to change Tube Timer."
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
    a.accessoryView = field
    a.addButton(withTitle: "OK")
    a.addButton(withTitle: "Cancel")
    a.window.initialFirstResponder = field
    guard a.runModal() == .alertFirstButtonReturn else { return }
    if field.stringValue == Limiter.shared.pin {
        pinUnlockedUntil = Date().timeIntervalSince1970 + 10 * 60
        action()
    } else {
        let bad = NSAlert()
        bad.messageText = "Wrong PIN 🙅"
        bad.informativeText = "Nice try! Ask a parent."
        bad.runModal()
    }
}

// MARK: - Control panel

struct ControlsView: View {
    @ObservedObject var m = Limiter.shared
    @State private var tickNow = Date()
    @State private var login = opensAtLogin
    @State private var newPin = ""
    @AppStorage("weekendFunAllDay") private var weekendFunAllDay = true
    @AppStorage("aiModel") private var aiModelSetting = ""

    /// A time-of-day picker binding for a "minutes after midnight" setting.
    func minutesBinding(_ key: String) -> Binding<Date> {
        Binding(
            get: {
                let m = UserDefaults.standard.integer(forKey: key)
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                UserDefaults.standard.set((c.hour ?? 0) * 60 + (c.minute ?? 0), forKey: key)
                tickNow = Date()
            })
    }
    @State private var pinMsg = ""
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var status: String {
        _ = tickNow
        if !m.enabled { return "Monitor is OFF" }
        if m.isLocked { return "🔒 Locked for \(fmt(m.lockedUntil - m.now))" }
        return m.watching ? "▶️ Watching now (\(fmt(m.timeLeft)) left)" : "✅ Ready (\(fmt(m.timeLeft)) left)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("🐔").font(.system(size: 44))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tube Timer").font(.title2).bold()
                    Text(status).foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $m.enabled).toggleStyle(.switch).labelsHidden()
            }

            if !m.needsPermission.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("⚠️ Needs permission to control \(m.needsPermission.joined(separator: " & ")). Turn on Tube Timer under Automation.")
                        .font(.callout).foregroundColor(.orange)
                    Button("Open Automation Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }
                }
            }

            TabView {
                timeTab.padding(10).tabItem { Text("⏱ Time") }
                videosTab.padding(10).tabItem { Text("🎓 Videos") }
            }
        }
        .padding(20)
        .frame(width: 500, height: 720)
        .onReceive(clock) { tickNow = $0 }
    }

    var timeTab: some View {
        ScrollView { timeTabContent }
    }

    var timeTabContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox(label: Text("Today")) {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: min(m.dailySec, m.dailyLimit), total: max(m.dailyLimit, 1))
                    Text("\(fmt(m.dailySec)) of \(fmt(m.dailyLimit)) used today")
                    Text("This sitting: \(fmt(m.sessionSec)) of \(fmt(m.sessionLimit))").foregroundColor(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }
            GroupBox(label: Text("Schedule")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("🌙 YouTube off")
                        Spacer()
                        DatePicker("", selection: minutesBinding("offStart"), displayedComponents: .hourAndMinute).labelsHidden()
                        Text("to")
                        DatePicker("", selection: minutesBinding("offEnd"), displayedComponents: .hourAndMinute).labelsHidden()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }
            GroupBox(label: Text("Limits")) {
                VStack(alignment: .leading, spacing: 8) {
                    Stepper("Per day: \(m.dailyMin) min", value: $m.dailyMin, in: 5...600, step: 5)
                    Stepper("Per sitting: \(m.sessionMin) min", value: $m.sessionMin, in: 1...240)
                    Stepper("Break after a sitting: \(m.lockoutMin) min", value: $m.lockoutMin, in: 1...240)
                    Text("Same limits every day, weekends included.").font(.caption).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }
            HStack {
                Button("➕ 10 minutes") { m.addExtra() }.controlSize(.large)
                Spacer()
                Button("Reset today") { m.resetToday() }
            }
            if !m.actionMessage.isEmpty { Text(m.actionMessage).foregroundColor(.green).font(.callout) }
            HStack {
                Text("Preview:").foregroundColor(.secondary)
                Button("Party") { m.showParty(preview: true) }
                Button("1-minute warning") { m.showWarning() }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("⏯ The timer only counts while a video is actually playing.").font(.callout)
                Text(m.playDetection == "precise"
                     ? "Play detection: precise ✅"
                     : "Play detection: basic. For precise: in Chrome, View → Developer → Allow JavaScript from Apple Events.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Toggle("Open automatically when I log in", isOn: Binding(get: { login }, set: { setOpenAtLogin($0); login = $0 }))
            VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Kid PIN:")
                TextField("1234", text: $m.kidPin).frame(width: 70)
                Text("+10 min, \(kKidExtrasPerDay)× a day (used \(m.kidExtrasToday) today)").font(.caption).foregroundColor(.secondary)
            }
            HStack {
                Text("Parent PIN:")
                SecureField("new 4 digits", text: $newPin).frame(width: 110)
                Button("Change") {
                    if newPin.count == 4 && newPin.allSatisfy(\.isNumber) { m.pin = newPin; pinMsg = "PIN changed ✅" }
                    else { pinMsg = "Must be 4 digits" }
                    newPin = ""
                }
                Text(pinMsg).font(.caption).foregroundColor(.secondary)
            }
            }
            Spacer()
        }
    }

    var videosTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Only allow approved learning videos", isOn: $m.filterOn).font(.headline)
                Text("Allowed: paper airplanes, drawing & crafts, piano and skill lessons, science / space / What If, and math, reading & writing. Everything else is blocked. No fun time.")
                    .font(.caption).foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Always allow these channels (comma separated)").font(.subheadline).bold()
                    TextField("e.g. Khan Academy, Pianote", text: $m.allowChannels)
                    Text("Also allow videos about (words in the title)").font(.subheadline).bold()
                    TextField("e.g. paper airplane, how to draw", text: $m.allowTopics)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YouTube start page (replaces YouTube's home feed)").font(.subheadline).bold()
                        TextField("https://www.youtube.com/results?search_query=science+for+kids", text: $m.youtubeHome)
                        Text("YouTube's home feed, Shorts and Trending go here. Suggestions, Shorts shelves, end screens and blocked channels are hidden from the page (needs Chrome: View → Developer → Allow JavaScript from Apple Events).")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Text("Always block these channels (fun time can't unlock these)").font(.subheadline).bold()
                    TextField("e.g. Brent Rivera", text: $m.blockChannels)
                    Text("Never allow videos about (not even with fun time)").font(.subheadline).bold()
                    TextField("e.g. kissing, horror", text: $m.blockTopics)
                    Text("Suggestion channels (Science Max, Mark Rober, Chase Dies in Space, What If, NASA, Math Antics, Storyline Online, piano channels…) and the shuffle/phonk songs are always allowed.")
                        .font(.caption).foregroundColor(.secondary)
                }
                GroupBox(label: Text("🤖 Smart filter (optional)")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(m.apiKey.isEmpty
                             ? "Off. Using built-in word rules. Paste an OpenRouter key (or an Anthropic key) to let AI judge each new video by your allowlist."
                             : "On. Each new video the word rules can't settle is judged by the smart filter (a tiny fraction of a cent per video).")
                            .font(.caption).foregroundColor(.secondary)
                        SecureField("OpenRouter key (sk-or-…) or Anthropic key (sk-ant-…)", text: $m.apiKey)
                        HStack {
                            Text("OpenRouter model:").font(.caption)
                            TextField("perplexity/pplx-decider-v1.2", text: $aiModelSetting).font(.caption)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                HStack {
                    Text("Preview:").foregroundColor(.secondary)
                    Button("\"Ah ah ah\"") { m.showNope(previewVideo, preview: true) }
                    Button("\"Are you sure?\"") { m.showNope(previewVideo, mode: "ask", preview: true) }
                    Button("Earn time") { m.showEarn(preview: true) }
                }
                if !m.earnLog.isEmpty {
                    Text("🧠 His \"explain it\" answers (check he's being honest)").font(.subheadline).bold()
                    ForEach(m.earnLog, id: \.self) { Text($0).font(.caption) }
                }
                if !m.recentBlocks.isEmpty {
                    Text("Recently blocked").font(.subheadline).bold()
                    ForEach(m.recentBlocks, id: \.self) { Text($0).font(.caption) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

let previewVideo = VideoInfo(id: "", title: "Some silly video", channel: "Preview Channel", category: "Entertainment")

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow?
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        if CommandLine.arguments.contains("--self-test") { selfTest(); exit(0) }
        migrateFromOldName()
        if !UserDefaults.standard.bool(forKey: "didFirstLaunch") {
            UserDefaults.standard.set(true, forKey: "didFirstLaunch")
            setOpenAtLogin(true)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let m = Limiter.shared
        m.onChange = { [weak self] in self?.updateMenu() }
        earn.onMessage = { kind, value in
            if kind == "cancel" { earn.hide() }
            if kind == "earned" {
                m.completeEarn(explanation: value)
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { earn.hide() }  // let the 🎉 screen show
            }
        }
        party.onMessage = { kind, value in
            if kind == "parent" { m.parentAction(value, from: party) }
        }
        nope.onMessage = { kind, value in
            if kind == "parent" { m.parentAction(value, from: nope) }
            if kind == "fun" { m.approveFun() }
            if kind == "earn" { m.showEarn() }
            if kind == "pick", let url = URL(string: "https://www.youtube.com/watch?v=\(value)") { m.pickFromNope(url) }
            if kind == "search", let q = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "https://www.youtube.com/results?search_query=\(q)") { m.pickFromNope(url) }
        }
        // Parent escape hatch: Control-Option-Command-P closes a lockout screen.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.modifierFlags.contains([.control, .option, .command]), e.charactersIgnoringModifiers?.lowercased() == "p" {
                party.hide(); nope.hide(); earn.hide()
                return nil
            }
            return e
        }
        Suggestions.shared.refresh()
        Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { _ in Suggestions.shared.refresh() }
        m.start()

        let args = CommandLine.arguments
        if args.contains("--preview-party") { m.showParty(preview: true) }
        else if args.contains("--preview-warning") { m.showWarning() }
        else if args.contains("--preview-nope") || args.contains("--preview-ask") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {  // give suggestions a moment to load
                m.showNope(previewVideo, mode: args.contains("--preview-ask") ? "ask" : "nope", preview: true)
            }
        }
        else if !args.contains("--login") {
            // New install: set a PIN first, then show the controls.
            if m.pin.isEmpty { DispatchQueue.main.async { if createPIN() { self.openControls() } } } else { showControls() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControls()
        return true
    }

    func updateMenu() {
        let m = Limiter.shared
        statusItem.button?.title = "🐔 " + m.menuTitle
        hud.setVisible(m.enabled && m.onYouTube && !m.isLocked && !nope.isShowing)
        if let w = window, w.isVisible, Date().timeIntervalSince1970 > pinUnlockedUntil { w.close() }  // PIN timed out
        let menu = NSMenu()
        func item(_ title: String, _ sel: Selector?) {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = self
            menu.addItem(i)
        }
        item("Today: \(fmt(m.dailySec)) of \(fmt(m.dailyLimit))", nil)
        menu.addItem(.separator())
        item("Open Controls…", #selector(showControls))
        item("➕ Give 10 more minutes", #selector(addExtra))
        item("🧒 Kid PIN: +10 minutes (\(max(0, kKidExtrasPerDay - m.kidExtrasToday)) left today)", #selector(kidAddExtra))
        item(m.enabled ? "Turn Monitor Off" : "Turn Monitor On", #selector(toggleEnabled))
        menu.addItem(.separator())
        item("Quit Tube Timer", #selector(quit))
        statusItem.menu = menu
    }

    @objc func showControls() { requirePIN { self.openControls() } }

    func windowWillClose(_ notification: Notification) { pinUnlockedUntil = 0 }

    func openControls() {
        if window == nil {
            let host = NSHostingView(rootView: ControlsView())
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Tube Timer"
            w.contentView = host
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc func addExtra() { requirePIN { Limiter.shared.addExtra() } }

    /// Developer check of +10, the kid PIN, Reset and the bedtime pass (run with --self-test; back up settings first).
    func selfTest() {
        let m = Limiter.shared, d = UserDefaults.standard
        func line(_ s: String) { print(s); fflush(stdout) }
        let t0 = m.timeLeft
        m.addExtra()
        line("+10:        \(fmt(t0)) -> \(fmt(m.timeLeft))  (\(m.timeLeft - t0 >= 599 ? "PASS" : "FAIL"))")
        for i in 1...3 { line("kid +10 #\(i): \(m.kidExtra())") }
        line("kid extras used: \(m.kidExtrasToday)  (\(m.kidExtrasToday == 2 ? "PASS" : "FAIL"))")
        m.dailySec = 3000; m.sessionSec = 1000
        m.resetToday()
        line("reset:      used \(fmt(m.dailySec)), left \(fmt(m.timeLeft))  (\(m.dailySec == 0 && m.timeLeft >= 1799 ? "PASS" : "FAIL"))")
        let mins = minutesNow()
        d.set((mins + 1440 - 5) % 1440, forKey: "offStart"); d.set((mins + 60) % 1440, forKey: "offEnd")
        line("bedtime now? \(inYouTubeOffHours)")
        m.addExtra()
        let pass = m.bedtimePassUntil - m.now
        line("bedtime +10 pass: \(fmt(pass))  (\(inYouTubeOffHours && pass > 590 ? "PASS" : "FAIL"))")
    }

    /// Kid PIN from the menu bar: +10 minutes, twice a day.
    @objc func kidAddExtra() {
        let m = Limiter.shared
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "🧒 Kid PIN"
        a.informativeText = "Enter your kid PIN for 10 more minutes (\(max(0, kKidExtrasPerDay - m.kidExtrasToday)) left today)."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
        a.accessoryView = field
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let r = NSAlert()
        if field.stringValue == m.kidPin && !m.kidPin.isEmpty {
            r.messageText = m.kidExtra()
        } else {
            r.messageText = "Wrong kid PIN 🙅"
        }
        r.runModal()
    }
    @objc func toggleEnabled() { requirePIN { Limiter.shared.enabled.toggle() } }
    @objc func quit() { requirePIN { NSApp.terminate(nil) } }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
