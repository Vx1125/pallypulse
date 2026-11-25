# PallyPulse

## 1.4.0
- New look for every window: dark panels, thin bronze edges, gold accents. Replaces Classic and Flat.
- Bar: dark rows with a thin status strip instead of solid green and red.
- Bar display: Standard, Compact (icons only) or Action only (only what you still owe).
- Bar options: row height, icon size and background opacity. Bar settings have their own Options tab.
- Ready check: totals and a readiness bar, Your Blessings, and Needs Attention, Fully Buffed, Unavailable and Other Paladins sections.
- Ready check: offline players count as unavailable, never as missing.
- Players tab: totals, class icons, and sorting by name, class, role or status (missing first).
- Blessings tab: your row highlighted, requests marked on the class icons, more detail in cell tooltips.
- Presets: the loaded preset shows next to the buttons, marked when assignments change.
- Versions tab: totals, a status dot and "Out of date" for old copies.
- Ready check: "Your Responsibilities" with a count and your Smart Buff key; one green line once they're all up.
- Ready check: the bar is split green / red / gray, and column icons sit inside each open section.
- Ready check: grows with its content and stops at the screen edge ("+N more").
- Players tab: Your Status and Raid Status columns. A red row means your blessing is missing; another paladin's shows tan.
- Players tab and Ready Check use the same counts.
- Bar: class names beside the icons (option), wider status strips, and "x2" and the shortest time explained in tooltips.
- Bar: the Smart row names the next blessing when the row is wide enough, and shows a tick when all is done.
- Windows are nearly opaque.
- Ready check: the header shows buffed / eligible; dead and offline players are left out of it.
- Ready check: about 30% narrower, with one column header and the list scrolling when it doesn't fit the screen.
- Ready check: Other Paladins lists each paladin with a line per blessing.
- Ready check, Players tab and the Smart Buff tooltip use one set of counts.
- Windows move back on screen after a resolution or UI scale change.
- Blessings tab: "assignment conflict" names the class, blessing and paladins; click it to flash the cells.
- A conflict only counts when a player would really get the same blessing twice, so personal blessings no longer trigger it.
- Blessings tab: option to hide classes with nobody in the group. A tan "+" marks a class no paladin blesses.
- Blessings tab: a second indicator says whether every player gets as many blessings as the paladins can give; hover for classes and players.
- Blessings tab tooltips: class members, who gets each blessing (and who doesn't), and what each paladin's sync icon means.
- Ready check: Other Paladins shows how many are pending and wraps long name lists.
- Bar: player list times no longer overlap the range bars.
- Options: General, Appearance and Advanced. Key bindings come first; every setting has a tooltip.
- Options: clearer names (Refresh before expiry, Greater Blessings from, Low symbol warning...) and units on values.
- Options: check boxes show a tick; settings that depend on another are dimmed while it's off.
- Options: Preview beside the alert sound, and Restore defaults (keeps assignments, presets and key bindings).

## 1.3.3
- Bar: the mouse wheel can switch a player back to the class blessing after Auto-assign gave them another.
- Ready check: players who said ready stay ready, and the window closes when the pull starts.
- Options > Group > Your aura: the aura Auto-assign gives you first.
- A class that joins the group after Auto-assign gets your blessing automatically, so it shows on the bar and frames.
- Players tab shows specs for every class (BM, MM, Fire, Destro...).

## 1.3.2
- Fixed: after a /reload in combat the bar showed an old panel layout until combat ended.
- Fixed: spec detection did not work on Forever. Specs are now read from the talent tabs.

## 1.3.1
- Players tab shows detected specs (Resto, Enhance, Prot...) in the Role column.
- Raid frames no longer show Light's Vigil.
- Fixed: a Holy paladin could be treated as Retribution (and get Might). Having Oath of Light now counts as Holy.

## 1.3.0
- Bar layouts are now Vertical and Horizontal, both built from the class rows.
- Removed the Row, Wrap and Column layouts and the Status text option.
- Options has two pages: General and Advanced.
- Flat style (1px edges) and a Font choice from LibSharedMedia, to match ElvUI or EllesmereUI.
- Bar X / Y position and Center.
- Profile export and import as a text string.
- Priorities: set your blessing order for each class and spec (e.g. Elemental vs Restoration Shaman).
- Priests are inspected for spec too.
- Warlocks default to Kings, then Wisdom, then Might.
- x2 on a bar row when another paladin gives that class the same blessing.
- Specs are shared between PallyPulse paladins.
- Lighter in raids: auras on mobs, nameplates and pets are ignored.
- /pulse debug cpu.
- Fixed: the bar jumping when you start dragging it or change its scale.

## 1.2.3
- Light's Vigil icon no longer disappears in combat.
- Raid frames no longer show Forbearance.
- Hunters default to Kings, then Wisdom, then Might (new Ranged role).

## 1.2.2
- Fixed: a blessing you know could be missing from the pickers (e.g. Wisdom after entering a dungeon).

## 1.2.1
- Click the blessing icon on a party or raid frame to cast it, in combat too (Options: Click icon to bless).

## 1.2.0
- Specs: hybrids and warriors are inspected out of combat (kept 60 days), so roles and Auto-assign follow spec.
- Auto-assign gives each class the blessing most of its players want.
- Range bars in the player list.
- !bless missing all, !bless report, !bless assign (leader), !bless want <name> (leader).
- !bless accepts typos in blessing names.

## 1.1.1
- Player list on the bar works in combat: hover a class, click a player (e.g. after Blessing of Protection).
- Blessings you cast in combat no longer show as Missing.
- Oath of Light no longer shows as missing in combat when it is up.
- Esc closes the ready check window.
- Class tooltip hides "Right-click: single" when a click already casts it.

## 1.1.0
- Removed Blessing of Light (replaced by Oath of Light on Forever).
- Test mode moved to a button at the top of the window.
- Test mode adds two fake paladins you can assign like real ones; fake players' buffs follow the assignments, so changes show everywhere at once.

## 1.0.9
- Shorter labels and tooltips throughout.
- Options regrouped: Bar, Raid frames, Key Bindings, Smart Buff, Group, Ready Check, Sounds.
- "Group" tab renamed "Versions".
- Clear asks for confirmation.
- Slash commands trimmed to /pulse, bar, options, check, announce. Debug tools moved to /pulse debug.

## 1.0.8
- Added Oath of Light (Mouseover) keybind. Shift-click the Oath row does the same.
- Added key bindings to Options.
- Added alert sound picker, including Radiation Ticker and LibSharedMedia sounds.
- Added separate bar, window and ready check scales.
- Removed the "Smart Buff: Oath of Light" keybind. Right-click Smart Buff still casts Oath.

## 1.0.7
- Mouse wheel over a player in the bar's player list changes their blessing.
- Smart Buff refreshes Oath of Light when there's nothing else to cast.
- Fixed the player list closing when moving the mouse onto it.

## 1.0.6
- Ready check: players missing blessings listed first, class stripes, click a paladin's line to whisper them, own scale, optional sound.
- Added options: hide aura button, fade when idle, seal button, Compact row width, grow upward, timers.
- Added Oath of Light expiring sound.
- Smart Buff row in Compact layout has a gold border and shows its key.
- Fixed the bar jumping while dragged.
- Option tooltips.

## 1.0.5
- Added ready check window with per-player blessing counts and who owes what. Raid buffs optional.
- Added test mode (fake raid).
- Fixed aura showing off in combat.
- Fewer chat messages.

## 1.0.4
- Added Compact layout (PallyPower-style rows). Default for new installs.
- Status text beside Smart Buff now optional.
- Fixed Smart Buff skipping a player when pressed during the global cooldown.
- Tooltips and player list open beside the bar.

## 1.0.3
- Oath of Light defaults to yourself when solo.
- Fixed your aura showing off when it was on.
- Smaller bar slots; Row, Wrap and Column layouts.

## 1.0.2
- First CurseForge release.
- Removed Blessing of Sanctuary.

## 1.0.0
- First release as PallyPulse: Smart Buff (works in combat), per-player and role-based assignments, !bless requests, auras, Righteous Fury, Oath of Light, raid frame icons, PallyPower sync.
