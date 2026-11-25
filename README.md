# PallyPulse

**One key. Less buff management.** Paladin blessings for WoW Forever.

Set your assignments once, bind Smart Buff, and each press casts the next blessing you owe.
Assignments follow each player's spec, Oath of Light goes on your tanks, the ready check shows
what you still owe, and PallyPower's sync protocol is supported so mixed raids work.

- CurseForge: https://www.curseforge.com/wow/addons/pallypulse (project 1809219)
- Bugs and requests: https://github.com/Vx1125/pallypulse/issues
- Store page text, quick start and FAQ: [CURSEFORGE.md](CURSEFORGE.md)

## Install

Install from CurseForge, or copy the `PallyPulse` folder into
`World of Warcraft\_forever_\Interface\AddOns`. No libraries are required; fonts and sounds
from LibSharedMedia are used when another addon has loaded it.

## Quick start

1. `/pulse` opens the window.
2. Options > General: bind **Smart Buff**.
3. Blessings tab: **Auto-assign**, or load a preset.
4. Press Smart Buff until everything is up. Each press casts one spell.

## Commands

`/pulse`, `/pulse bar`, `/pulse options`, `/pulse check`, `/pulse announce`

Debug: `/pulse debug`, `/pulse debug test | trace | frames | auras | specs | cpu`

Chat, for anyone in the group: `!bless want <blessings>`, `!bless clear`, `!bless missing [all]`,
`!bless report`; leader or assistant: `!bless assign`, `!bless want <name> <blessing>`.

## Project files

| File | For |
|---|---|
| `CURSEFORGE.md` | The CurseForge description (paste via the copy page) |
| `MARKETING.md` | Short description, gallery order and captions, GIF storyboard, release checklist |
| `CHANGELOG.md` | Release notes (packaged with the addon) |
| `DESIGN.md` | How the code works and the Forever constraints behind it |
| `UI_DESIGN_STANDARD.md` | The frozen look: colours, sizes, controls, Options layout |
| `media/` | Store images (not packaged) |

## Releasing

1. Update `CHANGELOG.md`.
2. Put the new version number in `VERSION` (e.g. `1.0.2`) and push to `main`.
   The GitHub Action tags `v1.0.2`, packages the addon and uploads it to CurseForge.
   (Pushing or creating a `v1.0.2` tag on GitHub works too.)

Needs the repository secret `CF_API_KEY` (a CurseForge API token), and
Settings > Actions > General > Workflow permissions set to "Read and write".
`check.yml` syntax-checks the Lua on every push.
