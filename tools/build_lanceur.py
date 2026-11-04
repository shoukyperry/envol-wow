"""Données du lanceur Windows (onglets Parcours et Équipement), écrites dans addon/Envol/Lanceur/.

Le jeu ignore ce dossier (aucun .lua) ; il voyage avec l'addon, donc chaque mise à jour l'actualise.
  index.json        races, classes, parcours complets 1 -> 60 par race et classe, liste des routes
  routes/<n>.json   étapes d'une route (textes français, conditions de classe/race)
  equipement.json   objets de leveling (stats Forever, provenance) et classements par spé / niveau / emplacement
Sources : routes RestedXP (CC BY-NC-SA) et Polestar (GPLv3) ; objets ForeverLevelingBiS (MIT) via Polestar.
"""
import json, os, re, sys, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from luadata import tables_after

WORK = os.environ.get("ENVOL_WORK", "work")
PS_DIR = os.environ.get("ENVOL_PS", "upstream/polestar")
ADDON = os.environ.get("ENVOL_ADDON", "addon/Envol")
OUT = os.path.join(ADDON, "Lanceur")
if os.path.isdir(OUT):
    shutil.rmtree(OUT)
os.makedirs(os.path.join(OUT, "routes"))

rxp = json.load(open(os.path.join(WORK, "rxp.json"), encoding="utf-8"))
ps = json.load(open(os.path.join(WORK, "ps.json"), encoding="utf-8"))
nfr = json.load(open(os.path.join(WORK, "polestar_names_fr.json"), encoding="utf-8"))
qfr = {int(k.split(":")[1]): v for k, v in nfr.items() if k.startswith("quest:")}

# --------------------------------------------------------------------- noms de lieux en français
ZONES_FR = {
    "Dun Morogh": "Dun Morogh", "Badlands": "Terres ingrates", "Blasted Lands": "Terres foudroyées",
    "Swamp of Sorrows": "Marais des Chagrins", "Duskwood": "Bois de la Pénombre", "Wetlands": "Les Paluns",
    "Elwynn Forest": "Forêt d'Elwynn", "Durotar": "Durotar", "Dustwallow Marsh": "Marécage d'Âprefange",
    "Azshara": "Azshara", "The Barrens": "Les Tarides", "Western Plaguelands": "Maleterres de l'Ouest",
    "Stranglethorn Vale": "Vallée de Strangleronce", "Alterac Mountains": "Montagnes d'Alterac",
    "Loch Modan": "Loch Modan", "Westfall": "Marche de l'Ouest", "Redridge Mountains": "Les Carmines",
    "Arathi Highlands": "Hautes-terres d'Arathi", "Burning Steppes": "Steppes ardentes",
    "The Hinterlands": "Les Hinterlands", "Searing Gorge": "Gorge des Vents brûlants",
    "Tirisfal Glades": "Clairières de Tirisfal", "Silverpine Forest": "Forêt des Pins-Argentés",
    "Eastern Plaguelands": "Maleterres de l'Est", "Teldrassil": "Teldrassil", "Darkshore": "Sombrivage",
    "Shadowfang Keep": "Donjon d'Ombrecroc", "Mulgore": "Mulgore", "Hillsbrad Foothills": "Contreforts de Hautebrande",
    "Ashenvale": "Orneval", "Feralas": "Féralas", "Felwood": "Gangrebois", "Thousand Needles": "Mille pointes",
    "Desolace": "Désolace", "Stonetalon Mountains": "Les Serres-Rocheuses", "Tanaris": "Tanaris",
    "Un'Goro Crater": "Cratère d'Un'Goro", "Razorfen Kraul": "Kraal de Tranchebauge", "Moonglade": "Reflet-de-Lune",
    "Winterspring": "Berceau-de-l'Hiver", "The Stockade": "La Prison", "Wailing Caverns": "Cavernes des Lamentations",
    "Blackfathom Deeps": "Profondeurs de Brassenoire", "Gnomeregan": "Gnomeregan", "Razorfen Downs": "Souilles de Tranchebauge",
    "Scarlet Monastery": "Monastère Écarlate", "Scarlet Monastery: Library": "Monastère Écarlate : Bibliothèque",
    "Zul'Farrak": "Zul'Farrak", "Uldaman": "Uldaman", "Silithus": "Silithus", "Sunken Temple": "Temple englouti",
    "The Temple of Atal'Hakkar": "Le temple d'Atal'Hakkar", "Undercity": "Fossoyeuse", "Stormwind City": "Hurlevent",
    "Ironforge": "Forgefer", "The Deadmines": "Les Mortemines", "Blackrock Spire": "Pic Rochenoire",
    "Blackrock Spire: Upper": "Pic Rochenoire supérieur", "Blackrock Depths": "Profondeurs de Rochenoire",
    "Orgrimmar": "Orgrimmar", "Thunder Bluff": "Les Pitons-du-Tonnerre", "Darnassus": "Darnassus",
    "Zul'Gurub": "Zul'Gurub", "Stratholme": "Stratholme", "Scholomance": "Scholomance", "Maraudon": "Maraudon",
    "Ragefire Chasm": "Gouffre de Ragefeu", "Dire Maul": "Hache-Tripes", "Alterac Valley": "Vallée d'Alterac",
    "Arathi Basin": "Bassin Arathi", "Zephras Isle": "Île de Zéphras", "City of Dalaran": "Cité de Dalaran",
    "Deadwind Pass": "Défilé de Deuillevent", "Ruins of Lordaeron": "Ruines de Lordaeron",
    "Hall of Thanes": "Salle des Thanes", "Riverglades": "Rives Claires", "Mount Hyjal": "Mont Hyjal",
}


