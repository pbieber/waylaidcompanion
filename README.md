# Pugger Waylaid Companion

A World of Warcraft Classic addon for the two trade factions, Durotar Supply and Logistics and the Azeroth Commerce Authority. It lists every Craftsman's Writ and Waylaid Crate, shows where each one is handed in, and tracks what is left to do today.

## What it shows

Open the window with `/pwc`, the minimap button or the addon compartment. It has four pages:

- **Overview**: your standing with your trade faction, how many writs of each tier the next standing and Exalted take, and how many daily turn-ins are left today.
- **Craftsman's Writs**: every writ for your side, by level or by profession, with the item it asks for, its reputation, its cost per reputation, how many you own, the region of its turn-in and whether it is done today. The tooltip names the NPC and gives the cost breakdown; clicking a row opens the map on the turn-in.
- **Waylaid Crates**: every crate and the items that fill it, how many of each you hold, and the Merchant's Favor it pays.
- **Turn-ins**: every place writs and crates go, a continent at a time.

The same places are marked on the world map. Hovering a marker lists the writs handed in there.

## Prices

Costs come from [Auctionator](https://www.curseforge.com/wow/addons/auctionator), which is optional. Without it the cost column stays empty and the tooltips say so.

In the cost per reputation column:

- `+ ?` means the writ or its material has no price, so the figure is only part of the cost.
- `*` means a price it is built on was last seen three or more days ago.

## Turn-ins the addon does not know yet

The shipped data does not have a turn-in for every writ. The addon learns the rest as you play: it reads the map point when a writ's quest is in your log, and notes who took the writ when you hand it in. What it learns is kept per account in `PuggerWaylaidCompanionDB`.

## Commands

| Command | What it does |
| --- | --- |
| `/pwc` or `/waylaid` | Show or hide the window |
| `/pwc writs`, `/pwc crates`, `/pwc turnins` | Open the window on that page |
| `/pwc map` | Show or hide the world map markers |
| `/pwc minimap` | Show or hide the minimap button |
| `/pwc where` | Print what the game reports for each writ in the quest log |

## Install

The addon's files are at the root of this repository, so the folder has to be named after the addon:

1. Download or clone this repository.
2. Put it in `World of Warcraft/<client>/Interface/AddOns/` as a folder named `PuggerWaylaidCompanion`.
3. Restart the game or type `/reload`.

## Scripts

Both need Python; the first also needs `lupa` (`pip install lupa`).

- `python scripts/bake_waylaid.py` reads each account's saved `PuggerWaylaidCompanion.lua` (read-only) and writes the turn-ins and Merchant's Favor recorded in game into `Data/Recorded.lua`. `--dry-run` reports without writing; `--wow` sets the game's folder.
- `python scripts/package.py` builds `dist/PuggerWaylaidCompanion-<version>.zip`, ready to unpack into `Interface/AddOns`.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
