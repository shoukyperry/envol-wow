"""Builds de talents pour Forever (Polestar, GPLv3 ; choix des talents d'après ForeverDB, notes Polestar en français).

Écrit addon/Envol/Data/Talents.lua :
  EnvolData.talents[CLASSE] = { tree = id de l'arbre C_Traits, nodes = { [noeud] = { entrée, rangs max, sort, colonne de spé, nom } },
                                builds = { { key, spec, nom, split, picks = { {noeud, rang}, ... }, notes = { [niveau] = texte } } } }
"""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from luadata import P
from luadata import ser

PS_DIR = os.environ.get("ENVOL_PS", "upstream/polestar")
ADDON = os.environ.get("ENVOL_ADDON", "addon/Envol")

base = os.path.join(PS_DIR, "addon", "Polestar")
src = open(os.path.join(base, "Talents", "Builds.lua"), encoding="utf-8").read()

# traductions françaises des notes (Locales/frFR.lua : L["anglais"] = "français")
fr = {}
for m in re.finditer(r'^L\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"', open(os.path.join(base, "Locales", "frFR.lua"), encoding="utf-8").read(), re.M):
    fr[m.group(1)] = m.group(2).replace('\\"', '"')

# L["..."] -> chaîne française (ou anglaise à défaut), pour lire le fichier comme des données
src = re.sub(r'L\["((?:[^"\\]|\\.)*)"\]', lambda m: json.dumps(fr.get(m.group(1), m.group(1).replace('\\"', '"')), ensure_ascii=False), src)

SPEC_FR = {"balance": "Équilibre", "feral": "Combat farouche", "restoration": "Restauration", "beastmastery": "Maîtrise des bêtes",
           "marksmanship": "Précision", "survival": "Survie", "arcane": "Arcanes", "fire": "Feu", "frost": "Givre", "holy": "Sacré",
           "protection": "Protection", "retribution": "Vindicte", "discipline": "Discipline", "shadow": "Ombre",
           "assassination": "Assassinat", "combat": "Combat", "subtlety": "Finesse", "elemental": "Élémentaire",
           "enhancement": "Amélioration", "affliction": "Affliction", "demonology": "Démonologie", "destruction": "Destruction",
           "arms": "Armes", "fury": "Fureur"}

data = {}
pos = 0
while True:
    i = src.find("T.Register(", pos)
    if i < 0:
        break
    p = P(src, i + len("T.Register("))
    p.ws()
    t = p.table()
    pos = p.i
    cls = t["class"]
    nodes = {int(k): [v[0], v[1], v[2], v[3], v[6]] for k, v in t["nodes"].items()}
    builds = []
    for b in t["builds"]:
        builds.append({"key": b["key"], "spec": b["spec"], "nom": SPEC_FR.get(b["key"], b["key"]), "split": b["split"],
                       "picks": b["picks"], "notes": {int(k): v for k, v in (b.get("notes") or {}).items()}})
    data[cls] = {"tree": t["tree"], "nodes": nodes, "builds": builds}

chemin = os.path.join(ADDON, "Data", "Talents.lua")
with open(chemin, "w", encoding="utf-8") as f:
    f.write("-- Builds de talents pour WoW Forever : Polestar Guides (GPLv3), choix d'après ForeverDB, notes en français.\n")
    f.write("EnvolData.talents = " + ser(data) + "\n")
print("talents :", sum(len(v["builds"]) for v in data.values()), "builds,", os.path.getsize(chemin) // 1024, "Ko")