def fr_place(m):
    en = m.group(3) or ""
    return ZONES_FR.get(en, en or "?")


def clean(t):
    """Texte prêt à afficher : sans couleurs ni icônes, lieux en français."""
    if t is None:
        return None
    t = re.sub(r"\|c[0-9a-fA-F]{8}", "", t).replace("|r", "")
    t = re.sub(r"\|T[^|]*\|t", "", t)
    t = re.sub(r"\{(\w+):(\d+)\|?([^}]*)\}", fr_place, t)
    t = re.sub(r"\s+", " ", t).strip()
    return t or None


# --------------------------------------------------------------------- conditions (copie de Core.lua)
CLASSES = ["WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"]
CLASSES_FR = {"WARRIOR": "Guerrier", "PALADIN": "Paladin", "HUNTER": "Chasseur", "ROGUE": "Voleur", "PRIEST": "Prêtre",
              "SHAMAN": "Chaman", "MAGE": "Mage", "WARLOCK": "Démoniste", "DRUID": "Druide"}
RACES = [("Human", "Humain", "Alliance"), ("Dwarf", "Nain", "Alliance"), ("NightElf", "Elfe de la nuit", "Alliance"),
         ("Gnome", "Gnome", "Alliance"), ("Skyborne", "Céleste (Alliance)", "Alliance"),
         ("Orc", "Orc", "Horde"), ("Scourge", "Mort-vivant", "Horde"), ("Tauren", "Tauren", "Horde"),
         ("Troll", "Troll", "Horde"), ("Skyborne", "Céleste (Horde)", "Horde")]


def token_ok(tok, p):
    if tok == "Undead":
        tok = "Scourge"
    if tok.isdigit():
        return p["level"] >= int(tok)
    return tok.upper() == p["class"] or tok == p["race"] or tok == p["faction"] or tok.upper() == "FOREVER"


def applies(c, p):
    if c is None:
        return True
    if isinstance(c, str):
        for alt in c.split("/"):
            ents = re.findall(r"!?[\w]+", alt)
            if ents and all(token_ok(e.lstrip("!"), p) != e.startswith("!") for e in ents):
                return True
        return False
    if c.get("cl") and p["class"] not in c["cl"]:
        return False
    if c.get("ra") and p["race"] not in c["ra"] and not (p["race"] == "Scourge" and "Undead" in c["ra"]):
        return False
    if c.get("fa") and p["faction"] not in c["fa"]:
        return False
    return True


def fits(m, p):
    if m.get("faction") and m["faction"] != p["faction"]:
        return False
    if m.get("races") and p["race"] not in m["races"] and not (p["race"] == "Scourge" and "Undead" in m["races"]):
        return False
    return applies(m.get("cond"), p)


# --------------------------------------------------------------------- routes
metas = []
for g in rxp:
    metas.append({"id": "rxp:" + g["name"], "src": "rxp", "name": g["name"], "faction": g.get("faction"),
                  "cond": g.get("cond"), "min": g["min"], "max": g["max"], "next": g.get("next"),
                  "defaultfor": g.get("defaultfor"), "steps": g["steps"]})
