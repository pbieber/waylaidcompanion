"""Bake what Pugger Waylaid Companion recorded in game into the addon's shipped data.

Reads every account's SavedVariables/PuggerWaylaidCompanion.lua in the WoW Forever client
(read-only) and the strings other players shared with /pwc export, merges them with what
is already in Data/Recorded.lua, and rewrites that file:

  - where each Craftsman's Writ is handed in (an NPC, or a map spot nobody has named yet);
  - the writs Data/Writs.lua limits to one side that players had on the other;
  - what each quartermaster sells (the newest list of each wins).

Shared strings are read from the .txt files in shares/ (any number of strings per file,
line breaks inside a string are fine) and from any files named on the command line. They
are decoded by the addon's own Share.lua, which keeps only the shapes it expects: a
shared string is never run as code.

No writ is ever dropped: one already in Recorded.lua stays unless the saved data knows
better (an NPC's name for what was only a spot, or a spot the addon has since moved to the
zone it really lies in).

    python scripts/bake_waylaid.py [--wow "C:/Program Files (x86)/World of Warcraft"] [--dry-run]
                                   [--no-saved] [share.txt ...]

Needs lupa (pip install lupa) to read the Lua files.
"""
from pathlib import Path
import argparse
import re
import sys

try:
    from lupa import lua51 as lupa
except ImportError:  # older lupa builds
    import lupa

# The repository's root is the addon folder.
ROOT = Path(__file__).resolve().parents[1]
ADDON = ROOT
OUT = ADDON / 'Data' / 'Recorded.lua'
SHARES = ROOT / 'shares'
SHARE_STRING = re.compile(r'PWC1:[0-9a-fA-F]{8}:[A-Za-z0-9+/=\s]+\.')


def to_py(value):
    """A Lua table as a dict, recursively."""
    if lupa.lua_type(value) == 'table':
        return {to_py(k): to_py(v) for k, v in value.items()}
    if isinstance(value, float) and value == int(value):
        return int(value)
    return value


def load_saved(path):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(path.read_bytes())
    return to_py(lua.globals().PuggerWaylaidCompanionDB) or {}


def load_shares(paths):
    """[(label, db)] for every shared string in the files, with the keys the saved
    settings use (npcs, writNpc, anySide, rewards)."""
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    ns = lua.table(TITLE='Pugger Waylaid Companion')
    chunk = lua.eval('function(src) return assert(loadstring(src, "Share.lua")) end')(
        (ADDON / 'Share.lua').read_bytes())
    chunk('PuggerWaylaidCompanion', ns)
    out = []
    for path in paths:
        found = SHARE_STRING.findall(path.read_text(encoding='utf-8', errors='replace'))
        if not found:
            print('%s: no shared string found' % path.name)
        for n, text in enumerate(found, 1):
            label = path.name + ('' if len(found) == 1 else ' #%d' % n)
            # Lua returns the data alone, or nil and why.
            result = ns.ShareDecode(text)
            data, why = result if isinstance(result, tuple) else (result, None)
            if data is None:
                print('%s: skipped, %s' % (label, why))
                continue
            data = to_py(data)
            out.append((label, {'npcs': data['npcs'], 'writNpc': data['writs'],
                                'anySide': data['anySide'], 'rewards': data['rewards']}))
    return out


def load_shipped():
    """(shipped NPC ids, writ quest -> shipped NPC id or None, quest -> name, recorded)."""
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    ns = lua.table()
    files = ['Data/Writs.lua'] + (['Data/Recorded.lua'] if OUT.exists() else [])
    for name in files:
        chunk = lua.eval('function(src, name) return assert(loadstring(src, name)) end')(
            (ADDON / name).read_bytes(), name)
        chunk('PuggerWaylaidCompanion', ns)
    writs = {}
    names = {}
    sides = {}
    for row in to_py(ns.WRITS).values():
        writs[row[1]] = row.get(8)
        names[row[1]] = row[10]
        sides[row[1]] = row.get(9)
    recorded = {
        'sides': sides,
        'anySide': to_py(ns.RECORDED_ANYSIDE) if ns.RECORDED_ANYSIDE else {},
        'npcs': to_py(ns.RECORDED_NPCS) if ns.RECORDED_NPCS else {},
        'writs': to_py(ns.RECORDED_WRITS) if ns.RECORDED_WRITS else {},
        'rewards': to_py(ns.RECORDED_REWARDS) if ns.RECORDED_REWARDS else {},
    }
    return set(to_py(ns.WRIT_NPCS)), writs, names, recorded


def place(table):
    """{1: name, 2: map, ...} -> [name, map, x, y, zone]."""
    return [table[i] for i in range(1, 6)]


