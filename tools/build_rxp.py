"""Convert the RestedXP public Forever guides (French, CC BY-NC-SA 4.0) to Envol data."""
import json, re, os, sys
import os
WORK = os.environ.get("ENVOL_WORK", "work")
PS_DIR = os.environ.get("ENVOL_PS", "upstream/polestar")
RXP_DIR = os.environ.get("ENVOL_RXP", "upstream/RXPGuides")
ADDON = os.environ.get("ENVOL_ADDON", "addon/Envol")
os.makedirs(WORK, exist_ok=True)
from collections import Counter

SRC = os.path.join(RXP_DIR, "lang/Guides-frFR/forever") + "/"
FILES = ["RestedXP-Skyborne.lua", "Alliance-1-10_NightElf.lua", "Alliance-1-13_Human.lua",
         "Alliance-1-14_DwarfGnome.lua", "Alliance-11-20.lua", "Horde-01-12_Durotar.lua",
         "Horde-01-14_Undead.lua", "Horde-1-12_Mulgore.lua", "Horde-12-22_Barrens.lua"]

MAPID = {"Durotar": 1411, "Mulgore": 1412, "The Barrens": 1413, "Alterac Mountains": 1416,
         "Arathi Highlands": 1417, "Badlands": 1418, "Blasted Lands": 1419, "Tirisfal Glades": 1420,
         "Silverpine Forest": 1421, "Western Plaguelands": 1422, "Eastern Plaguelands": 1423,
         "Hillsbrad Foothills": 1424, "The Hinterlands": 1425, "Dun Morogh": 1426, "Searing Gorge": 1427,
         "Burning Steppes": 1428, "Elwynn Forest": 1429, "Deadwind Pass": 1430, "Duskwood": 1431,
         "Loch Modan": 1432, "Redridge Mountains": 1433, "Stranglethorn Vale": 1434,
         "Swamp of Sorrows": 1435, "Westfall": 1436, "Wetlands": 1437, "Teldrassil": 1438,
         "Darkshore": 1439, "Ashenvale": 1440, "Thousand Needles": 1441, "Stonetalon Mountains": 1442,
         "Desolace": 1443, "Feralas": 1444, "Dustwallow Marsh": 1445, "Tanaris": 1446, "Azshara": 1447,
         "Felwood": 1448, "Un'Goro Crater": 1449, "Moonglade": 1450, "Silithus": 1451, "Winterspring": 1452,
         "Stormwind City": 1453, "StormwindClassic": 1453, "Orgrimmar": 1454, "Ironforge": 1455,
         "Thunder Bluff": 1456, "Darnassus": 1457, "Undercity": 1458, "Kalimdor": 1414,
         "Eastern Kingdoms": 1415, "Zephras Isle": 2521}

COLORS = {"FRIENDLY": "ff00ff25", "ENEMY": "ffff5722", "LOOT": "ff00bcd4", "WARN": "fffcdc00",
          "PICK": "ffdb2eef", "BUY": "ff2ecc40"}

warn = Counter()


def clean(t):
    if t is None:
        return None
    t = re.sub(r"\|T[^|]*chatbubble[^|]*\|t", "", t, flags=re.I)
    t = re.sub(r"\|cRXP_([A-Z]+)_", lambda m: "|c" + COLORS.get(m.group(1), "ffffffff"), t)
    t = t.replace("\\n", "\n").strip()
    return t or None


def split_cond(line):
    """'text << cond' -> (text, cond)."""
    m = re.match(r"^(.*?)\s*<<\s*([!\w/ ]+?)\s*$", line)
    if m and not line.lstrip().startswith("<<"):
        return m.group(1), m.group(2).strip()
    return line, None


def num(s):
    try:
        f = float(s)
        return int(f) if f == int(f) and "." not in s else f
    except (TypeError, ValueError):
        return None


def parse_goto(args):
    """Returns (pos, radius, flag) or None."""
    if not args:
        return None
    zone = args[0].strip()
    nums = [num(a.strip()) for a in args[1:]]
    if len(nums) < 2 or nums[0] is None or nums[1] is None:
        return None
    radius = nums[2] if len(nums) > 2 else None
    flag = args[4].strip() if len(args) > 4 else None
    m = re.match(r"^(\d+)/(\d+)$", zone)
    if m:
        pos = ["w", int(m.group(2)), nums[0], nums[1]]  # world: instance, a (left-right), b (top-bottom)
    else:
        mid = MAPID.get(zone) or (int(zone) if zone.isdigit() else None)
        if not mid:
            warn["zone:" + zone] += 1
            return None
        pos = ["m", mid, nums[0], nums[1]]
    return pos, radius, flag


def ids(s):
    return [int(x) for x in re.findall(r"\d+", s or "")]


def parse_xp(s):
    s = s.replace(" ", "")
    m = re.match(r"(<?)(\d+)([+.\-]?\d*)", s)
    if not m:
        return None
    lvl = int(m.group(2)); extra = m.group(3)
    xp = 0
    if extra:
        xp = float("0" + extra) if extra.startswith(".") else int(extra)
    return m.group(1) == "<", lvl, xp


