# PallyPulse

## 1.0.5
- New ready check window. It opens on every ready check (or /pulse check) with everyone's ready status and blessings:
  - A blessing count per player: 3/3 in green, 2/3 in red. The top line says "All blessed" or how many are short.
  - Missing blessings are outlined red if they're yours and orange if they're another paladin's. Hover for who.
  - The bottom lists who owes what, e.g. "Billy: [Wisdom] Bob, Sam".
  - Options > "Ready check: show raid buffs too" adds Stamina, Mark of the Wild, Intellect, Spirit, food and flask.
  - Hides in combat and comes back afterwards. Turn it off with Options > Open window on ready check.
- New preview mode for testing while solo: Options > Preview a raid (or /pulse preview) adds a pretend 13-person raid so you can see the bar, the tabs and the ready check window filled in. Nothing is cast on the pretend players. Closing the window or a /reload ends it.
- Fixed your aura turning red in combat while it was still on. It's now read from the stance bar, which the game still shows in combat.
- Much less chat spam: no more messages confirming what you just did. Errors and the debug commands still print.

## 1.0.4
- New Compact bar layout in the style of PallyPower: a thin column of rows, green when everyone is buffed, tan when expiring, red when someone is missing it. Drag the green dot to move it, click the dot to fold the rows, right-click it for assignments. It's the default for new installs; pick it under Options > Bar layout.
- The other bar layouts drop the two lines of text beside Smart Buff, so the panel is much slimmer. Turn them back on with Options > Show text beside Smart Buff. The low Symbols warning is now also in the Smart Buff tooltip.
- Smart Buff in combat no longer skips a player when you press the key during the global cooldown; it presses the same blessing again instead of moving on.
- Tooltips and the player list now open beside the bar instead of on top of it.
- The Smart Buff tooltip makes clear its counts cover all your buffs (Oath, aura and blessings).

## 1.0.3
- Oath of Light now defaults to yourself when you're solo or your target left the group.
- Fixed your own aura (e.g. Retribution Aura) showing as "Off" when it was on.
- The buff bar now says it can't be moved in combat instead of silently failing.
- New /pulse auras command lists the buffs on you, for troubleshooting.
- Smaller buff bar slots, and a new Bar layout option (Row, Wrap or Column) in Options.

## 1.0.2
- First CurseForge release.
- Removed Blessing of Sanctuary (no longer in WoW Forever).

## 1.0.1
- Removed Blessing of Sanctuary (no longer in WoW Forever).

## 1.0.0
- First release as PallyPulse.
- Smart Buff: one button (or keybind) casts the next buff you owe, and keeps working in combat
  (your friendly target first, then anyone missing a blessing at the pull, then Oath of Light).
- Alt + Smart Buff key casts your own blessing on yourself.
- Per-player exceptions and spec-aware auto-assign (tanks, healers, druid forms).
- "!bless want / clear / missing" chat requests for anyone in the group.
- One aura per paladin, Righteous Fury reminder while tanking.
- Oath of Light: own button, timer, in-combat recast, follows whoever is marked as tank.
- Re-blesses players after your Freedom / Protection / Sacrifice.
- Saves Symbols of Kings: normal blessings for small classes, low-reagent warning.
- Big blessing icons on Blizzard's party and raid frames, with Forbearance and Light's Vigil.
- Tabbed window: Blessings, Players, Group (version list) and Options.
- Syncs with PallyPower users (class, per-player and aura assignments).
