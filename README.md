# flowgeist.de — Sabbatical Page

Static landing page served via GitHub Pages while the production infrastructure is offline.

- `index.html` — self-contained page (sleeping flowgeist ghost, no external assets)
- `CNAME` — custom domain `flowgeist.de`
- `ops/dns-switch.ps1` — Hetzner DNS switch to/from GitHub Pages (`-WhatIf`, `-Revert`)

Remotes: `origin` = TrueNAS (primary), `github` = GitHub (serves Pages — push to both).
