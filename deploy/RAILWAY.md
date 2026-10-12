# Tube Timer Railway hosting

Canonical website: https://tube-timer.up.railway.app/
Project: tube-timer (81852319-a5f9-4536-a252-f20ce29a3a56)
Service: tube-timer (9544dddf-c3c4-4fd5-bb6f-9f7e51a1b1f2)

Serve docs/ with the root Dockerfile. Railway service configuration uses the Dockerfile builder, /index.html health check (60-second timeout), one replica and three on-failure retries. Domain routes to port 8080. Nginx reads Railway PORT; its default is 8080. No database or app credentials are needed for this public site. No macOS app runs on Railway.

Connect the GitHub source jbellsolutions/tube-timer, branch main, for future autodeploys. Deployment must pass health checks before retiring prior hosting. GitHub Pages is disabled after Railway is confirmed live; GitHub source and release assets remain available.

Gumroad: https://jbellcraft.gumroad.com/l/tubetimer
Current listed price: $50 one time. Purchase availability and paid delivery are managed in Gumroad, not by this static site. Before launch: upload the latest Mac release plus setup instructions; verify completed test checkout and download through the seller dashboard. Do not charge a real card for a self-test. Site links /download-help/ for installation instructions, not unprotected buyer entitlement.

When a custom domain is purchased, add it to this Railway service, configure the DNS records Railway supplies, verify HTTPS, update docs/index.html canonical/og:url and README website URL, and update all campaign and Gumroad website references. Do not guess DNS records in advance.
