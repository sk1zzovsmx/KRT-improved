# KRT: Kader Raid Tools — Improved (Total Rework)
AddOn Version: **0.5.6c**  
Game Version: **Wrath of the Lich King 3.3.5a** (Interface **30300**)

Copyright (C) 2018 **Kader Bouyakoub**  
This repository is an **improved / reworked** fork focused on **raid-leading quality-of-life**, **master-loot automation**, **SoftRes integration**, and a **more robust raid/loot history**. All rights goes to Kader.
It took a lot of time, effort for who isn't a code developer like ME. So please, for sake, do not judge.

---

## Highlights

- **Master Looter toolkit**: roll workflow (MS / OS / SR / Free), countdown, auto-award, and trade helpers.
- **SoftRes Reserves integration**:
  - **Multi-reserve** support (players can reserve the same item multiple times / quantity > 1)
  - **Plus System (P+)** priority mode
  - UI list grouped by **boss/source**, collapsible, with tooltips and chat-safe output
- **Loot Counter**: track **MS loot wins per player** in the current raid session, with an editable UI.
- **Loot History**: persistent raid sessions with roster, bosses, attendees, and loot. Includes safer internal IDs and filters.
- **Pre-saved Raid Warnings** + **MS Changes** tracker.
- **LFM Spammer** with composition builder and achievement ID helper.
- **Minimap button menu** + consolidated **/krt** slash commands.
- Built-in **debug / log levels** for troubleshooting.

---

## Installation

1. Download / clone the repository.
2. Copy the folder **`!KRT`** into:
   - `World of Warcraft/Interface/AddOns/`
3. Restart the game or type `/reload`.

> Tip: make sure you don’t have multiple copies of KRT enabled at the same time.

---

## Quick Start

- **Open the configuration**
  - Minimap button: **Right-click**
  - Slash: `/krt config`

- **Open the main menu**
  - Minimap button: **Left-click**
  - From there you can open Master Looter, Loot Counter, Loot Logger, Warnings, MS Changes, and the LFM Spammer.

- **Open Master Looter**
  - `/krt ml` (aliases: `/krt loot`, `/krt master`)

- **Import SoftRes reserves**
  - `/krt res import`
  - Or click the **Reserves** button in the Master Looter window (it opens Import if no reserves are loaded yet).

---

## Slash Commands

Main entrypoints:
- `/krt`
- `/kraidtools`

Common commands:
- `/krt config` — open config (`/krt config reset` restores defaults)
- `/krt ml` — Master Looter window
- `/krt counter` — Loot Counter window
- `/krt history` — Loot Logger / History window
- `/krt rw` — Raid Warnings window (`/krt rw <ID>` announces a saved warning)
- `/krt ms` — MS Changes window (`/krt ms demand` / `/krt ms announce`)
- `/krt lfm` — LFM Spammer window (`/krt lfm start` / `/krt lfm stop`)
- `/krt res` — Reserves list (`/krt res import` opens the import window)
- `/krt minimap on|off|pos <deg>` — show/hide button or set position angle
- `/krt debug on|off|level <name|num>` — toggle debug and/or set log level

---

## Features

**FIRST OF ALL**
## UI Multi-Select (Ctrl / Shift)

Several KRT panels use an **OS-like multi-selection** system to make lists faster to operate.

### Common rules (lists)
- **Left-click** focuses a row (the focused row drives dependent panels where applicable).
- **Ctrl + Left-click** toggles a row in/out of the selection (multi-select).
- **Shift + Left-click** selects a **range** from the last anchor to the clicked row.
- **Ctrl + Shift + Left-click** adds/removes a **range** while keeping the existing selection.
- The addon keeps a single **focused** entry even when multiple rows are selected.


### 1) Master Looter (Loot Master)

<img width="482" height="478" alt="image" src="https://github.com/user-attachments/assets/3133bf8f-3e57-4ac0-806b-afd50f6ad1a3" />

The Master Looter window is designed to reduce clicks and mistakes during loot distribution while keeping the workflow fast and predictable.

**Core workflow**
- **Select Item**: pick a loot slot from the current boss loot, or remove an inventory item from the window.
- **Spam Loot / Ready Check**: announce what dropped (boss loot) or do a ready-check before rolling (inventory rolls).
- **Roll types**:
  - **MS / OS / SR / Free**
