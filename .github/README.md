<div align="center">

# Parrot 3 - NeRgY Fork

### Continued development of Parrot floating combat text for World of Warcraft

<img src="https://img.shields.io/github/v/release/NeeRgY/Parrot3?style=for-the-badge" />
<img src="https://img.shields.io/github/last-commit/NeeRgY/Parrot3?style=for-the-badge" />
<img src="https://img.shields.io/github/issues/NeeRgY/Parrot3?style=for-the-badge" />
<br><br>

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/neergy)

**This is a community fork. Donations / tips support my maintenance, not the original Parrot authors.**

---
<br>

A maintained fork of **Parrot**, continued from **Parrot 2 by Neb (nebularg)**, originally by **ckknight**.

Merges the separate Retail and Classic builds into one addon with a dedicated TOC and code tree per game version.

**Current version:** `v3.0.0`

</div>

---

# About This Fork

This repository is maintained by **NeRgY**.

Lineage:

1. [ckknight/Parrot](https://www.wowace.com/projects/parrot) — original Parrot
2. [nebularg/Parrot2](https://github.com/nebularg/Parrot2) — Neb's continuation (Retail + Classic builds)
3. **NeRgY** — merged both builds into Parrot 3 and continues maintenance

Goals of this fork:

- Keep Parrot working on **Retail 12.1.0 / 12.1.5**
- One addon covering **Retail, Classic Era, TBC Classic and MoP Classic**
- One TOC and one code tree per version so nothing cross-contaminates
- Stay practical: stable, testable changes

> This is **NOT** the official Parrot repository.

---

# Original Project Credits

- Original Parrot: ckknight
- Parrot 2: https://github.com/nebularg/Parrot2 (Neb, profalbert)

Without their work, this fork would not exist.

---

# Supported Clients

| Client | Interface | TOC |
|--------|-----------|-----|
| Retail (`12.1.0` / `12.1.5`) | `120100, 120105` | `Parrot3_Mainline.toc` |
| Classic Era (`1.15.9`) | `11509` | `Parrot3_Vanilla.toc` |
| TBC Classic (`2.5.6`) | `20506` | `Parrot3_TBC.toc` |
| MoP Classic (`5.5.4`) | `50504` | `Parrot3_Mists.toc` |

`Libs/` and `Locales/` are shared by all four TOCs. SavedVariables stay `ParrotDB`, so existing Parrot 2 settings carry over.

---

## NeRgY Fork Highlights

- Retail and Classic builds of Parrot 2 merged into a single addon
- Per-version TOC + fully separated code tree (`Mainline/`, `Vanilla/`, `TBC/`, `Mists/`)
- **MoP Classic:** specialisation-aware trigger system ported from the Retail build, with a C_Spell compatibility shim
- Interface bumped to current clients; renamed to Parrot 3
- Every changed file carries an LGPL v2.1 change notice (see `CHANGELOG.md`)

---

# Installation

Download the latest release, then copy the `Parrot3` folder into:

- Retail: `World of Warcraft\_retail_\Interface\AddOns\Parrot3`
- Classic Era: `World of Warcraft\_classic_era_\Interface\AddOns\Parrot3`
- TBC: `World of Warcraft\_classic_\Interface\AddOns\Parrot3`

Then `/reload` in-game. Options: `/parrot` or `/par`.

## Important

Do **NOT** download `Source code (zip)` / `Source code (tar.gz)` from GitHub tags.

---

# Contributing

Bug reports and fixes welcome. When reporting an issue, include:

- WoW version / client (Retail, Classic Era, TBC, MoP)
- Addon version (`v3.0.0`)
- Lua errors (BugSack / `/console scriptErrors 1`)
- Reproduction steps

---

# Support

- GitHub Issues: https://github.com/NeeRgY/Parrot3/issues
- Repository: https://github.com/NeeRgY/Parrot3
- Parrot 2 (upstream): https://github.com/nebularg/Parrot2

---

# Credits

## Original Authors
- ckknight
- profalbert
- nebularg (Neb) — Parrot 2

## Current Fork Maintainer
- NeRgY

---

# License

Parrot 3 is released under the **GNU Lesser General Public License, version 2.1** — see [`LICENSE.txt`](LICENSE.txt), the same license as upstream.

---

# Disclaimer

This project is unofficial and is not affiliated with Blizzard Entertainment.

World of Warcraft is a trademark of Blizzard Entertainment.

Use this addon at your own discretion.
