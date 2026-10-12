# ⏱🐔 Tube Timer

**Turn YouTube from a brain-rot machine back into a tool, without the daily fight.**

Tube Timer is a free Mac app made by a dad whose son was on YouTube all day. It doesn't just block YouTube. It:

- **Counts only real watching.** The timer runs only while a video is actually playing, not while it's paused or he's searching.
- **Lets learning through and catches brain-rot.** Science, space, math, reading, art, crafts, quizzes and music are always OK. Passive "secret room / noob vs pro / 24 hours in…" videos use a small daily **fun-time** allowance. Inappropriate stuff is blocked.
- **Makes kids get up.** After a sitting (30 min on school days, 1 hour on weekends) the screen turns into a dance party with dancing Minecraft-style chickens that says *get up, go outside, talk to people, shake your butt*. It can't be clicked away until the break is over.
- **Lets kids earn more fun time by learning.** Watch a short math or science video inside the app, answer 5 questions, and get +20 minutes (twice a day).
- **Says "Ah ah ah!"** When he opens something off-limits, a pixel character in a different costume each time wags his finger and offers 5 hand-picked videos instead: paper airplanes, drawing, Science Max, What If, space.
- **Has a bedtime.** YouTube shuts off overnight (default 9 PM–6 AM).
- **Shows a countdown on screen** so kids always know how much time is left.
- **Is locked with a parent PIN.**

> 🌐 **Website:** https://tube-timer.up.railway.app/
> 👨‍👩‍👦 **Parents' community (more apps, Minecraft mods, learning curriculum):** see the website

---

## Install (Mac, macOS 13 Ventura or newer)

### Option 1: one line in Terminal (recommended, no security warnings)

Open **Terminal** (press ⌘-Space, type *Terminal*, press Return), paste this, and press Return:

```bash
curl -fsSL https://raw.githubusercontent.com/jbellsolutions/tube-timer/main/install.sh | bash
```

It builds Tube Timer on your Mac, puts it in your Dock, and opens it. If your Mac doesn't have Apple's free *Command Line Tools* yet, a window pops up to install them. Click **Install**, wait a few minutes, then run the line again.

### Option 2: download the app

Grab `TubeTimer-x.y.z.dmg` from [Releases](https://github.com/jbellsolutions/tube-timer/releases), drag it to Applications, and open it. This early version isn't notarized by Apple yet, so the first time, macOS will ask you to approve it in **System Settings → Privacy & Security → Open Anyway**.

### First run

1. **Create your 4-digit parent PIN.** You'll need it for settings, extra time, or turning Tube Timer off.
2. **Open YouTube in Chrome or Safari** and click **OK** when macOS asks to let Tube Timer control your browser. Missed it? Go to *System Settings → Privacy & Security → Automation → Tube Timer*.
3. *(Optional, for the most accurate timer)* In Chrome: **View → Developer → Allow JavaScript from Apple Events.**

Works with Chrome, Safari, Brave, Edge, and Arc.

---

## Customize it

Click the Tube Timer icon (Dock, Desktop, or the 🐔 in the menu bar) and enter your PIN.

| ⏱ Time tab | 🎓 Videos tab |
|---|---|
| Daily limit, sitting length, break length | Fun (entertainment) minutes, weekdays & weekends |
| Weekend limits | Which YouTube categories count as learning |
| Fun-video hours & YouTube-off hours | Always-allow / always-block channels |
| ➕ 10 minutes, reset today | Always-allow topics, never-allow topics |
| Change PIN, open at login | Optional 🤖 Claude AI smart filter (bring your own API key) |
| | His "explain it" answers + recently blocked videos |

### Your own videos, quizzes and party songs

The suggestion cards, the earn-time quizzes, and the dance-party songs are plain JSON files. To change them, copy any of these from [`app/content/`](app/content) into `~/Library/Application Support/Tube Timer/` and edit your copy. It replaces the built-in one the next time Tube Timer opens.

- `suggestions.json`: the 5 suggestion slots, plus channels that are always allowed
- `challenges.json`: earn-time videos with 4 auto-checked questions + 1 "explain it" prompt each
- `party-songs.json`: the songs that play during the get-up break

---

## How it works

- A small menu-bar app checks the front tab of each browser every 5 seconds through macOS Automation (AppleScript).
- To decide what a video is, it reads the video's public YouTube page: title, channel, category, and family-safe flag. Then it applies rules in this order: your allow/block lists, then never-allow topics, then learning categories, then a clear learning angle in the title ("quiz", "science", "how to draw"…), then brain-rot signals, then learning/creative/music topics. Anything left over counts as fun time. With an Anthropic API key, Claude judges the videos the rules can't settle, using the parent's criteria.
- Breaks, the "Ah ah ah" screen, and earn-time quizzes are full-screen windows that hide the Dock and block ⌘-Tab until they're done. **Parent escape hatch:** ⌃⌥⌘P (Control-Option-Command-P).
- Everything stays on your Mac. No accounts and no tracking. The only internet calls are to YouTube's public pages, plus Anthropic if you turn on the AI filter.

### Honest limits

- It only watches **web browsers on this Mac**: Chrome, Safari, Brave, Edge, and Arc. It doesn't cover Firefox, the YouTube app on phones or tablets, or TVs. (Mobile is coming.)
- A determined kid with an **admin** account can quit or delete any app. For the strongest setup, give your child a **Standard** macOS user account.

---

## Build from source

```bash
git clone https://github.com/jbellsolutions/tube-timer.git
cd tube-timer
./install.sh            # build + install
app/make-release.sh     # build the universal .dmg/.zip into app/dist/
```

Requires macOS 13+ and Apple's Command Line Tools (`xcode-select --install`). Single-file Swift app ([`app/main.swift`](app/main.swift)) + HTML screens. No dependencies.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/jbellsolutions/tube-timer/main/uninstall.sh | bash
```

Add `-s -- --all` after `bash` to also delete settings.

## License

[PolyForm Noncommercial 1.0.0](LICENSE.md): free for families, schools, and personal use. Please don't resell it.