- **Countdown**: starts/stops a countdown and (optionally) blocks late rolls during the countdown.
- **Award / Trade**:
  - In loot window: awards via master loot.
  - From inventory: assists with trading (and can mark players with raid icons for quick identification).

**Multi-award (multiple identical copies)**
- If the same item drops **multiple times** (or you set an item count > 1), you can **pick multiple winners** and award them sequentially.

**Hold / Bank / Disenchant**
- Assign items to:
  - **Hold** (loot holder)
  - **Bank** (reserved materials / BoEs, etc.)
  - **DE** (disenchanter)
- Optional: announcement + whisper for these assignments (see Configuration).

**Quality-of-life and safety**
- Optional **stack protection** (prevents accidental stack trading).
- Optional **screen reminder** for trade/award actions.
- Optional **Raid Warning vs Raid chat** announce behavior.

### Master Looter: Multi-select winners (roll list)
When rolling loot **directly from the loot window**, KRT supports **manual multi-winner picking** in the roll list:

- Selection becomes available **after the countdown ends**.
- KRT **auto-prefills** the selection with the **top N** rollers, where **N = ItemCount** (number of identical copies to award).
- Use **Ctrl + Click** on player rows to **toggle winners**.
- The selection is **capped to N** (you can’t select more winners than the number of copies you’re awarding).
  - If **N = 1**, Ctrl+Click on another player acts like a **swap** (replaces the current winner).
- Selected winners are visually highlighted and shown as: `> Name <`.
- Press **Award** to award **exactly the selected winners** (clamped to available copies), sequentially.

> Note: while a multi-award sequence is running, winner selection is temporarily locked to avoid mistakes.

---

### 2) SoftRes Reserves (Import + List + SR Roll Support)

<img width="231" height="483" alt="image" src="https://github.com/user-attachments/assets/2cbfba09-01eb-42cd-ab9a-0a7e1059d6ab" />

This fork adds a full reserves system that integrates directly into the Master Looter workflow.

#### Import (SoftRes CSV)
Open the import dialog:
- `/krt res import`
- or via Master Looter **Reserves** button.

<img width="398" height="296" alt="image" src="https://github.com/user-attachments/assets/e985fe7e-b4b3-48b6-bdac-1464419ddf0c" />

You can switch import mode:
- **Multi-reserve**: supports *quantity > 1* reserves and/or multiple reserves per player.
  
  If you are able to see if a player has reserved the same item multiple times, even if it is already reserved.

<img width="375" height="531" alt="image" src="https://github.com/user-attachments/assets/a096b162-d8dc-4878-b44f-bcf244eb3a30" />

- **Plus System (P+)**: supports **one reserved item per player**, with optional **priority (P+)** values.

  Due the limitation of Soft Reserve you have to force only **one item pick** for player so you can use the **plus** function on the website as a priority.

<img width="371" height="531" alt="image" src="https://github.com/user-attachments/assets/9abbd237-8749-4515-a026-8a741465c8d2" />

If you try to import a CSV that doesn’t match the selected mode, the addon will warn you and can auto-switch you to the correct mode.

#### Reserve List UI
- Shows reserved items with:
  - Item icon + name/link
  - Players list (compact + tooltip with full details)
  - Grouped by **boss/source**, with collapsible headers

#### SR Roll integration
When rolling as **SR**:
- Reserved players are highlighted in the roll list.
- **Multi-reserve**:
  - The addon tracks how many rolls each player is allowed (e.g. 2 reserves → up to 2 valid rolls)
  - Extra rolls are blocked (and can be whispered)
- **Plus System (P+)**:
  - Priority is shown in the roll list as `(P+N)`
  - Winner selection prefers higher P+ first (then roll)

The SR announce messages are **chat-safe** (UI can use class colors, but chat output avoids color codes that may break formatting).

---

### 3) Loot Counter (MS Wins)

<img width="259" height="356" alt="image" src="https://github.com/user-attachments/assets/b850232d-0b3d-4ae8-b4d6-e21ca62c4828" />

A lightweight counter to track **how many MS items** each player has won in the current raid session.

- Standalone window: `/krt counter`
- Integrated display in Master Looter:
  - optional `+N` shown next to players during **MS** rolls
- Counts are updated automatically when an **MS award is confirmed by loot chat** (authoritative event-driven logging).

---

### 4) LFM Spammer (Grouping / PUG)

<img width="258" height="374" alt="image" src="https://github.com/user-attachments/assets/7c438638-ffd2-4731-a8bf-0de1007e5d9e" />

