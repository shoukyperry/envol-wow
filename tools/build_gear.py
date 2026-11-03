"""Extrait les poids de stats de leveling de Polestar (GPLv3 ; part wowsims : MIT) vers Data/Equipement.lua."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from luadata import tables_after, ser

PS_DIR = os.environ.get("ENVOL_PS", "upstream/polestar")
ADDON = os.environ.get("ENVOL_ADDON", "addon/Envol")
gear = os.path.join(PS_DIR, "addon/Polestar/Gear")

bands = next(tables_after(open(os.path.join(gear, "SpecData.lua"), encoding="utf-8").read(), "Gear.WEIGHT_BANDS ="))
classes = next(tables_after(open(os.path.join(gear, "Weights.lua"), encoding="utf-8").read(), "Gear.CLASSES ="))

FR = {"arms": "Armes", "fury": "Fureur", "protection": "Protection", "holy": "Sacré", "retribution": "Vindicte",
      "beastmastery": "Maîtrise des bêtes", "marksmanship": "Précision", "survival": "Survie",
      "assassination": "Assassinat", "combat": "Combat", "subtlety": "Finesse", "discipline": "Discipline",
      "shadow": "Ombre", "elemental": "Élémentaire", "enhancement": "Amélioration", "restoration": "Restauration",
      "arcane": "Arcanes", "fire": "Feu", "frost": "Givre", "affliction": "Affliction", "demonology": "Démonologie",
      "destruction": "Destruction", "balance": "Équilibre", "feral": "Combat farouche"}

out = {"classes": {}, "bands": {}}
for cls, c in classes.items():
    specs = []
    for s in c["specs"]:
        specs.append({"key": s["key"], "fr": FR.get(s["key"], s["label"]), "names": s.get("names", [])})
    out["classes"][cls] = {"default": c["default"], "specs": specs}
for cls, specs in bands.items():
    out["bands"][cls] = {}
    for key, lst in specs.items():
        out["bands"][cls][key] = [{"upTo": b["upTo"], "w": b["weights"]} for b in lst]

# compétences d'armes et d'armures (classe -> armure max, bouclier, relique, armes)
# armures : 1 tissu, 2 cuir, 3 mailles, 4 plaques ; armes : sous-classes d'objet du client
def s(*a): return {str(x): True for x in a}
out["prof"] = {
    "WARRIOR": {"armor": 3, "armor40": 4, "shield": True, "dw": 20, "weapons": s(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18)},
    "PALADIN": {"armor": 3, "armor40": 4, "shield": True, "relic": 7, "weapons": s(0, 1, 4, 5, 6, 7, 8)},
    "HUNTER": {"armor": 2, "armor40": 3, "dw": 20, "weapons": s(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18)},
    "ROGUE": {"armor": 2, "dw": 10, "weapons": s(2, 3, 4, 7, 13, 15, 16, 18)},
    "PRIEST": {"armor": 1, "weapons": s(4, 10, 15, 19)},
    "SHAMAN": {"armor": 2, "armor40": 3, "shield": True, "relic": 9, "weapons": s(0, 1, 4, 5, 10, 13, 15)},
    "MAGE": {"armor": 1, "weapons": s(7, 10, 15, 19)},
    "WARLOCK": {"armor": 1, "weapons": s(7, 10, 15, 19)},
    "DRUID": {"armor": 2, "relic": 8, "weapons": s(4, 5, 10, 13, 15)},
}
path = os.path.join(ADDON, "Data", "Equipement.lua")
with open(path, "w", encoding="utf-8") as f:
    f.write("-- Poids de stats pour le leveling, par classe, spécialisation et tranche de niveau.\n")
    f.write("-- Source : Polestar Guides (GPLv3), dont une part issue des simulations wowsims (MIT).\n")
    f.write("EnvolData.gear = " + ser(out) + "\n")
print("équipement :", sum(len(v) for v in out["bands"].values()), "spécialisations ->", path)