for g in ps:
    metas.append({"id": g["id"], "src": "ps", "name": clean(g["name"]), "faction": g.get("faction"),
                  "races": g.get("races"), "min": g["min"], "max": g["max"], "nextid": g.get("nextid"), "steps": g["steps"]})
by_id = {m["id"]: m for m in metas}


def ps_for_level(level, p):
    best = None
    for m in metas:
        if m["src"] == "ps" and fits(m, p) and m["max"] > level and m["min"] <= level + 1:
            if m.get("races"):
                if level < 12:
                    return m
            elif not best or (m["min"], m["max"]) < (best["min"], best["max"]):
                best = m
    if best:
        return best
    for m in metas:
        if m["src"] == "ps" and fits(m, p) and m["max"] > level:
            return m
    return None


def start(p):
    best = None
    for m in metas:
        if m["src"] == "rxp" and fits(m, p) and m.get("defaultfor") and m["defaultfor"] != "None" \
                and applies(m["defaultfor"], p) and m["min"] <= 1 < m["max"]:
            if not best or m["min"] > best["min"]:
                best = m
    return best or ps_for_level(1, p)


def next_of(m, p):
    if m["src"] == "rxp" and m.get("next"):
        for names, cond in m["next"]:
            if applies(cond, p):
                for n in names:
                    for o in metas:
                        if o["src"] == "rxp" and o["name"] == n and fits(o, p):
                            return o
    if m.get("nextid") and m["nextid"] in by_id and fits(by_id[m["nextid"]], p):
        return by_id[m["nextid"]]
    p2 = dict(p, level=max(p["level"], m["max"]))
    o = ps_for_level(p2["level"], p2)
    return o if o and o["id"] != m["id"] else None


def chain(p):
    out, seen = [], set()
    m = start(p)
    while m and m["id"] not in seen and len(out) < 80:
        seen.add(m["id"])
        out.append(m["id"])
        p = dict(p, level=max(p["level"], m["max"]))
        m = next_of(m, p)
    return out


# numérotation des fichiers de route
num = {m["id"]: i for i, m in enumerate(metas, 1)}

DEFAULT_TEXT = {"v": "Vendez vos objets et réparez", "tn": "Allez voir votre maître de classe", "fp": "Prenez le point de vol",
                "fly": "Prenez un vol", "hs": "Utilisez votre pierre de foyer", "home": "Liez votre pierre de foyer à l'auberge",
                "die": "Mourez puis ressuscitez à l'ange (raccourci)"}


def goal_text(g):
    k = g["k"]
    if k == "g":
        return None
    x = clean(g.get("x"))
    if x:
        return x
    q = g.get("q")
    if k == "a":
        return f"Acceptez « {qfr.get(q, 'quête %s' % q)} »"
    if k == "t":
        return f"Rendez « {qfr.get(q, 'quête %s' % q)} »"
    if k == "c":
        return f"Terminez « {qfr.get(q, 'quête %s' % q)} »" + (f" : {g['cm']}" if g.get("cm") else "")
    if k == "col":
        return f"Récupérez {g.get('n', 1)} × {nfr.get('item:%s' % g['i'], g.get('cm') or 'objet %s' % g['i'])}"
    if k == "lv":
        return f"Montez au niveau {g['l']}"
    if k == "tr":
        return "Apprenez un nouveau sort chez votre maître"
    if k == "ab":
        return f"Abandonnez « {qfr.get(q, 'quête %s' % q)} »"
    return DEFAULT_TEXT.get(k)


KIND = {"a": "accepter", "t": "rendre", "c": "objectif", "col": "objet", "lv": "niveau", "tr": "sort", "v": "marchand",
        "fly": "vol", "fp": "vol", "hs": "foyer", "home": "foyer", "die": "mort", "tn": "maître", "m": "info", "ab": "abandon"}

for m in metas:
    steps = []
    for s in m["steps"]:
        e = {}
        if s.get("h"):
            e["h"] = clean(s["h"])
        if s.get("c") is not None:
            e["c"] = s["c"]
        lines = []
        for t in s.get("t", []):
            if isinstance(t, list):
                tx = clean(t[0])
                if tx:
                    lines.append({"x": tx, "c": t[1], "k": "info"})
            else:
                tx = clean(t)
                if tx:
                    lines.append({"x": tx, "k": "info"})
        for g in s["g"]:
            tx = goal_text(g)
            if tx:
                ln = {"x": tx, "k": KIND.get(g["k"], "info")}
                if g.get("c") is not None:
                    ln["c"] = g["c"]
                lines.append(ln)
        if s.get("cw"):
            e["chemin"] = 1
        if lines:
            e["l"] = lines
            steps.append(e)
    with open(os.path.join(OUT, "routes", f"{num[m['id']]}.json"), "w", encoding="utf-8") as f:
        json.dump(steps, f, ensure_ascii=False, separators=(",", ":"))

