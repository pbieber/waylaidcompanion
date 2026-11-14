# Pugger Waylaid Companion

A World of Warcraft Classic addon for the two trade factions, Durotar Supply and Logistics and the Azeroth Commerce Authority. It lists every Craftsman's Writ and Waylaid Crate, where each is turned in, and what is left today.

## Pages

Open the window with `/pwc`, the minimap button or the addon compartment.

- **Overview**: your standing, the turn-ins to the next standing and to Exalted, and what is open today.
- **Craftsman's Writs**: every writ for your side, by tier, profession or cost: material, rep, cost (per 100 rep by default), owned, zone of the turn-in, today. Click a row: map (or, at the auction house, buy).
- **Waylaid Crates**: every crate, by tier, profession or cost: the Merchant's Favor it pays, its cost with its cheapest material (per favor by default), owned. Each material under a crate shows the crate's cost filled with that one, and the cheapest is ticked. Crates of gathered goods (herbs, ore, textiles, curiosities) are white, crates of crafted goods (ingots, fabrics, parts) green, and a green crate pays twice the favor of a white one of its tier. A turn-in also pays half its favor in silver (5 favor, 2s 50c); that comes off the cost unless you untick **Count the turn-in's silver** under Options. At the auction house, click a crate's row to buy it.
- **Fastcraft**: the crates in your bags, the materials in your bags that fill them, and how many crates that fills. **Craft** fills them all, one kind after the other (below).
- **Turn-ins**: every turn-in, by continent. Also marked on the world map.
- **Rewards**: what your faction's quartermasters sell, one list per profession, each with its own quartermaster, by standing, with its cost and whether you can buy it. Learned the first time you open each quartermaster's shop.
- **Transfer**: mail, bank and buying for writs (below).
- **Options**, at the foot of the menu: show writ and crate costs per reputation and per favor, or absolute; the scale (per 1, 10, 100 or 1000 rep or favor, each on its own); item names by tier colour or in their in-game rarity colour (the tier then shows in the Profession column's colour, or in the Tier column when sorted by profession); **Show both names**; and the window's **Style**, Modern (flat and dark) or Classic (the game's own frames), which changes after a reload.

Click a group header to fold it.

## Prices

Prices come from the addon's own auction house scan and from [Auctionator](https://www.curseforge.com/wow/addons/auctionator), whichever saw the item more recently. Auctionator is optional: without it, the scan alone fills in every price.

On any list, drag a column's heading onto another to move the column there; each page remembers its order, and **Reset order** under Options puts them back. The writs page shows the reputation at the end of the row.

To scan, open the auction house, then press **Scan AH** under a list. Under the writs list it searches every writ and every material a writ asks for; under the crates list every crate and what fills it. It goes one item at a time, with a progress bar beside the button; a few hundred items take a few minutes. `/pwc scan` searches both lists' items. Closing the auction house stops the scan and keeps what it found. Prices are kept per realm and side. Each bar's **Last scan** is when a scan of its own list last ran to the end; a scan of the other list doesn't count, though the two share materials.

In the Cost / 100 rep column:

- `+ ?` means the writ or its material has no price, so the figure is only part of the cost.
- `*` means a price it is built on was last seen three or more days ago.

## Turn-ins the addon does not know yet

The shipped data does not have a turn-in for every writ. The addon learns the rest as you play: it reads the map point when a writ's quest is in your log, and notes who took the writ when you hand it in. What it learns is kept per account in `PuggerWaylaidCompanionDB`.

## Sharing what you've learned

Type `/pwc export` to get a string of what the addon has learned on your account: the turn-ins, the writs the data wrongly limits to one side, and what each quartermaster sells. It holds nothing about your characters, bags, mail or gold. Press Ctrl+C to copy it, then post it as an issue on the [addon's GitHub page](https://github.com/pbieber/waylaidcompanion/issues) (attach it as a .txt file if it is long), and it goes into the next release for everyone. You can also give it to another player directly.

To add a string someone shared, type `/pwc import`, paste it with Ctrl+V and press **Import**. Only what your account doesn't know yet is added: a turn-in you or the addon already know stays, and a quartermaster's list is replaced only by a newer one. Importing the same string twice changes nothing.

## Buying at the auction house

With the auction house open, click a writ's or a crate's row. The buy window shows each item under **Paying** *price* **for:**. Nothing is bought without a click.

1. **Writ or crate.** Type an amount, or **Max** for all listed. Cheapest first; one click per writ.
2. **Material.** Your writs or crates (in bags plus bought) times what each asks for, minus what your bags hold. For a crate it's the crate's cheapest material, and crates that other materials in your bags already fill need none.

Material sold in bulk: **Buy** gets the exact price, **Confirm** pays. **Skip** moves on, **Cancel** stops.

Prices more than 3 minutes old are searched again first: when an item was last scanned longer ago, and when you click **Buy** on an offer that has sat that long (it then shows the new price, and what it was). The lowest price each search finds replaces the item's price on the writs and crates pages.

## Filling crates

On the crates page, click a material under a crate. The window says how many of the crates in your bags it fills. **Fill a crate** uses a crate and picks the material for you, which starts the cast; click again after each cast, one click per crate. Not in combat.

To fill every crate in your bags, open **Fastcraft** and click **Craft**. The same window opens on the first crate your bags can fill; when that kind is done it moves on to the next by itself, until nothing is left to fill. It is still one click per crate. Where a crate's first material runs short, the next one in your bags fills the rest.

For a crafted material (a bar, a bolt, a cured hide, an engineering part) the window also lists the recipes that make enough of it for the crates in your bags, what it is made of first; set **Craft for crates** to craft for more or fewer. Nothing is crafted without a click.

1. Open the profession. The addon reads its recipes while its window is open, and keeps them until you log out.
2. Click **Craft**. One click crafts one recipe as often as your bags allow; the queue moves on as the bags fill.

A recipe of another profession (bars for engineering parts) shows `open` and its profession: open that one to craft it. `Missing` is what the bags lack and no recipe you know makes.

## Transfer

A *set* is one writ and its material.

- **Mail**: one set of each writ in your bags to a character, up to 12 attachments a mail; click **Send** for each. Needs a mailbox on the Send Mail tab. Your alts are listed once you have logged in on them (mail goes to first name and surname). Type any other name to send to it, or **Save** it as a button.
- **Bank**: needs the bank open. **Bank to bags** and **Bags to bank**, each with:
  - **1 of each**: a writ of each kind and its material (into the bags: only kinds the bags lack).
  - **Extra**: every writ but one of each kind.
  - **All writs**: every writ.
- **Buying**: needs the auction house open. **Buy missing material** buys what the writs in your bags still need.

## Writs on other characters

The Owned column counts the writs on every character of the account: bags, bank and mailbox. Another character counts as it was when you last played it, the bank as it was when last open there. A number on its own is on the character you are playing; a writ on another character shows that character's name. Tick **Show both names** under Options, or type `/pwc names`, to show first name and surname. The crates page counts crates the same way. The tooltip lists every character and where they keep them, for the writ and for its material.

## Commands

| Command | What it does |
| --- | --- |
| `/pwc` or `/waylaid` | Show or hide the window |
| `/pwc writs`, `/pwc crates`, `/pwc fastcraft`, `/pwc turnins`, `/pwc rewards`, `/pwc transfer`, `/pwc options` | Open the window on that page |
| `/pwc map` | Show or hide the world map markers |
| `/pwc minimap` | Show or hide the minimap button |
| `/pwc scan` | Start or stop the auction house scan of writs and crates (`/pwc scan writs`, `/pwc scan crates`: one) |
| `/pwc names` | Show first name only, or first name and surname |
| `/pwc where` | Print what the game reports for each writ in the quest log |
| `/pwc export` | Show a string of what the addon has learned, to share |
| `/pwc import` | Add what a shared string knows |
| `/pwc shop` | At an open shop, print what the Rewards page reads from it |

## Install

The addon's files are at the root of this repository, so the folder has to be named after the addon:

1. Download or clone this repository.
2. Put it in `World of Warcraft/<client>/Interface/AddOns/` as a folder named `PuggerWaylaidCompanion`.
3. Restart the game. After an update `/reload` is enough, unless the update adds a file.

## Scripts

Both need Python; the first also needs `lupa` (`pip install lupa`).

- `python scripts/bake_waylaid.py` reads each account's saved `PuggerWaylaidCompanion.lua` (read-only) and the strings players shared, and writes the turn-ins, writs for both sides and quartermasters' rewards into `Data/Recorded.lua`. Save shared strings as `.txt` files in `shares/` (several per file and line breaks are fine), or name files on the command line. `--dry-run` reports without writing; `--no-saved` leaves out this computer's saved data; `--wow` sets the game's folder.
- `python scripts/release.py` builds `dist/PuggerWaylaidCompanion-<version>.zip`, the file to upload to CurseForge. Give it a version, as in `python scripts/release.py 0.4.0`, to write that into the toc first.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
