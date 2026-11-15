# Brief

**Question:** Build a native Mac app of Bogey Club that works fully without the Claude connection (local data storage, offline scorecard scan, saving files).

**Purpose:** The person wants to use their golf scorebook on the Mac independently of Claude.

**Targets:**
- web/index.html
- server/runtime.js
- ios/GolfScorebuch

**Constraints:**
- Keep web/index.html, iOS app, Cloudflare hosting working unchanged
- No Claude services at runtime

**Done when:** A .app builds from the repo, opens the Bogey Club UI, stores players/courses/rounds/photos on the Mac, saves PDFs/backups, imports backups, and reads scorecard photos with Apple's on-device text recognition.
