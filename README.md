# LoadoutLocker

Save your equipped gear to each talent loadout and automatically swap when you switch builds.

Built for **World of Warcraft: Midnight** (Interface `120007`).

## Features

- **Per-loadout gear sets** — each saved talent loadout can have its own gear snapshot
- **Auto-equip on loadout change** — switching loadouts applies the linked gear set after talents commit
- **Smart swapping** — two-phase unequip/equip handles embellished items and slot conflicts
- **Combat-safe** — gear swaps queue until combat ends
- **Talent UI button** — Save Gear button below the loadout dropdown on the talent panel
- **Character-specific saves** — data stored per character, per specialization

## Installation

1. Copy the `LoadoutLocker` folder into your WoW `Interface/AddOns` directory
2. Enable **LoadoutLocker** on the character select screen
3. `/reload` if you add or update the addon while logged in

## Usage

### Save gear

1. Equip the gear you want for a loadout
2. Select that talent loadout (or switch to it)
3. Click **Save Gear** on the talent panel, or run:

```
/locker save
```

Re-saving updates the gear set for that loadout. The button label changes to **Update Gear** when a set already exists.

### Switch loadouts

Select a different talent loadout as usual. If a saved gear set exists for that loadout, LoadoutLocker equips it automatically after the talent change completes.

Loadouts with no saved gear are left unchanged.

### Slash commands

| Command | Description |
|---------|-------------|
| `/locker save` | Save currently equipped gear to the active talent loadout |
| `/locker list` | List saved gear sets for your current specialization |
| `/locker delete` | Remove the saved gear set for the active talent loadout |
| `/locker help` | Show command help |

`/loadoutlocker` is an alias for `/locker`.

## Limitations

- **Starter Build** loadouts cannot be saved
- Requires enough bag space for gear swaps that need items moved out of equipment slots
- Missing items are skipped with a chat message; other slots still swap
- Gear swaps do not run in combat (queued until combat ends)

