import json, re, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import os
WORK = os.environ.get("ENVOL_WORK", "work")
PS_DIR = os.environ.get("ENVOL_PS", "upstream/polestar")
RXP_DIR = os.environ.get("ENVOL_RXP", "upstream/RXPGuides")
ADDON = os.environ.get("ENVOL_ADDON", "addon/Envol")
os.makedirs(WORK, exist_ok=True)

from luadata import tables_after, P

base = os.path.join(PS_DIR, "addon") + "/"
guides = []
def resolve(o, locs):
    if isinstance(o, dict):
        if "__ref" in o:
            return locs.get(o["__ref"], [])[o["idx"] - 1]
        return {k: resolve(v, locs) for k, v in o.items()}
    if isinstance(o, list):
        return [resolve(v, locs) for v in o]
    return o

for f in ["Polestar_Guides_Horde/Guides.lua", "Polestar_Guides_Alliance/Guides.lua", "Polestar_Guides/Guides.lua"]:
    txt = open(base + f, encoding="utf-8").read()
    # each guide sits in its own "do ... end" block, with optional local lists before it
    blocks = re.split(r"\n-- Source: ", txt)
    for b in blocks:
        locs = {}
        for m in re.finditer(r"local (\w+) = \{", b):
            p = P(b, m.end() - 1)
            locs[m.group(1)] = p.table()
        for g in tables_after(b, "Polestar.RegisterGuide("):
            guides.append(resolve(g, locs))
lev = [g for g in guides if g.get("category", "Leveling") == "Leveling"]
json.dump(lev, open(os.path.join(WORK, "polestar_leveling.json"), "w"), ensure_ascii=False)

# French per-guide texts: t.guides["id"] = (function() return { ... } end)()
txt = open(base + "Polestar_frFR/Texts.lua", encoding="utf-8").read()
fr = {}
for m in re.finditer(r't\.guides\["([^"]+)"\]\s*=\s*\(function\(\)\s*return', txt):
    p = P(txt, m.end()); p.ws()
    fr[m.group(1)] = p.table()
pk = next(tables_after(txt, "t.pack ="), {})
fr["__pack"] = pk
json.dump(fr, open(os.path.join(WORK, "polestar_texts_fr.json"), "w"), ensure_ascii=False)

# French names: R("kind", lo, hi, [[ id\tname lines ]])
ntxt = open(base + "Polestar_frFR/Names.lua", encoding="utf-8").read()
names = {}
for m in re.finditer(r'R\("(\w+)",\s*\d+,\s*\d+,\s*\[(=*)\[(.*?)\]\2\]\)', ntxt, re.S):
    kind = m.group(1)
    for line in m.group(3).split("\n"):
        if "\t" in line:
            i, n = line.split("\t", 1)
            n = re.sub(r"%([0-9A-Fa-f]{2})", lambda x: chr(int(x.group(1), 16)), n)
            names[kind + ":" + i.strip()] = n
json.dump(names, open(os.path.join(WORK, "polestar_names_fr.json"), "w"), ensure_ascii=False)
print(len(guides), "guides,", len(lev), "leveling,", len(fr), "fr text sets,", len(names), "fr names")
from collections import Counter
print(Counter(g.get("faction") for g in lev))
gt = Counter(); sk = Counter(); gk = Counter(); wk = Counter()
for g in lev:
    for st in g["steps"]:
        sk.update(st.keys())
        for w in st.get("when", []) or []:
            wk[w.get("k")] += 1
        for go in st.get("goals", []):
            gt[go["t"]] += 1
            gk.update(go.keys())
print("goal types", gt.most_common())
print("step keys", sk.most_common())
print("when kinds", wk.most_common())
print("goal keys", gk.most_common())
