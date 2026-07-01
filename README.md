# LoadoutLocker

Save your equipped gear to each talent loadout and automatically swap when you switch builds. Assign loadouts to dungeons, raids, delves, and PvP content and get prompted when it is time to switch — including loadouts from other specializations.

Built for **World of Warcraft: Midnight** (Interface `120007`). Current version: **1.11.0**.

## Features

- **Per-loadout gear sets** — each saved talent loadout can have its own gear snapshot
- **Auto-equip on loadout change** — switching loadouts applies the linked gear set after talents commit
- **Cross-spec loadouts** — content assignments can target any specialization and talent loadout on your class; prompts handle spec, talent, and gear changes in order
- **Smart swapping** — two-phase unequip/equip handles embellished items and slot conflicts
- **Talent UI button** — Save Gear button below the loadout dropdown on the talent panel
- **Equipment Manager sync** — saved gear is mirrored to a Blizzard equipment set (named after the loadout) so you can equip from the character panel too
- **Upgrade scan** — when applying a loadout, prompts if a same-name bag item is better (track, ilvl, or tertiary stats)
- **Content loadout prompts** — assign default and per-content loadouts for dungeons, raids, delves, and PvP; get an in-game prompt when entering or when raid bosses need a different build
- **In-game menu** — `/locker` opens General, Priority, Loadouts, Dungeons, Raids, Delves, and PvP tabs
- **Loadout management** — overview table, copy gear sets between loadouts, delete saved sets, clear ignored upgrade slots
- **Options integration** — also listed under **Esc → Options → AddOns**

## Installation

1. Copy the `LoadoutLocker` folder into your WoW `Interface/AddOns` directory
2. Enable **LoadoutLocker** on the character select screen
3. `/reload` if you add or update the addon while logged in

On first login per account, LoadoutLocker shows a short getting-started guide. Skip it anytime, or reopen with `/locker tutorial`.

## Usage

### Save gear

1. Equip the gear you want for a loadout
2. Select that talent loadout (or switch to it)
3. Click **Save Gear** on the talent panel, or run:

```
/locker save
```

Re-saving updates the gear set for that loadout. LoadoutLocker also keeps the matching Blizzard equipment set in sync.

### Switch loadouts

Select a different talent loadout as usual. If a saved gear set exists for that loadout, LoadoutLocker equips it automatically after the talent change completes.

Loadouts with no saved gear are left unchanged.

When you accept a **Switch Loadout** prompt for another specialization, LoadoutLocker changes spec first, then talents, then gear. The prompt shows progress while the swap runs and closes when finished.

### Upgrade scan

When you switch loadouts (or run `/locker scan`), LoadoutLocker checks your bags for items with the **same name** as saved set pieces. You are prompted to use a better item when:

1. **Higher upgrade track** — Myth > Hero > Champion > Veteran > Adventurer (plus special tracks such as Sporefused and Ascendant Voidforged)
2. **Same track, higher item level**
3. **Same track and item level** — compares bonus stats using your tertiary priority (default: Sockets > Avoidance > Leech > Speed)

Accepting an upgrade updates the saved loadout gear and equips it.

Use **Do not ask again** on a prompt to ignore that equipment slot for the current loadout. Manage ignored slots on the **Loadouts** tab. Turn upgrade prompts on or off on the **General** tab.

### Content loadout prompts

Use the **Dungeons**, **Raids**, **Delves**, and **PvP** tabs to pick a default talent loadout for each activity type, then optionally override individual dungeons, bosses, delves, or PvP modes. Assignments can use loadouts from any specialization on your class.

When you enter matching content (or after a raid boss kill, when remaining bosses need different loadouts), LoadoutLocker shows a prompt to switch loadouts. Click **Switch Loadout** to apply the assignment; click **Not now** to dismiss it for the current visit.

Raid prompts respect your lockout progress — bosses you have already killed are skipped.

Toggle each prompt type on the **General** tab:

- Dungeons
- Raids (entering and after boss kills)
- Delves
- PvP

### Slash commands

| Command | Description |
|---------|-------------|
| `/locker` | Open the LoadoutLocker menu |
| `/locker save` | Save currently equipped gear to the active talent loadout |
| `/locker list` | List saved gear sets for your current specialization |
| `/locker delete` | Remove the saved gear set for the active talent loadout |
| `/locker scan` | Check bags for better versions of saved loadout items |
| `/locker tutorial` | Show the getting started guide |
| `/locker debug` | Open bug report with debug info |
| `/locker help` | Show command help |

## Limitations

- **Starter Build** loadouts cannot be saved or used as a copy target
- Requires enough bag space for gear swaps that need items moved out of equipment slots
- Missing items are skipped with a chat message; other slots still swap
- Gear swaps do not run in combat — the swap is cancelled if combat starts mid-swap
- Blizzard equipment sets share a game-wide limit; LoadoutLocker warns if it cannot create a set
- Cross-spec switches require an out-of-combat spec change; cancelling the spec cast (for example by moving) aborts the prompt swap