def lua_string(text):
    out = []
    for ch in str(text):
        if ch in '\\"':
            out.append('\\' + ch)
        elif ord(ch) < 32 or ord(ch) == 127:
            out.append('\\%03d' % ord(ch))
        else:
            out.append(ch)
    return '"' + ''.join(out) + '"'


def lua_key(key):
    return '[%d]' % key if isinstance(key, int) else '[%s]' % lua_string(key)


def lua_value(value):
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, (int, float)):
        return repr(value)
    return lua_string(value)


def ordered(table):
    """A Lua array (a dict keyed 1..n, or a list) as a list."""
    if isinstance(table, list):
        return table
    return [table[i] for i in sorted(table) if isinstance(i, int)]


def lua_item(item):
    costs = ', '.join('{ value = %d, name = %s%s }' % (
        c['value'], lua_string(c['name']), ', icon = %s' % lua_value(c['icon']) if c.get('icon') else '')
        for c in ordered(item.get('costs') or {}))
    fields = ['id = %d' % item['id']]
    if item.get('name'):
        fields.append('name = %s' % lua_string(item['name']))
    fields += ['price = %d' % (item.get('price') or 0), 'quantity = %d' % (item.get('quantity') or 1)]
    if item.get('standing'):
        fields.append('standing = %d' % item['standing'])
    fields.append('costs = { %s }' % costs if costs else 'costs = {}')
    return '{ %s }' % ', '.join(fields)


def items(shop):
    """A shop's items as a list, whether they came as a Lua array (a dict keyed 1..n)
    or a list."""
    found = shop.get('items') or []
    if isinstance(found, dict):
        found = [found[k] for k in sorted(found)]
    return [i for i in found if isinstance(i, dict)]