routes = [{"n": num[m["id"]], "nom": m["name"], "src": "RestedXP" if m["src"] == "rxp" else "Polestar",
           "min": m["min"], "max": m["max"], "etapes": len(m["steps"])} for m in metas]
parcours = {}
for race, race_fr, fac in RACES:
    for cl in CLASSES:
        p = {"race": race, "class": cl, "faction": fac, "level": 1}
        parcours[f"{race}|{fac}|{cl}"] = [num[i] for i in chain(p)]
index = {"races": [{"cle": f"{r}|{f}", "nom": n, "faction": f} for r, n, f in RACES],
         "classes": [{"cle": c, "nom": CLASSES_FR[c]} for c in CLASSES],
         "routes": routes, "parcours": parcours}
json.dump(index, open(os.path.join(OUT, "index.json"), "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))

# --------------------------------------------------------------------- équipement
fsrc = open(os.path.join(PS_DIR, "addon/Polestar_ItemDB/Forever.lua"), encoding="utf-8").read()
items_raw = next(tables_after(fsrc, "DB.Register(nil,"))
# RegisterLeveling(méta, données) : on lit le deuxième tableau
i0 = fsrc.index("DB.RegisterLeveling(")
from luadata import P
p_ = P(fsrc, i0 + len("DB.RegisterLeveling("))
p_.ws(); p_.table(); p_.ws(); assert fsrc[p_.i] == ","; p_.i += 1; p_.ws()
lev = p_.table()
profs, en_names, src, quests, npcs, zones = (lev[k] for k in ("professions", "names", "src", "quests", "npcs", "zones"))

gtxt = open(os.path.join(ADDON, "Data", "Equipement.lua"), encoding="utf-8").read()
gear = next(tables_after(gtxt, "EnvolData.gear ="))

PROF_FR = {"Alchemy": "Alchimie", "Blacksmithing": "Forge", "Enchanting": "Enchantement", "Engineering": "Ingénierie",
           "Leatherworking": "Travail du cuir", "Tailoring": "Couture", "Jewelcrafting": "Joaillerie", "Mining": "Minage",
           "Herbalism": "Herboristerie", "Skinning": "Dépeçage", "Cooking": "Cuisine", "First Aid": "Secourisme", "Fishing": "Pêche"}
CLASS_BIT = {"WARRIOR": 1, "PALADIN": 2, "HUNTER": 4, "ROGUE": 8, "PRIEST": 16, "SHAMAN": 64, "MAGE": 128, "WARLOCK": 256, "DRUID": 1024}
TOK = {"mpr": "mp5", "hpr": "hp5"}
STAT_FR = {"str": "Force", "agi": "Agilité", "sta": "Endurance", "int": "Intelligence", "spi": "Esprit", "armor": "Armure",
           "ap": "Puissance d'attaque", "rap": "PA à distance", "sp": "Puissance des sorts", "heal": "Soins", "mp5": "Mana/5 s",
           "hp5": "Vie/5 s", "crit": "Critique", "hit": "Toucher", "spellCrit": "Critique des sorts", "spellHit": "Toucher des sorts",
           "defense": "Défense", "dodge": "Esquive", "parry": "Parade", "blockValue": "Valeur de blocage", "dps": "DPS de l'arme",
           "rdps": "DPS à distance", "spShadow": "Dégâts d'ombre", "spFire": "Dégâts de feu", "spFrost": "Dégâts de givre",
           "spArcane": "Dégâts des arcanes", "spHoly": "Dégâts du sacré", "spNature": "Dégâts de nature"}

# emplacement d'affichage selon le type d'inventaire
SLOT = {1: "Tête", 2: "Cou", 3: "Épaules", 5: "Torse", 20: "Torse", 6: "Taille", 7: "Jambes", 8: "Pieds", 9: "Poignets",
        10: "Mains", 11: "Doigt", 12: "Bijou", 16: "Dos", 13: "Arme à une main", 21: "Arme à une main",
        17: "Arme à deux mains", 22: "Main gauche", 14: "Main gauche", 23: "Main gauche",
        15: "À distance", 25: "À distance", 26: "À distance", 28: "Relique"}
SLOT_ORDER = ["Arme à deux mains", "Arme à une main", "Main gauche", "À distance", "Relique", "Tête", "Cou", "Épaules",
              "Dos", "Torse", "Poignets", "Mains", "Taille", "Jambes", "Pieds", "Doigt", "Bijou"]
RANGED = {15, 25, 26}


def parse_item(s):
    parts = s.split()
    inv, ilvl, req, q, cid, sub = (int(x) for x in parts[:6])
    st = {}
    cls = None
    for t in parts[6:]:
        m = re.match(r"([a-zA-Z]+)(-?\d+)$", t)
        if not m:
            continue
        k, v = m.group(1), int(m.group(2))
        if k == "cls":
            cls = v
        elif k != "uniq":
            st[TOK.get(k, k)] = st.get(TOK.get(k, k), 0) + v
    if "dmin" in st and st.get("speed"):
        dps = (st["dmin"] + st["dmax"]) / 2 / (st["speed"] / 1000)
        st["rdps" if inv in RANGED else "dps"] = round(dps, 1)
    for k in ("dmin", "dmax", "speed"):
        st.pop(k, None)
    return {"inv": inv, "ilvl": ilvl, "req": req, "q": q, "cid": cid, "sub": sub, "st": st, "cls": cls}


def quest_info(qid):
    s = quests.get(qid)
    if not isinstance(s, str):
        return None
    head, choices, its, name = (s.split("|") + ["", "", "", ""])[:4]
    lvl, req, side, zone, rrace, rcls, dng = (head.split() + ["0"] * 7)[:7]
    return {"level": int(lvl), "side": int(side), "zone": int(zone), "dungeon": dng != "0", "name": qfr.get(qid, name)}


def zone_name(z):
    en = zones.get(z)
    return ZONES_FR.get(en, en) if en else None


RAIDS = {1977, 2677, 3428, 3429, 3456, 2717}  # Zul'Gurub, Repaire de l'Aile noire, AQ 40/20, Naxxramas, Cœur du Magma
MIN_DROP = 2.0  # % : en dessous, trop rare pour compter dessus en leveling


def sources(iid):
    """-> textes de provenance, factions possibles, niveau de quête le plus bas (ou None)"""
    s = src.get(iid)
    out, sides, qlv = [], set(), None
    if not isinstance(s, str):
        return out, {1, 2}, None
    for tok in s.split():
        m = re.match(r"q(\d+)$", tok)
        if m:
            qi = quest_info(int(m.group(1)))
            if qi and qi["zone"] not in RAIDS:
                sides |= {1, 2} if qi["side"] == 3 else {qi["side"]}
                if qi["level"]:
                    qlv = qi["level"] if qlv is None else min(qlv, qi["level"])
                z = zone_name(qi["zone"])
                out.append(f"Quête « {qi['name']} »" + (f" — {z}" if z else "") + (f", niv. {qi['level']}" if qi["level"] else "")
                           + (" (donjon)" if qi["dungeon"] else ""))
            continue
        m = re.match(r"d(\d+)x(\d+)z(\d+)$", tok)
        if m:
            npc, pct, zid = int(m.group(1)), int(m.group(2)) / 10, int(m.group(3))
            if pct < MIN_DROP or zid in RAIDS:
                continue
            z = zone_name(zid)
            sides |= {1, 2}
            who = nfr.get(f"npc:{npc}") or npcs.get(npc)
            if npc and who:
                out.append(f"Butin : {who} ({pct:g} %)" + (f" — {z}" if z else ""))
            else:
                out.append(f"Butin ({pct:g} %)" + (f" — {z}" if z else ""))
            continue
        m = re.match(r"c(\d+)p(\d+)s(\d+)$", tok)
        if m:
            pr = profs[int(m.group(2)) - 1] if 0 < int(m.group(2)) <= len(profs) else "?"
            sides |= {1, 2}
            out.append(f"Artisanat : {PROF_FR.get(pr, pr)} ({m.group(3)})")
    return out, sides, qlv


items = {}
for iid, s in items_raw.items():
    if iid not in en_names:
        continue
    it = parse_item(s)
    if it["inv"] not in SLOT or it["q"] >= 5:
        continue  # pas d'emplacement, ou objet légendaire (contenu de raid)
    it["slot"] = SLOT[it["inv"]]
    it["nom"] = nfr.get(f"item:{iid}", en_names[iid])
    it["src"], it["sides"], qlv = sources(iid)
    if not it["src"]:
        continue  # provenance inconnue, raid ou butin trop rare
    # niveau réel d'accès : niveau requis, sinon niveau de la quête ou de l'objet
    eff = it["req"] if it["req"] > 0 else max(1, it["ilvl"] - 5)
    if qlv:
        eff = max(eff, qlv - 2)
    it["eff"] = eff
    items[iid] = it


def usable(it, cl, level):
    prof = gear["prof"][cl]
    if it["cls"] and not (it["cls"] & CLASS_BIT[cl]):
        return False
    if it["cid"] == 4:
        sub = it["sub"]
        if sub == 0:
            return True
        if 1 <= sub <= 4:
            mx = prof.get("armor40") if level >= 40 and prof.get("armor40") else prof["armor"]
            return sub <= mx
        if sub == 6:
            return bool(prof.get("shield"))
        if sub in (7, 8, 9):
            return prof.get("relic") == sub
        return False
    if it["cid"] == 2:
        if not prof["weapons"].get(str(it["sub"])):
            return False
        if it["inv"] in (22,) and not (prof.get("dw") and level >= prof["dw"]):
            return False
        return True
    return False


def weights(cl, spec, level):
    bands = gear["bands"][cl][spec]
    b = next((b for b in bands if level <= b["upTo"]), bands[-1])
    w = dict(b["w"])
    if spec == "feral" and "dps" not in w:
        w["dps"] = 14 * w.get("ap", 0)
    return w


def score(it, w):
    sc = 0.0
    for k, v in it["st"].items():
        sc += v * w.get(k, 0)
    return sc


LEVELS = [10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60]
rank = {}
used = set()
for cl in CLASSES:
    for spec in gear["classes"][cl]["specs"]:
        sk = spec["key"]
        for lvl in LEVELS:
            w = weights(cl, sk, lvl)
            for side, fac in ((1, "Alliance"), (2, "Horde")):
                per = {}
                for iid, it in items.items():
                    if it["eff"] > lvl or side not in it["sides"] or not usable(it, cl, lvl):
                        continue
                    sc = score(it, w)
                    if sc <= 0:
                        continue
                    per.setdefault(it["slot"], []).append((sc, iid))
                res = {}
                for sl in SLOT_ORDER:
                    lst = sorted(per.get(sl, []), reverse=True)[:3]
                    if lst:
                        res[sl] = [[iid, round(sc, 1)] for sc, iid in lst]
                        used.update(i for _, i in lst)
                rank[f"{cl}|{sk}|{lvl}|{fac}"] = res

specs = {cl: [{"cle": s["key"], "nom": s["fr"], "defaut": s["key"] == gear["classes"][cl]["default"]}
              for s in gear["classes"][cl]["specs"]] for cl in CLASSES}
prio = {}
for cl in CLASSES:
    for s in gear["classes"][cl]["specs"]:
        for lvl in LEVELS:
            w = weights(cl, s["key"], lvl)
            main = w.get("str") or w.get("agi") or w.get("int") or w.get("sta") or 1
            # stats « par point » seulement (les % de critique/toucher ne se comparent pas directement)
            prim = ("str", "agi", "sta", "int", "spi", "ap", "sp", "heal", "mp5", "spShadow", "spFire", "spFrost", "spNature", "spArcane")
            top = sorted(((v, k) for k, v in w.items() if k in prim and v >= 0.2), reverse=True)
            prio[f"{cl}|{s['key']}|{lvl}"] = [STAT_FR[k] for v, k in top[:5]]

QUAL = {0: "#9d9d9d", 1: "#ffffff", 2: "#1eff00", 3: "#0070dd", 4: "#a335ee", 5: "#ff8000"}
eq = {"niveaux": LEVELS, "emplacements": SLOT_ORDER, "specs": specs, "priorites": prio,
      "objets": {str(i): {"nom": items[i]["nom"], "c": QUAL.get(items[i]["q"], "#ffffff"), "niv": items[i]["eff"],
                          "src": items[i]["src"][:2],
                          "stats": ", ".join(f"{v:g} {STAT_FR.get(k, k)}" for k, v in items[i]["st"].items() if k in STAT_FR)}
                 for i in sorted(used)},
      "classements": rank}
json.dump(eq, open(os.path.join(OUT, "equipement.json"), "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))

tot = sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(OUT) for f in fs)
print(f"lanceur : {len(routes)} routes, {len(parcours)} parcours, {len(items)} objets ({len(used)} classés), {tot // 1024} Ko")
