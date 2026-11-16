# PallyPulse design notes

How the addon works, the WoW Forever constraints behind it, and where things live. Keep this
current when behaviour changes.

## Files (load order from PallyPulse.toc)
| File | What it does |
|---|---|
| Data.lua | Blessings (Might, Wisdom, Kings, Light), spell ids, class and role preferences, auras, Righteous Fury, Oath of Light, hand blessings, defaults, style colours |
| Core.lua | Roster, saved variables, capabilities, own addon comm ("PPULSE" prefix), class assignments, aura scanning and memory, ClassStatus, CastNames, Auto-assign, auto Oath, slash commands |
| Compat.lua | PallyPower "PLPWR" protocol: SELF, ASSIGN, PASSIGN, MASSIGN, NASSIGN, ASELF, AASSIGN, REQ, CLEAR |
| Widgets.lua | Shared UI kit: tooltip-style panels, Blizzard buttons and check boxes, icon slots |
| Players.lua | Per-player exceptions (hand / auto), role guessing, spec-aware AutoOverrides, "!bless" chat commands |
| Auras.lua | Aura assignment and sync, Righteous Fury status, FindAura, spell-name localization |
| Versions.lua | Version list (PallyPulse / PallyPower / none), reagent count, Auto Self Cast warning |
| Smart.lua | Smart Buff queue (Candidates), secure button wiring, in-combat snippet, cast confirmation, keybinding labels |
| Presets.lua | Save and load layouts by paladin slot |
| Bar.lua | Compact bar: Smart Buff button, aura, class and Oath slots, player flyout |
| FrameIcons.lua | Icons on Blizzard party and raid frames: blessing, hand, Oath, Light's Vigil, Forbearance |
| Settings.lua | Options tab |
| Window.lua | Tabbed window: Blessings, Players, Group, Options |
| Minimap.lua, UI.lua | Minimap button; builds the UI at login |

## WoW Forever facts that shape the code
- Blessings last 1 hour. Salvation and Sanctuary are gone; Kings is baseline.
- Greater Blessings cost a Symbol of Kings (item 21177); it's unclear whether they're live yet.
- Oath of Light: Holy talent, 5 minutes, one target per paladin, boosts only that paladin's heals.
- A paladin can only have one blessing on a player: Freedom, Protection and Sacrifice replace it.
- Group members' auras can be hidden ("secret") from addons around and during combat.
- Protected (secure) code can't run UnitIsUnit, so it can't tell which group member is targeted.
- Protected code has no range check.
- The game's Auto Self Cast setting redirects an out-of-range blessing onto the caster.

## Smart Buff
Out of combat, live, each press re-picks (Candidates in Smart.lua), in this order:
1. Your aura if it's off
2. Righteous Fury while you're marked as tank
3. Oath of Light missing
4. Re-bless after your Freedom / Protection / Sacrifice
5. Missing blessings, yourself first, then class order
6. Oath under 1 minute
7. Expiring blessings (within the refresh window)

Out of range and out of sight players are skipped. A cast only counts once
UNIT_SPELLCAST_SUCCEEDED confirms it. A Greater Blessing is used only when it's known, the
class is big enough (greaterMin) and it's castable; a class with exceptions uses normal
blessings.

In combat a secure snippet (SecureHandlerWrapScript on the Smart button) runs each press:
1. Friendly target: that player's blessing. This only works with the "rb-one" fallback (every
   class gets the same blessing), since UnitIsUnit isn't available.
2. Otherwise, the next entry in the list frozen at PLAYER_REGEN_DISABLED: players missing a
   blessing who were in range at the pull. Dead players are skipped.
3. Otherwise, Oath of Light.

Alt + key casts your own blessing on yourself; right-click (or the second keybind) casts Oath.

## Aura reading
MemberRemaining treats "unsure" (hidden auras, failed read, combat) as "still up" if we saw the
buff before (auraMemory). Memory is dropped when a player dies or gets your hand blessing. The
combat list uses the last good out-of-combat reads (no fresh scan at the pull).

## Sync
- Own prefix "PPULSE":
  - C (caps incl. OATH, A_ auras), A (assign), O (oath), P (exception), R (request)
  - U (aura), V / VQ (version), Q (sync request)
- A paladin can change their own row; leaders and assistants can change any row.
- PallyPower: class, per-player (NASSIGN) and aura (ASELF / AASSIGN) assignments both ways.
  Salvation (4) and Sanctuary (6) are ignored.

## Releasing
Update CHANGELOG.md, bump VERSION, push to main. The workflow's "tag" job tags vX.Y.Z and
dispatches itself on that tag; the "release" job runs BigWigsMods/packager, which uploads to
CurseForge 1809219 (detected as the Forever flavor, game version 1.60.1) and GitHub Releases.
Needs the CF_API_KEY secret and "Read and write" workflow permissions.

## Debugging in game
- /pulse trace: every Smart Buff press, plus the list at the pull
- /pulse debug: assignments, Oath, combat-queue availability
- /pulse test: dry run of the queue and guessed roles
- /pulse frames: which Blizzard frames were found
- /pulse check: opens the ready check window (also opens on every ready check)
- /pulse auras: buffs on you with spell id and caster, and what the aura check finds
- /pulse versions
