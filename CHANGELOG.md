# PallyPulse

## 1.0.8
- New Sounds section in Options: pick an alert sound from a dropdown (it plays when you pick it) and a Test sound button. Besides six game sounds, it lists sounds your other addons share through LibSharedMedia, such as DBM, BigWigs, WeakAuras or Details.
- Separate sizes in Options: Bar size, Window size (the main window) and Ready check size. Changing the ready check size opens that window so you can see it.
- Set your PallyPulse keybinds right in Options (new Keybinds section): click a button, press a key. Right-click clears it.
- Removed the separate "Smart buff: Oath of Light" keybind; the new Oath keybind and the Smart Buff key cover it. Right-clicking the Smart Buff button still casts Oath.
- Put Oath of Light on anyone quickly: a new keybind, "Oath of Light on mouseover / target" (Key Bindings > AddOns > PallyPulse), casts it on whoever your mouse is over, otherwise your target, otherwise you, and makes them your Oath target. Shift-click the Oath row on the bar does the same. Works in combat; the Oath row and Smart Buff switch to the new target after combat.

## 1.0.7
- Player list beside the bar: scroll the mouse wheel over a player to change the blessing you give them (marked with *), then click to cast it.
- Fixed the player list closing when you move the mouse onto it.
- When everyone is buffed, the Smart Buff key refreshes your Oath of Light out of combat too, instead of doing nothing.

## 1.0.6
- Ready check window:
  - Players who are short a blessing are listed first.
  - Names are white with a class-colored stripe, so every class is easy to read.
  - Click a paladin's line at the bottom to whisper them what they owe.
  - Its own size setting (Options > Ready check > Window scale).
  - Optional sound when a ready check starts and you owe blessings.
- New bar options: hide the aura button, fade when everyone is buffed, a seal button (click to cast, mouse wheel to change seal), and for the Compact layout row width, grow upward, and timers on or off.
- Optional sound when your Oath of Light has 30 seconds left.
- The Smart Buff row in the Compact layout has a gold edge and shows your keybind, so it stands apart from the other rows.
- Fixed the bar jumping away from the mouse while you drag it.
- Options are grouped into clearer sections and every option explains itself on hover.

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
