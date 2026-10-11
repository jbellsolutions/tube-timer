# Launch checklist

## 1. GitHub (repo + free website)
1. In Terminal, log back in to GitHub: `gh auth login` and follow the prompts.
2. Ask Claude to publish. It creates `jbellsolutions/tube-timer` (public), pushes the code, turns on GitHub Pages from `/docs`, and uploads `TubeTimer-1.0.0.dmg` as a Release.
3. Website: https://jbellsolutions.github.io/tube-timer/

## 2. Gumroad ($50 download + tester coupons)
1. Create a product: **Digital product → "Tube Timer for Mac"**, price **$50**.
2. Set the URL slug to **`tubetimer`**. The site expects `https://jbellsolutions.gumroad.com/l/tubetimer`. If yours differs, edit `CONFIG.gumroad` at the bottom of `docs/index.html`.
3. Upload `app/dist/TubeTimer-1.0.0.dmg`. Add a receipt note: "Open the DMG, drag Tube Timer to Applications, then see READ ME FIRST if macOS asks you to approve it."
4. **Tester coupons:** Product → Discounts → New discount → **100% off**, code e.g. `BETATESTER`, and set a usage limit. Testers type the code in the "Have a tester code?" box on the site, which opens Gumroad with the code added to the end of the product link (`.../l/tubetimer/BETATESTER`). Test it once yourself to confirm Gumroad applies it.
5. Promise the "mobile app free when it launches" in the product description so buyers have it in writing.

## 3. Skool (7-day free trial)
1. In your Skool group, turn on paid membership with a **7-day free trial**.
2. Put the group's URL in `CONFIG.skool` at the bottom of `docs/index.html`, and add the Tube Timer DMG (or a link to the Release) inside the group.

## 4. Later (optional but worth it)
- **Apple Developer ID ($99/yr):** sign and notarize the app so the download opens without the "Open Anyway" step. That's the biggest conversion boost for the paid download.
- **Windows version:** a separate build (likely a small browser extension + tray app). Worth doing once the Mac version proves demand.
- **Analytics:** add Plausible or Google Analytics to `docs/index.html` to measure clicks on Buy vs. Trial.
