"""Traduit en français les noms de monstres, PNJ et objets restés en anglais dans les textes des guides.

Dictionnaire anglais -> français construit par identifiant :
  noms anglais : forever-db (Polestar, GPLv3), guides Polestar, base d'objets Forever ;
  noms français : tables de noms françaises de Polestar (noms du client) ;
  plus la table de PNJ français de RestedXP (locale/NPCnames.lua, CC BY-NC-SA).
"""
import json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from luadata import P

WORK = os.environ.get("ENVOL_WORK", "work")
PS_DIR = os.environ.get("ENVOL_PS", "upstream/polestar")
RXP_DIR = os.environ.get("ENVOL_RXP", "upstream/RXPGuides")

_dico = None
_par_id = None


def _charger():
    global _dico, _par_id
    fr = json.load(open(os.path.join(WORK, "polestar_names_fr.json"), encoding="utf-8"))
    en = {}
    db = os.path.join(PS_DIR, "forever-db", "data")
    for kind in ("npc", "item", "object"):
        f = os.path.join(db, kind + ".jsonl")
        if os.path.exists(f):
            for line in open(f, encoding="utf-8"):
                o = json.loads(line)
                if o.get("name"):
                    en[f"{kind}:{o['id']}"] = o["name"]
    for f in ("Polestar_Guides_Horde/Guides.lua", "Polestar_Guides_Alliance/Guides.lua", "Polestar_Guides/Guides.lua"):
        p = os.path.join(PS_DIR, "addon", f)
        if os.path.exists(p):
            for m in re.finditer(r'\["((?:npc|item|object):\d+)"\] = "((?:[^"\\]|\\.)*)"', open(p, encoding="utf-8").read()):
                en.setdefault(m.group(1), m.group(2))
    d = {}
    for k, v in en.items():
        if k in fr and fr[k] != v:
            d.setdefault(v, fr[k])
    # table de PNJ française de RestedXP
    p = os.path.join(RXP_DIR, "locale", "NPCnames.lua")
    if os.path.exists(p):
        s = open(p, encoding="utf-8").read()
        i = s.find('elseif locale == "frFR"')
        if i >= 0:
            j = s.find("addon.npcNames =", i)
            q = P(s, j + len("addon.npcNames ="))
            q.ws()
            for a, b in q.table().items():
                if isinstance(a, str) and isinstance(b, str) and a != b:
                    d.setdefault(a, b)
    _dico = d
    _par_id = fr
    return d


def _cherche(nom):
    d = _dico if _dico is not None else _charger()
    n = nom.strip()
    m = re.match(r"^(.*?)::(\d+)$", n)
    if m:  # « Nom::12345 » : identifiant de PNJ fourni
        t = _par_id.get(f"npc:{m.group(2)}")
        return t or m.group(1)
    premier = re.sub(r"^(\w+?)s\b", r"\1", n)  # « Chunks of Boar Meat » -> « Chunk of Boar Meat »
    for c in (n, n[:-1] if n.endswith("s") else None, n[:-3] + "y" if n.endswith("ies") else None,
              n[:-2] if n.endswith("es") else None, premier if premier != n else None):
        if c and c in d:
            return d[c]
    return None


_ANGLAIS = re.compile(r"[A-Za-z]")
_ACCENTS = re.compile(r"[éèêàâçùûôîïœ]")


def _segment(nom):
    """Traduit un nom (avec ou sans crochets), sinon le renvoie tel quel."""
    brut = nom
    crochets = nom.startswith("[") and nom.endswith("]")
    coeur = nom[1:-1] if crochets else nom
    if not _ANGLAIS.search(coeur) or _ACCENTS.search(coeur):
        return re.sub(r"::\d+", "", brut)
    t = _cherche(coeur)
    if not t:
        return re.sub(r"::\d+", "", brut)
    return f"[{t}]" if crochets else t


stats = {"traduits": 0}


def traduire(texte):
    if not texte:
        return texte

    def couleur(m):
        nouveau = _segment(m.group(2))
        if nouveau != m.group(2):
            stats["traduits"] += 1
        return m.group(1) + nouveau + "|r"

    texte = re.sub(r"(\|c[0-9a-fA-F]{8})([^|]+?)\|r", couleur, texte)

    def crochet(m):
        nouveau = _segment(m.group(0))
        if nouveau != m.group(0):
            stats["traduits"] += 1
        return nouveau

    return re.sub(r"\[[^\[\]|]{2,60}\]", crochet, texte)


def nom_francais(kind, ident):
    if _dico is None:
        _charger()
    return _par_id.get(f"{kind}:{ident}")
