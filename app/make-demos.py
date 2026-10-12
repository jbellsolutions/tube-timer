#!/usr/bin/env python3
"""Regenerates the website's live demos (docs/demo/*.html) from the app's real screens."""
import json, os
here = os.path.dirname(os.path.abspath(__file__))
docs = os.path.join(here, "..", "docs", "demo")
load = lambda name: json.load(open(os.path.join(here, "content", name)))
slots = load("suggestions.json")["slots"]
songs = load("party-songs.json")["songs"]
challenge = dict(load("challenges.json")[0], seconds=8)
common = {"canEarn": True, "earnMinutes": 20, "funWindow": "4:00 PM–8:30 PM", "primary": True}
demos = {
    "party": ("party", {"until": "NOW+1500", "partyUntil": "NOW+1500", "reason": "That's 30 minutes in a row. Take a 30 minute break!",
                        "daily": False, "songs": songs, "musicSeconds": 60, "muted": True, "primary": True}),
    "nope": ("nope", dict(common, mode="nope", title="I Survived 100 Days in a Secret Room", channel="Some Brain-Rot Channel",
                          category="Entertainment", skin=0, slots=slots, funLeft=0, funMin=20)),
    "ask": ("nope", dict(common, mode="ask", title="I Built an EXTREME Treehouse!", channel="A Kid Vlogger",
                         category="Entertainment", skin=7, slots=slots, funLeft=745, funMin=20)),
    "earn": ("earn", dict(common, challenge=challenge, used=0, inWindow=True)),
}
for name, (src, params) in demos.items():
    page = open(os.path.join(here, src + ".html")).read()
    js = json.dumps(params, ensure_ascii=False).replace('"NOW+1500"', "Date.now()/1000+1500")
    page = page.replace("<head>", "<head>\n<!-- Demo copy of a Tube Timer screen. Regenerate with app/make-demos.py -->\n"
                        f"<script>window.PARAMS={js};</script>", 1)
    open(os.path.join(docs, name + ".html"), "w").write(page)
print("demos written")
