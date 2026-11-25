# PallyPulse UI Design Standard

The look as of 1.4.0 is frozen. New features use what is described here instead of new styles.
Change it only for a real usability problem, and update this file in the same commit.

## Principles

- The interface answers three questions at a glance: what is missing, which of it is mine, and
  what my next key press will do.
- Immediate information goes in the window, explanations go in tooltips, and setup goes in
  Options. Nothing on screen is an instruction paragraph.
- Colour carries meaning, never decoration, and is always backed by text, a count, an icon or a
  tooltip.
- Combat-safe first: secure buttons are only shown, hidden or moved out of combat.

## Colours (`ns.STYLE` in Data.lua)

| Token      | Hex       | Use |
|------------|-----------|-----|
| `bg`       | `#141311` at 98% | Window background |
| `panel`    | `#201E1A` | Buttons, tracker rows, neutral rows |
| `header`   | `#242019` | Title bars, section headers |
| `cell`     | `#171613` at 90% | Icon wells, input boxes |
| `border`   | `#51432B` | Every 1px edge and divider |
| `gold`     | `#D6B266` | Headings, active tab, focus, Smart Buff row edge |
| `text`     | `#E0DBD0` | Body text |
| `dim`      | `#938C80` | Secondary text, hints |
| `rowSel`   | `#38301E` | Your own row |
| `rowMiss`  | `#35231E` | A row where **your** blessing is missing |
| `rowHover` | `#2C2820` | Hover |
| `rowAlt`   | white at 2.5% | Alternate rows |
| `paladin`  | class pink | Paladin row edge, Oath of Light |

Status colours have one meaning in every window:

| Token   | Hex       | Meaning | Paired text |
|---------|-----------|---------|-------------|
| `good`  | `#94BA78` | Active, ready, buffed | time left, "Ready", "Active" |
| `warn`  | `#D6B266` | Expiring | time left |
| `bad`   | `#D17665` | Your blessing missing, conflict | "Missing", count |
| `other` | `#B89D67` | Another paladin's blessing missing, unassigned | "Incomplete", paladin name |
| `off`   | `#938C80` | Dead or offline | "Dead", "Offline" |

A whole row turns red only when the local paladin has to act.

## Typography

- Headings, tabs, button labels: Friz Quadrata (`S.head`), 11-14 px, gold for headings.
- Body: the client's standard font (`S.font`), 11-12 px.
- Counts and timers: Arial Narrow (`S.num`), outlined on icons.
- Every font string has a 1px black shadow. Text is created with `W.Text` so the Font option
  (LibSharedMedia) reaches it.

## Window shell

- `W.Panel`: flat fill, 1px `border` edge. Windows are 98% opaque.
- Title bar: 24-26 px `header` band with a 1px `border` line under it; title in gold at the
  left; close is a small dim "x" (`W.CloseButton`) at the top right.
- Tabs: text only, dim when inactive, gold with a 1-2 px gold underline when active, a thin
  `border` rule under the tab row.
- Padding: 10 px inside windows (`PAD`); 16 px left column and 270 px second column on
  Options pages.
- Windows are draggable by the title (or anywhere on the Ready Check), clamped to the screen,
  and moved back on screen after a resolution or UI scale change. Each has its own scale.

## Controls (Widgets.lua)

| Widget | Size | Notes |
|--------|------|-------|
| `W.Button` | 22 px high (18 in title bars) | `panel` fill, `border` edge, gold edge and label on hover |
| `W.Check` | 24 px hit box, 14 px box | gold square when on |
| `W.Stepper` | 24 px row, 24x20 buttons | value in gold between - and + |
| `W.Dropdown` | 24 px row, 140x20 button | menu is a `W.Panel` |
| `W.NumberBox` | 64x20 | `cell` well |
| `W.Section` | 12 px gold heading | 1px `border` rule under it |
| `W.SkinScroll` | 4 px thumb | no arrows |

Options rows step 27 px; headings 22 px.

## Icons and rows

| Element | Size |
|---------|------|
| Tracker row | 22 px high (16-32, option), 76 px wide (60-140, option) |
| Tracker icons | 18 px (option), class icon then blessing icon |
| Tracker status strip | 3 px, left edge (bottom edge on Compact cells) |
| Blessings grid cell | 26 px, 3 px gap; class header icons 20 px |
| Players / Versions rows | 22 px; class icon 14 px; blessing cell 20 px |
| Ready Check rows | 18 px; matrix cells 16 px, 3 px gap; section headers 18 px |
| Flyout rows | 20 px; 16 px icons; three-bar range meter |
| Blessing icons | always native, cropped 8% (`SetTexCoord(0.08, 0.92, 0.08, 0.92)`) |

## Status indicators

- Tracker: dark row, 3 px strip (green / gold / red), red missing count, timer in text colour
  or gold when expiring, small tick on the Smart row when everything is up.
- Matrix cells: icon = active; red edge = yours missing; tan edge = another paladin's missing;
  faint edge = not assigned; dimmed row = dead or offline.
- Assignment grid: red edge = conflict; tan "+" = a class in the group nobody blesses; dim "+" =
  unassigned; grey icon = a blessing that paladin doesn't know.
- Totals are always "Buffed · Missing · Unavailable" from `ns.ReadinessSummary`, and the
  Ready Check header is buffed / eligible (dead and offline left out).

## Information hierarchy

1. Tracker: the Smart row (next press) first, then rows that need you.
2. Ready Check: totals and bar, Your Responsibilities, then sections (Needs Attention open;
   Fully Buffed, Unavailable and Other Paladins closed; the player's choice is remembered).
3. Main window: Blessings (assign), Players (per player), Versions (sync), Options.

## Words

Smart Buff, All buffed, Missing, Expiring, Ready, Active, Dead, Offline, Incomplete, Single,
Scale, Next Blessing, Your Responsibilities, assignment conflict. No chat messages confirming
actions.