def merge_rewards(kept, shops):
    """Fold a source's { npc: shop } into kept, the newest list of each quartermaster
    winning. Returns how many it added or replaced."""
    changed = 0
    shops = shops or {}
    if 'items' in shops:  # before 0.5.1 a faction held a single shop
        shops = {shops.get('npc') or '?': shops}
    for npc, shop in shops.items():
        if not shop.get('items'):
            continue
        old = kept.get(npc)
        if old is None or (shop.get('time') or 0) > (old.get('time') or 0):
            if old is not None:
                # A tooltip still loading has no requirement line; the addon then keeps
                # what an earlier visit saw (Rewards.lua), and so does this.
                seen = {i.get('id'): i.get('standing') for i in items(old)}
                for item in items(shop):
                    if item.get('standing') is None and seen.get(item.get('id')) is not None:
                        item['standing'] = seen[item.get('id')]
            kept[npc] = shop
            changed += 1
    # A list kept by name (before 0.5.1) that is also there by NPC id.
    by_id = {s.get('npc') for k, s in kept.items() if isinstance(k, int)}
    for npc in [k for k, s in kept.items() if isinstance(k, str) and s.get('npc') in by_id]:
        del kept[npc]
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--wow', default='C:/Program Files (x86)/World of Warcraft')
    parser.add_argument('--dry-run', action='store_true', help='report, write nothing')
    parser.add_argument('--no-saved', action='store_true', help="leave out this computer's saved data")
    parser.add_argument('shares', nargs='*', type=Path,
                        help='files holding shared strings (default: every .txt in shares/)')
    args = parser.parse_args()

    shipped_npcs, writs, names, recorded = load_shipped()
    npcs = {k: place(v) for k, v in recorded['npcs'].items()}
    where = dict(recorded['writs'])
    any_side = {q for q, yes in recorded['anySide'].items() if yes is True}
    rewards = {f: dict(shops) for f, shops in recorded['rewards'].items()}
    before = (len(where), sum(isinstance(v, int) for v in where.values()))

    sources = []
    if not args.no_saved:
        saved = sorted((Path(args.wow) / '_forever_' / 'WTF' / 'Account').glob(
            '*/SavedVariables/PuggerWaylaidCompanion.lua'))
        if not saved:
            sys.exit('No PuggerWaylaidCompanion.lua found under ' + args.wow + ' (use --no-saved to skip)')
        sources += [(path.parts[-3], load_saved(path)) for path in saved]
    sources += load_shares(args.shares or sorted(SHARES.glob('*.txt')))

    for label, db in sources:
        account_npcs = {k: place(v) for k, v in (db.get('npcs') or {}).items()}
        account_writs = db.get('writNpc') or {}
        changed = 0
        for faction, shops in (db.get('rewards') or {}).items():
            changed += merge_rewards(rewards.setdefault(faction, {}), shops)
        print('%s: %d writs, %d places, %d quartermaster lists newer' % (
            label, len(account_writs), len(account_npcs), changed))
        for quest, at in account_writs.items():
            if quest not in writs:
                print('  ! quest %s is not a known writ, skipped' % quest)
                continue
            if writs[quest] is not None:
                continue  # Data/Writs.lua already has its NPC
            if at not in account_npcs and at not in shipped_npcs and at not in npcs:
                print('  ! quest %s points at %s, which has no place, skipped' % (quest, at))
                continue
            old = where.get(quest)
            # An NPC beats an unnamed spot, and a spot is replaced by the saved one: the
            # addon corrects a spot filed under the wrong zone, which gives it a new key.
            # A named NPC stays.
            if old is None or not isinstance(old, int):
                if old is not None and old != at and not isinstance(at, int):
                    print('  quest %s (%s): %s moved to %s' % (quest, names[quest], old, at))
                where[quest] = at
            elif old != at:
                print('  ! quest %s (%s): keeping %s, saved data says %s' % (quest, names[quest], old, at))
            # The saved place wins over the recorded one for the same reason.
            if where[quest] == at and at in account_npcs and at not in shipped_npcs:
                npcs[at] = account_npcs[at]
        for quest, yes in (db.get('anySide') or {}).items():
            if yes is True and recorded['sides'].get(quest):
                any_side.add(quest)

    used = set(where.values())
    npcs = {k: v for k, v in npcs.items() if k in used}
    named = sum(isinstance(v, int) for v in where.values())
    total = len(writs)
    known = sum(1 for q, npc in writs.items() if npc is not None or q in where)

    def order(key):
        return (isinstance(key, str), key)

    lines = [
        "-- Recorded in game by Pugger Waylaid Companion and written here by",
        "-- scripts/bake_waylaid.py. Do not edit by hand: run the script again instead.",
        "local _, ns = ...",
        "",
        "-- Places writs are handed in that Data/Writs.lua does not have:",
        "-- [NPC id, or \"at:map:x:y\" for a spot nobody has named yet] = { name, uiMapID, x, y, zone }",
        "ns.RECORDED_NPCS = {",
    ]
    for key in sorted(npcs, key=order):
        name, map_id, x, y, zone = npcs[key]
        lines.append('  %s = { %s, %d, %s, %s, %s },' % (
            lua_key(key), lua_string(name), map_id, x, y, lua_string(zone)))
    lines += ["}", "", "-- [writ quest] = place", "ns.RECORDED_WRITS = {"]
    for quest in sorted(where):
        lines.append('  [%d] = %s, -- %s' % (
            quest, where[quest] if isinstance(where[quest], int) else lua_string(where[quest]), names[quest]))
    lines += ["}", "",
              "-- Writs Data/Writs.lua limits to one side that players have had on the other:",
              "ns.RECORDED_ANYSIDE = {"]
    for quest in sorted(any_side):
        lines.append('  [%d] = true, -- %s' % (quest, names.get(quest, '?')))
    lines += ["}", "",
              "-- What each quartermaster sells, as Rewards.lua keeps it:",
              "-- [faction] = { [NPC id] = { npc, time, items = { { id, name, price, quantity, standing, costs } } } }",
              "ns.RECORDED_REWARDS = {"]
    for faction in sorted(rewards):
        if not rewards[faction]:
            continue
        lines.append('  [%s] = {' % lua_string(faction))
        for npc in sorted(rewards[faction], key=order):
            shop = rewards[faction][npc]
            lines.append('    %s = { npc = %s, time = %d, items = {' % (
                lua_key(npc), lua_string(shop.get('npc') or '?'), shop.get('time') or 0))
            for item in ordered(shop['items']):
                lines.append('      %s,' % lua_item(item))
            lines.append('    } },')
        lines.append('  },')
    lines += ["}", ""]

    print('Recorded writs: %d (was %d), %d with a named NPC (was %d).' % (len(where), before[0], named, before[1]))
    print('Turn-in known for %d of %d writs.' % (known, total))
    print('Writs for both sides: %s.' % (', '.join(names.get(q, str(q)) for q in sorted(any_side)) or 'none'))
    print('Quartermaster lists: %s.' % (
        ', '.join('%s %d' % (f, len(s)) for f, s in sorted(rewards.items()) if s) or 'none'))
    if args.dry_run:
        print('Dry run: nothing written.')
        return
    OUT.write_text('\n'.join(lines), encoding='utf-8', newline='\n')
    print('Wrote ' + str(OUT.relative_to(ROOT)))


if __name__ == '__main__':
    main()
