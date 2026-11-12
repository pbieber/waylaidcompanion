# Pugger Waylaid Companion

A World of Warcraft Classic addon for the two trade factions, Durotar Supply and Logistics and the Azeroth Commerce Authority. It lists every Craftsman's Writ and Waylaid Crate, shows where each one is handed in, and tracks what is left to do today.

## What it shows

Open the window with `/pwc`, the minimap button or the addon compartment. It has four pages:

- **Overview**: your standing with your trade faction, how many writs of each tier the next standing and Exalted take, and how many daily turn-ins are left today.
- **Craftsman's Writs**: every writ for your side, by level, by profession or by cost, with the item it asks for, its reputation, what 100 reputation costs through it, how many your account owns, the region of its turn-in and whether it is done today. The tooltip names the NPC and gives the cost breakdown and who holds what; clicking a row opens the map on the turn-in.
- **Waylaid Crates**: every crate and the items that fill it, how many crates your account owns, how many of each item you carry, and the Merchant's Favor it pays.
- **Turn-ins**: every place writs and crates go, a continent at a time.

On the writs and crates pages, click a level or profession header to fold that group away; click it again to open it. Folded groups stay folded until you open them.

The same places are marked on the world map. Hovering a marker lists the writs handed in there.

## Prices

Prices come from the addon's own auction house scan and from [Auctionator](https://www.curseforge.com/wow/addons/auctionator), whichever saw the item more recently. Auctionator is optional: without it, the scan alone fills in every price.

To scan, open the auction house, then press **Scan auction house** under the writs list (or type `/pwc scan`). It searches every writ, every material a writ asks for, and every crate and what fills it, one item at a time, with a progress bar beside the button. Several hundred items take a few minutes. Closing the auction house stops the scan and keeps what it found. Prices are kept per realm and side.

In the Cost / 100 rep column:

- `+ ?` means the writ or its material has no price, so the figure is only part of the cost.
- `*` means a price it is built on was last seen three or more days ago.

## Turn-ins the addon does not know yet

The shipped data does not have a turn-in for every writ. The addon learns the rest as you play: it reads the map point when a writ's quest is in your log, and notes who took the writ when you hand it in. What it learns is kept per account in `PuggerWaylaidCompanionDB`.

## Buying at the auction house

With the auction house open, click a writ's row to buy writs and their material. A small window over the auction house takes you through two steps, showing each item with **Paying** *price* **for:** above it, and nothing is bought without a click there:

1. **The writ.** Type how many to buy, or click **Max** for every one listed; the price follows the count, cheapest first. It starts at one when your bags hold no writ, at none when they do.
2. **The material.** As many as your writs ask for (the ones in your bags plus those just bought) less what your bags already hold. If that's nothing, the window says so.

An item sold in bulk shows its price from the listings; **Buy** asks the auction house for the exact price, **Confirm** pays it. An item sold one auction at a time (writs, on WoW Forever) is paid one auction per click.

If the game blocks the addon's purchase of a writ, the window puts the writ's name in the auction house's own search box and shows the cheapest price; buy it there with the game's Buyout button, then click **Next** for the material. Materials sold in bulk are bought from the window as above.

**Skip** moves on to the next item, **Cancel** stops. With the auction house closed, a click opens the map instead.

## Writs on other characters

The Owned column counts the writs on every character of the account: bags, bank and mailbox. Another character counts as it was when you last played it, the bank as it was when last open there. A number on its own is on the character you are playing; a writ on another character shows that character's name. Tick **Show both names** under the writs list, or type `/pwc names`, to name two other characters instead of one. The crates page counts crates the same way. The tooltip lists every character and where they keep them, for the writ and for its material.

## Commands

| Command | What it does |
| --- | --- |
| `/pwc` or `/waylaid` | Show or hide the window |
| `/pwc writs`, `/pwc crates`, `/pwc turnins` | Open the window on that page |
| `/pwc map` | Show or hide the world map markers |
| `/pwc minimap` | Show or hide the minimap button |
| `/pwc scan` | Start or stop the auction house scan |
| `/pwc names` | Show one or both names of other characters in the Owned column |
| `/pwc where` | Print what the game reports for each writ in the quest log |

## Install

The addon's files are at the root of this repository, so the folder has to be named after the addon:

1. Download or clone this repository.
2. Put it in `World of Warcraft/<client>/Interface/AddOns/` as a folder named `PuggerWaylaidCompanion`.
3. Restart the game. After an update `/reload` is enough, unless the update adds a file.

## Scripts

Both need Python; the first also needs `lupa` (`pip install lupa`).

- `python scripts/bake_waylaid.py` reads each account's saved `PuggerWaylaidCompanion.lua` (read-only) and writes the turn-ins and Merchant's Favor recorded in game into `Data/Recorded.lua`. `--dry-run` reports without writing; `--wow` sets the game's folder.
- `python scripts/release.py` builds `dist/PuggerWaylaidCompanion-<version>.zip`, the file to upload to CurseForge. Give it a version, as in `python scripts/release.py 0.4.0`, to write that into the toc first.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