def parse_guide(text, file_faction):
    g = {"src": "rxp", "next": [], "steps": []}
    step = None
    drop = False
    lines = text.split("\n")
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("--"):
            continue
        if line == "step" or line.startswith("step ") or line.startswith("step<<"):
            if step is not None and not drop:
                g["steps"].append(step)
            step = {"g": []}
            drop = False
            _, c = split_cond(line)
            if c:
                step["c"] = c
            continue
        if step is None:  # header
            if line.startswith("<<"):
                g["cond"] = line[2:].strip()
            elif line.startswith("#name "):
                g["name"] = line[6:].strip()
            elif line.startswith("#displayname "):
                g["display"] = line[13:].strip()
            elif line.startswith("#next "):
                body, c = split_cond(line[6:])
                g["next"].append([[n.strip() for n in body.split(";") if n.strip()], c])
            elif line.startswith("#defaultfor "):
                g["defaultfor"] = line[12:].strip()
            elif line.startswith("#group "):
                body, c = split_cond(line[7:])
                g.setdefault("groups", []).append(body.strip())
            continue
        # inside a step
        if line.startswith("#"):
            body, c = split_cond(line)
            parts = body[1:].split(None, 1)
            key = parts[0].lower(); val = parts[1].strip() if len(parts) > 1 else ""
            if key == "completewith":
                step["cw"] = val
            elif key == "optional":
                step["opt"] = 1
            elif key == "label":
                step["lbl"] = val
            elif key == "loop":
                step["loop"] = 1
            elif key == "requires":
                step["req"] = val
            elif key in ("hardcore", "ssf", "hidewindow"):
                drop = True
            elif key == "season":
                if "2" in val and "0" not in val and "1" not in val:
                    drop = True
            elif key == "xprate":
                m = re.match(r"([<>])\s*([\d.]+)", val)
                if m:
                    ok = (1.0 < float(m.group(2))) if m.group(1) == "<" else (1.0 > float(m.group(2)))
                    if not ok:
                        drop = True
            elif key == "level":
                step.setdefault("sk", []).append(["minlvl", int(val)])
            elif key == "ah":
                step["opt"] = 1
            continue
        line, cond = split_cond(line)
        if line.startswith(">>"):
            t = clean(line[2:])
            if t:
                step.setdefault("t", []).append(t if not cond else [t, cond])
            continue
        if line.startswith("+"):
            goal = {"k": "m", "x": clean(line[1:])}
            if cond:
                goal["c"] = cond
            step["g"].append(goal)
            continue
        if not line.startswith("."):
            t = clean(line)
            if t:
                step.setdefault("t", []).append(t)
            continue
        m = re.match(r"^\.(\w+)\s*(.*)$", line)
        cmd, rest = m.group(1), m.group(2)
        text = None
        if ">>" in rest:
            rest, text = rest.split(">>", 1)
            text = clean(text)
        comment = None
        if "--" in rest:
            rest, comment = rest.split("--", 1)
            comment = comment.strip()
        args = [a.strip() for a in rest.split(",")] if rest.strip() else []
        goal = None
        sk = None
        if cmd == "goto" or cmd == "waypoint":
            r = parse_goto(args)
            if r:
                pos, radius, flag = r
                goal = {"k": "g", "p": pos}
                if radius is not None:
                    goal["r"] = radius
                if flag is not None or cmd == "waypoint":
                    goal["op"] = 1  # optional waypoint: never blocks
        elif cmd == "accept":
            goal = {"k": "a", "q": int(args[0])}
        elif cmd == "turnin":
            goal = {"k": "t", "q": int(args[0])}
        elif cmd == "complete":
            goal = {"k": "c", "q": int(args[0])}
            if len(args) > 1 and args[1].isdigit():
                goal["o"] = int(args[1])
            if comment and not text:
                goal["cm"] = comment
        elif cmd == "collect":
            goal = {"k": "col", "i": int(args[0]), "n": int(args[1]) if len(args) > 1 and args[1].isdigit() else 1}
            if len(args) > 2 and args[2].isdigit():
                goal["q"] = int(args[2])
                if len(args) > 3 and args[3].isdigit():
                    goal["o"] = int(args[3])
            if comment and not text:
                goal["cm"] = comment
        elif cmd == "xp":
            p = parse_xp(args[0]) if args else None
            if p:
                rev, lvl, xp = p
                skipstep = num(args[1]) if len(args) > 1 else None
                if skipstep is not None:
                    sk = ["xp", lvl, xp, 1 if (rev or skipstep < 0) else 0]
                else:
                    goal = {"k": "lv", "l": lvl, "xp": xp}
                    if rev:
                        goal = None
                        sk = ["xp", lvl, xp, 1]
        elif cmd == "train":
            if args and args[0].isdigit():
                goal = {"k": "tr", "s": int(args[0])}
        elif cmd in ("vendor", "trainer", "fp", "fly", "hs", "home", "deathskip", "bindlocation"):
            kk = {"vendor": "v", "trainer": "tn", "fp": "fp", "fly": "fly", "hs": "hs", "home": "home",
                  "deathskip": "die", "bindlocation": "home"}[cmd]
            if cmd == "bindlocation":
                sk = None
                goal = None
            else:
                goal = {"k": kk}
                if not text and args:
                    goal["cm"] = ", ".join(args)
        elif cmd == "abandon":
            goal = {"k": "ab", "q": int(args[0])}
        elif cmd in ("use", "cast", "usespell", "destroy", "equip", "bankdeposit", "unitscan"):
            if text:
                goal = {"k": "m", "x": text, "info": 1}
                text = None
        elif cmd == "isOnQuest":
            sk = ["onq", ids(rest)]
        elif cmd == "isNotOnQuest":
            sk = ["notonq", ids(rest)]
        elif cmd == "isQuestComplete":
            sk = ["qc", ids(rest)]
        elif cmd == "isQuestNotComplete":
            sk = ["qnc", ids(rest)]
        elif cmd == "isQuestTurnedIn":
            sk = ["ti", ids(rest)]
        elif cmd == "isQuestAvailable":
            sk = ["avail", ids(rest)]
        elif cmd == "money":
            mm = re.match(r"([<>])\s*([\d.]+)", rest.strip())
            if mm:
                sk = ["money", mm.group(1), int(round(float(mm.group(2)) * 10000))]
        elif cmd == "itemcount":
            if len(args) >= 2:
                mm = re.match(r"([<>]?)(=?)\s*(\d+)", args[1])
                if mm:
                    sk = ["ic", ids(args[0]), mm.group(1) or ">=", int(mm.group(3)), mm.group(2) == "="]
        elif cmd == "zoneskip":
            zs = []
            for z in re.split(r"[+/]", args[0] if args else ""):
                z = z.strip()
                mid = MAPID.get(z) or (int(z) if z.isdigit() else None)
                if mid:
                    zs.append(mid)
                else:
                    warn["zoneskip:" + z] += 1
            if zs:
                sk = ["zone", zs, 1 if len(args) > 1 and (num(args[1]) or 0) & 1 else 0]
        elif cmd == "subzoneskip":
            if args and args[0].isdigit():
                sk = ["sub", int(args[0]), 1 if len(args) > 1 and (num(args[1]) or 0) & 1 else 0]
        elif cmd in ("target", "mob", "itemStat", "skill", "skipgossipid", "cooldown", "disablecheckbox", "pin",
                     "link", "macro", "timer", "aura", "line", "dungeon", "group", "skipgossip", "gossipoption",
                     "maxlevel", "zone", "subzone", "showwhiledead", "solo", "clicknext", "addquestitem",
                     "bronzetube"):
            if cmd == "target" and args:
                step.setdefault("tg", []).append(rest.strip())
            elif cmd == "mob" and args:
                step.setdefault("mob", []).append(rest.strip().lstrip("+"))
            if text and cmd not in ("itemStat", "skill"):
                step.setdefault("t", []).append(text)
            text = None
        else:
            warn["cmd:" + cmd] += 1
        if sk:
            if cond:
                sk.append(cond)
            step.setdefault("sk", []).append(sk) if not cond else step.setdefault("skc", []).append(sk)
        if goal:
            if text:
                goal["x"] = text
            if cond:
                goal["c"] = cond
            step["g"].append(goal)
        elif text:
            step.setdefault("t", []).append(text if not cond else [text, cond])
    if step is not None and not drop:
        g["steps"].append(step)
    return g


