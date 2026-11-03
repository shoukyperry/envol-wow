"""Write Envol's Lua data files from rxp.json and ps.json."""
import json, os, re
import os
WORK = os.environ.get("ENVOL_WORK", "work")
PS_DIR = os.environ.get("ENVOL_PS", "upstream/polestar")
RXP_DIR = os.environ.get("ENVOL_RXP", "upstream/RXPGuides")
ADDON = os.environ.get("ENVOL_ADDON", "addon/Envol")
os.makedirs(WORK, exist_ok=True)

OUT = os.path.join(ADDON, "Data") + "/"
os.makedirs(OUT, exist_ok=True)
rxp = json.load(open(os.path.join(WORK, "rxp.json")))
ps = json.load(open(os.path.join(WORK, "ps.json")))
nfr = json.load(open(os.path.join(WORK, "polestar_names_fr.json")))

IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
RESERVED = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local",
            "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"}


def lstr(s):
    s = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "")
    return '"' + s + '"'


def ser(v):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        r = ("%.3f" % v).rstrip("0").rstrip(".")
        return r if r not in ("", "-") else "0"
    if isinstance(v, str):
        return lstr(v)
    if isinstance(v, list):
        return "{" + ",".join(ser(x) for x in v) + "}"
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            if x is None:
                continue
            if isinstance(k, str) and IDENT.match(k) and k not in RESERVED:
                parts.append(k + "=" + ser(x))
            else:
                parts.append("[" + ser(k) + "]=" + ser(x))
        return "{" + ",".join(parts) + "}"
    raise TypeError(type(v))


def write_guides(path, guides, header):
    with open(path, "w", encoding="utf-8") as f:
        f.write(header)
        f.write("local A = EnvolData.Add\n")
        for g in guides:
            meta = {k: g.get(k) for k in ("src", "id", "name", "faction", "cond", "min", "max", "races",
                                          "next", "nextid", "defaultfor")}
            meta = {k: v for k, v in meta.items() if v not in (None, [], "")}
            f.write("A(" + ser(meta) + ",function() return " + ser(g["steps"]) + " end)\n")


H_RXP = ("-- Envol : routes RestedXP publiques pour WoW Forever (traduction française),\n"
         "-- adaptées depuis github.com/RestedXP/RXPGuides — licence CC BY-NC-SA 4.0.\n"
         "-- RestedXP n'a ni produit ni approuvé cette adaptation. Usage personnel, non commercial.\n")
H_PS = ("-- Envol : routes Polestar Guides pour WoW Forever (textes français),\n"
        "-- adaptées depuis github.com/fitzforge/polestar — licence GPLv3 (données : voir LICENCES.txt).\n")

for g in rxp:
    g["id"] = "rxp:" + g["name"]
write_guides(OUT + "RXP.lua", rxp, H_RXP)
write_guides(OUT + "Polestar_Alliance.lua", [g for g in ps if g["faction"] == "Alliance"], H_PS)
write_guides(OUT + "Polestar_Horde.lua", [g for g in ps if g["faction"] == "Horde"], H_PS)

# French quest names for every quest the routes touch (fallback when a line has no text)
qids = set()
for g in rxp + ps:
    for s in g["steps"]:
        for go in s["g"]:
            if go.get("q"):
                qids.add(go["q"])
        for sk in s.get("sk", []) + s.get("skc", []):
            pass
qn = {q: nfr["quest:" + str(q)] for q in sorted(qids) if "quest:" + str(q) in nfr}
with open(OUT + "Quetes.lua", "w", encoding="utf-8") as f:
    f.write("-- Noms français des quêtes utilisées par les routes (source : Polestar, noms du client).\n")
    f.write("EnvolData.questNames = " + ser(qn) + "\n")
for fn in sorted(os.listdir(OUT)):
    print(fn, os.path.getsize(OUT + fn) // 1024, "KB")
print(len(qids), "quests,", len(qn), "named")