Stop rewriting your LFM message every time your group changes.

- Build a message from:
  - raid name
  - role composition (tanks/healers/melee/ranged)
  - optional class requirements
  - extra free-text notes
- Select channels + set spam period and start/stop.
- Supports achievement IDs via `{1234}` in the message.

**Achievement ID helper**
- Shift-click an achievement link into chat and use:
  - `/krt ach <paste-the-link>`
- The addon prints the achievement ID you can use as `{ID}`.

---

### 5) Pre-Saved Raid Warnings

<img width="596" height="241" alt="image" src="https://github.com/user-attachments/assets/37a6ff30-a7b4-467e-b508-b10e83c448ed" />

Save raid warning templates and reuse them instantly.

- Create, edit, delete warnings.
- Announce via:
  - click → **Announce**
  - **Ctrl+Click** on a saved entry
  - `/krt rw <ID>` (macro-friendly)

Warnings are stored across characters.

---

### 6) MS Changes (Main Spec Changes)

<img width="248" height="201" alt="image" src="https://github.com/user-attachments/assets/1cb1e664-ce2a-47ff-98b9-01ae6a465e77" />

Track what people are rolling as (MS changes) so you don’t lose track mid-raid.

- Add / edit changes manually
- Ask the raid to whisper you their changes:
  - `/krt ms demand`
- Spam the collected changes:
  - `/krt ms announce`
- Ctrl+Click can be used for quick single-player spam (where supported by the UI).

---

### 7) Loot History (Loot Logger)

<img width="829" height="485" alt="image" src="https://github.com/user-attachments/assets/cbf6b20c-a876-4a53-a4e8-db0b33f256c1" />

Stores:
- raid sessions (zone + size)
- roster + replacements
- boss encounters (including trash entries where used)
- attendees per encounter
- loot with winner + win type + roll value + timestamp

**Notes / improvements in this rework**
- Safer internal IDs for bosses and loot entries (helps prevent overwrite issues).
- Filtering by boss and/or player.
- Some low-value items can be ignored from logging (e.g., badges/emblems) via an internal ignore list.

### Loot Logger: Multi-Select (UI Lists)

The **Loot Logger** uses an OS-like selection model across its lists (**Raids**, **Bosses**, **Boss Attendees**, **Raid Attendees**, **Loot**).

#### Controls
- **Left-click**: focuses a row (the focused row drives dependent panels and filters).
- **Ctrl + Left-click**: toggles a row in/out of the selection (multi-select).
- **Shift + Left-click**: selects a **range** from the last anchor to the clicked row.
- **Ctrl + Shift + Left-click**: adds/removes a **range** while keeping the existing selection.

#### Focus vs Selection
- You can have **multiple selected** rows, but only **one focused** row at a time.
- The focused row is used for **Edit**, **Set Current**, and other single-target actions.

#### Bulk actions (why multi-select matters)
Multi-select is primarily used for **batch delete** operations (the **Delete** button shows a count):
- **Raids**: delete multiple raids at once (**the current raid is protected and cannot be deleted**).
- **Bosses**: delete multiple encounters (their associated loot entries are removed too).
- **Attendees** (Boss/Raid): delete multiple names in one action.
- **Loot**: delete multiple loot rows in one action.

#### Loot context menu
- **Right-click** on a loot row forces a **single focused row** and opens the context menu  
  (multi-select is not used for the context menu).

#### Filter exclusivity
- Selecting a **Boss Attendee** clears the **Raid Attendee** filter (and its selection), and vice versa,
  to avoid mixed filters.

Export buttons exist in UI but may be disabled / not implemented in this branch.

---

## Minimap Button

- **Left-click**: open the quick menu (Master Looter, Counter, Logger, Warnings, MS Changes, LFM, etc.)
- **Right-click**: open Configuration
- **Shift + drag**: move on the minimap ring
- **Alt + drag**: free-drag mode (place anywhere)

You can also control it via:
- `/krt minimap on|off|pos <deg>`

---

## Debug / Troubleshooting

KRT includes a lightweight logger with log levels.

- Toggle debug:
  - `/krt debug on`
  - `/krt debug off`
- Set log level:
  - `/krt debug level info|debug|trace|spam` (names/numbers supported)

---

## Credits

Original addon: **Kader Bouyakoub** (2018).  
This fork contains additional rework and features while keeping the original goal: **make raid leading easier**.