def main():
    guides = []
    for f in FILES:
        txt = open(SRC + f, encoding="utf-8").read()
        fac = None
        if 'if faction == "Horde" then return end' in txt:
            fac = "Alliance"
        elif 'if faction == "Alliance" then return end' in txt:
            fac = "Horde"
        for m in re.finditer(r"RegisterGuide\(\[\[(.*?)\]\]", txt, re.S):
            g = parse_guide(m.group(1), fac)
            if not any("RestedXP Guide Forever" in x for x in g.get("groups", [])):
                continue
            g["faction"] = fac
            g["file"] = f
            r = re.match(r"(\d+)-(\d+)", g["name"])
            g["min"], g["max"] = (int(r.group(1)), int(r.group(2))) if r else (1, 60)
            del g["groups"]
            guides.append(g)
    names = {g["name"] for g in guides}
    for g in guides:
        for alts, c in g["next"]:
            for n in alts:
                if n not in names and not n.startswith("RestedXP"):
                    warn["next-missing:" + n] += 1
    json.dump(guides, open(os.path.join(WORK, "rxp.json"), "w"), ensure_ascii=False)
    print(len(guides), "guides,", sum(len(g["steps"]) for g in guides), "steps")
    for g in guides:
        print(" ", g["faction"], "|", g["name"], "|", g.get("cond"), "| next:", g["next"], "| def:", g.get("defaultfor"))
    print("warnings:", warn.most_common(40))


main()
