"""Convert Polestar leveling guides (GPLv3, data per THIRD_PARTY.md) to Envol data, in French."""
import json, re, os
import os
WORK = os.environ.get("ENVOL_WORK", "work")
PS_DIR = os.environ.get("ENVOL_PS", "upstream/polestar")
RXP_DIR = os.environ.get("ENVOL_RXP", "upstream/RXPGuides")
ADDON = os.environ.get("ENVOL_ADDON", "addon/Envol")
os.makedirs(WORK, exist_ok=True)
from collections import Counter

lev = json.load(open(os.path.join(WORK, "polestar_leveling.json")))
tfr = json.load(open(os.path.join(WORK, "polestar_texts_fr.json")))
nfr = json.load(open(os.path.join(WORK, "polestar_names_fr.json")))

# Era map frames (world bounds) from Polestar's MapFrames.lua
frames = {}
for m in re.finditer(r"\[(\d+)\] = \{ c = (\d+), left = ([-\d.]+), right = ([-\d.]+), top = ([-\d.]+), bottom = ([-\d.]+) \}",
                     open(os.path.join(PS_DIR, "addon/Polestar_Guides/MapFrames.lua")).read()):
    frames[int(m.group(1))] = tuple(float(x) for x in m.groups()[1:])

warn = Counter()
CLS = {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"}


RUNTIME_KINDS = {"area", "zone", "map"}


def name(kind, i, guide, fallback=None):
    if kind in RUNTIME_KINDS:
        # résolu en jeu par le client (noms français) ; repli anglais après la barre
        en = guide.get("names", {}).get(f"{kind}:{i}") or fallback or ""
        return "{%s:%s|%s}" % (kind, i, en.replace("}", ")"))
    n = nfr.get(f"{kind}:{i}")
    if n:
        return n
    n = guide.get("names", {}).get(f"{kind}:{i}")
    return n or fallback or f"{kind} {i}"


def resolve(text, guide):
    if not text:
        return text
    tr = tfr.get(guide["id"], {}).get(text)
    if tr:
        text = tr
    else:
        warn["untranslated"] += 1
    return re.sub(r"\{(\w+):(\d+)(?::[^}]*)?\}", lambda m: name(m.group(1), m.group(2), guide), text)


def pos(go):
    if "map" not in go or go.get("x") is None:
        return None
    m, x, y = go["map"], go["x"], go["y"]
    if go.get("f") == "e" and m in frames:
        c, left, right, top, bottom = frames[m]
        a = left + x / 100 * (right - left)
        b = top + y / 100 * (bottom - top)
        return ["w", int(c), round(a, 1), round(b, 1)]
    return ["m", m, x, y]


def cond(only):
    if not only:
        return None
    c = {}
    if only.get("classes"):
        c["cl"] = [x.upper() for x in only["classes"]]
    if only.get("races"):
        c["ra"] = only["races"]
    if only.get("factions"):
        c["fa"] = only["factions"]
    return c or None


def q(go, g):
    return name("quest", go["quest"], g, go.get("title"))


def npc_of(go, g):
    if go.get("npc"):
        return name("npc", go["npc"], g, go.get("npcName"))
    if go.get("object"):
        return name("object", go["object"], g, go.get("objName"))
    return None


def place(go, g):
    if go.get("area"):
        return name("area", go["area"], g, go.get("location"))
    return go.get("location") or ""


def conv_goal(go, g):
    t = go["t"]
    out = None
    who = npc_of(go, g)
    if t == "accept":
        out = {"k": "a", "q": go["quest"], "x": f"Acceptez « {q(go, g)} »" + (f" ({who})" if who else "")}
    elif t == "turnin":
        out = {"k": "t", "q": go["quest"], "x": f"Rendez « {q(go, g)} »" + (f" ({who})" if who else "")}
        if go.get("direct"):
            out["k"] = "m"
    elif t == "collect":
        it = name("item", go["item"], g, go.get("itemName"))
        n = go.get("count", 1)
        src = ""
        if go.get("from"):
            fk = go.get("fromKind", "npc")
            src = " sur " + name(fk, go["fromId"], g, go["from"]) if fk == "npc" else " (" + name(fk, go["fromId"], g, go["from"]) + ")"
        out = {"k": "col", "i": go["item"], "n": n, "x": f"Récupérez {n} × {it}{src}"}
        if f"item:{go['item']}" not in nfr:
            out["en"] = it  # pas de nom français connu : le client le donnera en jeu
        if go.get("quest"):
            out["q"] = go["quest"]
            if go.get("oi"):
                out["o"] = go["oi"]
    elif t == "kill":
        tgt = go.get("target")
        tname = name("npc", go["target"], g, None) if isinstance(tgt, int) else (tgt or "")
        n = go.get("count")
        x = f"Tuez {tname}" + (f" ×{n}" if n and n > 1 else "")
        if go.get("quest") and go.get("oi"):
            out = {"k": "c", "q": go["quest"], "o": go["oi"], "x": x}
        elif go.get("quest"):
            out = {"k": "c", "q": go["quest"], "x": x}
        else:
            out = {"k": "m", "x": x}
    elif t == "complete":
        out = {"k": "c", "q": go["quest"], "x": f"Terminez « {q(go, g)} »"}
    elif t == "goto":
        label = resolve(go.get("text"), g) if go.get("text") else None
        out = {"k": "g", "r": go.get("r", 8), "x": "Allez à : " + label if label else "Allez au point indiqué"}
    elif t == "train":
        if go.get("class"):
            out = {"k": "tn", "x": "Allez voir votre maître de classe"}
            cands = []
            for c in go.get("candidates") or []:
                p = pos(c)
                if p:
                    e = {"p": p, "n": name("npc", c["npc"], g, c.get("npcName"))}
                    if c.get("classes"):
                        e["cl"] = [x.upper() for x in c["classes"]]
                    cands.append(e)
            if cands:
                out["cand"] = cands
        else:
            out = {"k": "tn", "x": f"Allez voir {who} (formation)" if who else "Allez voir le maître"}
    elif t == "fly":
        out = {"k": "fly", "x": f"Prenez un vol vers {place(go, g)}"}
    elif t == "getfp":
        out = {"k": "fp", "x": f"Récupérez le point de vol : {place(go, g)}"}
    elif t == "sethome":
        out = {"k": "home", "x": f"Liez votre pierre de foyer : {place(go, g)}"}
    elif t == "hearth":
        out = {"k": "hs", "x": f"Utilisez votre pierre de foyer ({place(go, g)})"}
    elif t == "vendor":
        out = {"k": "v", "x": f"Vendez et réparez" + (f" ({who})" if who else "")}
    elif t == "buy":
        it = name("item", go["item"], g, go.get("itemName"))
        n = go.get("count", 1)
        out = {"k": "col", "i": go["item"], "n": n, "x": f"Achetez {n} × {it}" + (f" ({who})" if who else "")}
        if f"item:{go['item']}" not in nfr:
            out["en"] = it
        cands = go.get("candidates") or []
        if cands and not go.get("map"):
            p = pos(cands[0])
            if p:
                out["p"] = p
    elif t == "use":
        it = name("item", go["item"], g, go.get("itemName")) if go.get("item") else ""
        if go.get("quest") and go.get("oi"):
            out = {"k": "c", "q": go["quest"], "o": go["oi"], "x": f"Utilisez {it}"}
        else:
            out = {"k": "m", "x": f"Utilisez {it}"}
    elif t == "interact":
        x = f"Interagissez avec {who}" if who else "Interagissez avec l'objet"
        if go.get("quest") and go.get("oi"):
            out = {"k": "c", "q": go["quest"], "o": go["oi"], "x": x}
        else:
            out = {"k": "m", "x": x}
    elif t == "talk":
        out = {"k": "m", "x": f"Parlez à {who}" if who else "Parlez au PNJ"}
    elif t == "die":
        out = {"k": "die", "x": f"Mourez et ressuscitez : {place(go, g)}"}
    elif t == "level":
        lvl = go["level"]; frac = go.get("frac") or 0
        out = {"k": "lv", "l": lvl, "xp": frac,
               "x": f"Montez niveau {lvl}" + (f" ({int(frac * 100)} %)" if frac else "")}
    elif t == "note":
        return None
    else:
        warn["goal:" + t] += 1
        return None
    if "p" not in out:
        p = pos(go)
        if p:
            out["p"] = p
    if go.get("note"):
        out["x"] += " — " + resolve(go["note"], g)
    if go.get("optional"):
        out["op"] = 1
    c = cond(go.get("only"))
    if c:
        out["c"] = c
    return out


def conv_when(ws):
    sk = []
    for w in ws or []:
        k = w["k"]
        if k == "onquest":
            sk.append(["onq", w["q"] if isinstance(w["q"], list) else [w["q"]]])
        elif k == "level":
            n = w["n"] + (w.get("frac") or 0)
            # shown only while level OP n holds -> skip when it does not
            sk.append(["lvlwhen", w["op"], n])
        elif k == "money":
            inv = {">=": "<", ">": "<", "<": ">", "<=": ">"}[w.get("op", ">=")]
            sk.append(["money", inv, w["n"]])
        elif k == "group":
            sk.append(["grp"])
        elif k == "bound":
            sk.append(["bound", w["area"], 1 if w.get("neg") else 0])
        elif k == "skill":
            pass
        else:
            warn["when:" + k] += 1
    return sk


out = []
for g in lev:
    steps = []
    for st in g["steps"]:
        s = {"g": []}
        title = resolve(st.get("title"), g)
        if title:
            s["h"] = title
        if st.get("note"):
            s["t"] = [resolve(st["note"], g)]
        for go in st["goals"]:
            if go["t"] == "note":
                s.setdefault("t", []).append(resolve(go.get("text") or go.get("note"), g))
                continue
            c = conv_goal(go, g)
            if c:
                s["g"].append(c)
        c = cond(st.get("only"))
        if c:
            s["c"] = c
        sk = conv_when(st.get("when"))
        if sk:
            s["sk"] = sk
        if st.get("along"):
            s["cw"] = st["along"] if isinstance(st["along"], str) else "self"
        if st.get("label"):
            s["lbl"] = st["label"]
        steps.append(s)
    title = resolve(g["title"], g)
    races = g.get("races")
    out.append({"src": "ps", "id": g["id"], "name": f"{g['minLevel']}-{g['maxLevel']} {title}",
                "faction": g.get("faction"), "min": g["minLevel"], "max": g["maxLevel"],
                "races": races, "nextid": g.get("next"), "steps": steps})
json.dump(out, open(os.path.join(WORK, "ps.json"), "w"), ensure_ascii=False)
print(len(out), "guides,", sum(len(g["steps"]) for g in out), "steps")
print(warn.most_common(20))
for g in out[:3]:
    print(json.dumps(g["steps"][:3], ensure_ascii=False)[:900])
