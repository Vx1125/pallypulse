# PallyPulse marketing and release notes

Store-facing material that isn't the description itself (that's `CURSEFORGE.md`).
Not packaged with the addon.

## Message

**One key. Less buff management.**

Problem it solves: keeping a raid blessed as a paladin means tracking classes, specs, timers and
other paladins. PallyPulse turns that into one key you press until it's done, and a ready check
that tells you what is still yours to do.

## CurseForge summary (short description)

> One key for raid blessings. Smart Buff casts the next blessing you owe, with spec-based assignments, Oath of Light on your tanks and PallyPower sync for WoW Forever.

(167 characters.)

## Gallery

In this order. Title, then caption.

| # | File | Title | Caption |
|---|------|-------|---------|
| 1 | `smart-buff-v3.jpg` | Smart Buff | One key casts the next blessing you owe. The tooltip shows what and on whom. |
| 2 | `blessings-v3.jpg` | Assignments | Every paladin's blessings by class, plus aura and Oath. Conflicts and gaps are flagged. |
| 3 | `ready-check-v3.jpg` | Ready check | Buffed, missing and unavailable at a glance, opened with every ready check. |
| 4 | `responsibilities-v3.jpg` | Yours, and everyone else's | What you still owe on top; other paladins' gaps grouped by blessing. |
| 5 | `players-v3.jpg` | Every player | Your blessing and the raid's side by side, with what you need to fix first. |
| 6 | *(to take)* `presets` | Presets | Save assignments per raid and load them in one click. |
| 7 | `options-v3.jpg` | Set up in seconds | Bind Smart Buff and go. Every setting explains itself on hover. |
| 8 | `layouts-v3.jpg` | Your bar, your way | Standard, Compact or Action only, vertical or horizontal. |
| 9 | `frame-click-v2.jpg` | Raid frames | Your blessing on each frame. Click it to cast, in combat too. |
| 10 | `priorities-v3.jpg` | Priorities by spec | Set your own blessing order for every class and spec. |
| 11 | `appearance-v3.jpg` | Appearance | Bar, raid frame icons and window scale, each on its own. |

Banner: `banner-v4.jpg` (1920x660).

Still to capture: **#6 Presets** - Blessings tab in test mode with the Presets menu open and a
couple of saved presets, the loaded one's name showing next to the buttons. Use test mode so no
real names appear.

Rules: test mode only (fake names; never a real character name), JPG under 2 MB, new file name
for every replaced image (CurseForge caches by URL).

## Gameplay GIF (10-15 s)

Shows the core loop with no narration: things are missing, press the key, they're done.

**Setup**
- Your paladin, in a real party or raid (Smart Buff casts real spells, so test mode can show the
  bar but can't play the casts). Use a group whose names you're fine showing, or blur them.
- Most blessings expired or missing; you carry Symbols of Kings.
- Smart Buff bound to a visible key; Options > Appearance: Standard, vertical, Timers on.
- Out of combat, everyone in range. Ready Check window open (`/pulse check`) beside the bar.

**Framing**
- Crop to the bar and the Ready Check only, about 640x400. Keep the game world behind them
  but no chat or action bars.
- 30 fps, then export at 15 fps for size.

**Storyboard**

| Time | On screen | Caption (bottom, small) |
|------|-----------|-------------------------|
| 0-2 s | Bar with red rows and counts; Ready Check "Your Responsibilities 6 Missing" | Blessings missing |
| 2-3 s | Hover the top row: the Next Blessing tooltip | Next: Greater Blessing of Kings |
| 3-10 s | Press the key 4-5 times, a beat between presses; counts drop, rows go green, the Ready Check list shrinks | One key |
| 10-13 s | All rows green, tick on the top row, "All your blessings active" | Done |

Show the key press (an on-screen key overlay or the key name in the caption). Don't speed up the
casts or edit out the global cooldown.

## Release readiness (1.4.0)

| Area | State |
|------|-------|
| Version | `VERSION` 1.4.0; the toc uses `@project-version@` so packages carry the tag. Local copies say `dev-<sha>`. |
| Client | `## Interface: 16001`, WoW Forever only. |
| Dependencies | None. LibSharedMedia is optional and found at run time, so no `OptionalDeps` line. |
| Changelog | `CHANGELOG.md` has 1.4.0 at the top and is shipped with the package. |
| Naming | "PallyPulse" everywhere (toc Title, slash command `/pulse` and `/pallypulse`, saved variable `PallyPulseDB`). |
| Install | README covers CurseForge and manual install. |
| Support | GitHub Issues is enabled on a public repo. **To do:** add it as the Issues link (and the repo as Source) in the CurseForge project settings. |
| License | **No license file** in the repo and none set on GitHub. Choose one before inviting contributions; set it on CurseForge to match. (Not changed here.) |
| Screenshots | Replaced with 1.4.0 images. Old images (`*-v2.jpg`, `flat-style.jpg`, `priorities.jpg`, `banner-v2.jpg`) stay in `media/` until the new description is live, then can be deleted. |
| Description | Rewritten for 1.4.0 (`CURSEFORGE.md`). Dropped Classic/Flat and Light's Vigil. |
| Docs | `DESIGN.md` brought up to date (Light blessing, Vigil and Forbearance icons, Widgets, tab names). |

Optional: the toc `## Notes` line ("Paladin blessing assignments and one-key buffing.") is what
players see in the in-game addon list. It's accurate; it could echo the tagline in a later
release.

## Claims to confirm in game

- The Smart Buff tooltip and top row name the same spell and target the key then casts, in and out of combat.
- PallyPower sync with the PallyPower version players actually run now (built against Forever 10.10.26).
- Oath auto-target picks up Main Tank markers (`GetPartyAssignment`) and group Tank roles on Forever.
- Greater Blessings are used at the set class size and consume Symbols of Kings.
- Raid frame icons and click-to-cast on Blizzard's party and raid frames (not ElvUI, HealBot and the like).
- Dead and offline players never show as missing in the ready check.
