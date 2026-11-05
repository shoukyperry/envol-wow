"""Exercise the Envol addon in Lua 5.1 against a mocked WoW client."""
import re, sys, os, math
from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.environ.get("ENVOL_ADDON", os.path.join(HERE, "..", "addon", "Envol")) + "/"
L = lua51.LuaRuntime(unpack_returned_tuples=True)
L.execute("unpackOrig = unpack")
L.execute(open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8").read())


def load(files):
    for f in files:
        L.execute(open(ADDON + f, encoding="utf-8").read())


toc = [l.strip().replace("\\", "/") for l in open(ADDON + "Envol.toc", encoding="utf-8")
       if l.strip() and not l.startswith("##")]
load(toc)
M = L.globals().MOCK
E = L.globals().Envol
ok = True


def check(cond, msg):
    global ok
    print(("  OK   " if cond else "  ÉCHEC ") + msg)
    ok = ok and bool(cond)


def view_lines():
    L.execute("MOCK.texts = {}")
    L.execute("Envol.UpdateUI()")
    return [t for t in M.texts.values() if t]


print("== Connexion d'un Tauren Guerrier niveau 1")
M.Fire("PLAYER_LOGIN")
g = E.guide
check(g is not None and g.meta.name == "1-6 Mulgore", "route de départ = 1-6 Mulgore (%s)" % (g and g.meta.name))
v = E.view
print("   étape", v.idx, "/", v.total)
for t in view_lines()[:12]:
    print("   |", re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", t))

print("== Accepter la quête 747 puis 752")
M.onQuest[747] = True
M.Fire("QUEST_ACCEPTED", 747)
i1 = E.view.idx
M.onQuest[752] = True
M.Fire("QUEST_ACCEPTED", 752)
i2 = E.view.idx
check(i2 > i1 >= 2, "l'étape avance toute seule (%d -> %d)" % (i1, i2))
for t in view_lines()[:10]:
    print("   |", re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", t))

print("== Flèche : cible et rotation")
L.execute("Envol.UpdateArrowTarget()")
f = L.globals().EnvolArrow
f.scripts.OnUpdate(f, 0.1)
check(M.rotation is not None, "la flèche tourne (rotation = %s rad)" % M.rotation)

print("== Styles de flèche, halo et rotation fluide")
styles = L.execute("""
local out = {}
for i = 1, #Envol.ARROW_STYLES do out[#out + 1] = Envol.CycleArrowStyle() end
return table.concat(out, ",")
""")
check(styles.split(",")[-1] == "Arcane" and "Classique" in styles, "cycle des styles : " + styles)
L.execute("EnvolDB.arrowStyle = 'Feu'; EnvolDB.arrow3D = false; Envol.ApplyArrowStyle(); MOCK.rotation = nil")
f.scripts.OnUpdate(f, 0.03)
r1 = M.rotation
L.execute("MOCK.facing = MOCK.facing + 2.5")
f.scripts.OnUpdate(f, 0.03)
r2 = M.rotation
check(r1 is not None and r2 is not None and abs(r2 - r1) < 2.5, "rotation fluide (%.2f -> %.2f, la cible a sauté de 2,5 rad)" % (r1 or 0, r2 or 0))
L.execute("MOCK.facing = 0")

print("== Flèche en relief : bonne vue de la planche selon la direction")
L.execute("EnvolDB.arrowStyle = 'Arcane'; EnvolDB.arrow3D = true; Envol.ApplyArrowStyle()")
check("Relief" in str(M.texture), "texture en relief : %s" % M.texture)
ok3d = True
dirs = [L.eval("EnvolData.reliefAngles[%d]" % k) for k in range(1, 65)]
pire = 0
for deg in range(0, 360, 7):
    ang = math.radians(deg)
    L.execute("Envol.SetReliefAngle(%r)" % ang)
    tc = list(M.texcoord.values())
    idx = round(tc[2] * 8) * 8 + round(tc[0] * 8)
    err = abs((dirs[idx] - ang + math.pi) % (2 * math.pi) - math.pi)
    pire = max(pire, math.degrees(err))
ok3d = pire < 6
print("   écart max à l'écran : %.1f°" % pire)
check(ok3d, "vue choisie selon l'angle (64 vues, 8 x 8)")
# devant = vue 0 (la pointe s'éloigne), derrière = vue 32 (la pointe vient vers soi)
L.execute("Envol.SetReliefAngle(0)"); tc0 = list(M.texcoord.values())
L.execute("Envol.SetReliefAngle(math.pi)"); tcpi = list(M.texcoord.values())
check((round(tc0[0] * 8), round(tc0[2] * 8)) == (0, 0) and (round(tcpi[0] * 8), round(tcpi[2] * 8)) == (0, 4),
      "devant -> vue 0, derrière -> vue 32")
L.execute("EnvolDB.arrow3D = false; Envol.ApplyArrowStyle()")
check("Fleche_Arcane" in str(M.texture), "décoché : flèche plate (%s)" % M.texture)
L.execute("EnvolDB.arrow3D = true; Envol.ApplyArrowStyle()")

print("== Bouton suivant / précédent")
before = E.view.idx
L.execute("Envol.NextStep()")
mid = E.view.idx
L.execute("Envol.PrevStep()")
after = E.view.idx
check(mid > before and after < mid, "suivant %d -> %d, précédent -> %d" % (before, mid, after))
L.execute("Envol.NextStep()")

print("== Fin de route : enchaînement")
L.execute("EnvolChar.idx = #Envol.guide.steps + 1; Envol.Refresh(true)")
M.RunTimers()
check(E.guide.meta.name in ("6-12 Mulgore",), "route suivante = %s" % E.guide.meta.name)

print("== Fin des routes RestedXP : relais Polestar")
L.execute('Envol.OpenGuide("rxp:17-22 Serres-Rocheuses/Tarides/Orneval", 1)')
M.level = 22
L.execute("Envol.player.level = 22; EnvolChar.idx = #Envol.guide.steps + 1; Envol.Refresh(true)")
M.RunTimers()
check(E.guide.meta.src == "ps", "relais vers Polestar : %s" % E.guide.meta.name)

print("== Toutes les routes se chargent et s'affichent sans erreur")
errors = L.execute("""
local bad = {}
local saved = EnvolChar.guide
for _, m in ipairs(EnvolData.metas) do
  local ok, err = pcall(function()
    local steps = EnvolData.loaders[m.id]()
    Envol.guide = { meta = m, steps = steps, labels = {}, id = m.id }
    EnvolChar.guide = m.id
    for i = 1, #steps do
      EnvolChar.idx = i
      Envol.StepState(i)
      for gi, g in ipairs(steps[i].g) do Envol.GoalState(g, i, gi); Envol.GoalText(g) end
    end
  end)
  if not ok then bad[#bad + 1] = m.id .. " : " .. tostring(err) end
end
return table.concat(bad, "\\n")
""")
check(errors == "", "aucune erreur sur %s routes%s" % (len(list(L.globals().EnvolData.metas.values())), ("\n" + errors) if errors else ""))

print("== Races de départ")
for race, fac, cls, expect in [("Human", "Alliance", "PALADIN", "1-6 Comté-du-nord"), ("Gnome", "Alliance", "MAGE", "1-5 Vallée des Frigères"),
                               ("NightElf", "Alliance", "DRUID", "1-6 Sombrevallon"), ("Orc", "Horde", "HUNTER", "1-6 Durotar"),
                               ("Scourge", "Horde", "PRIEST", "1-6 Clairières de Tirisfal"), ("Skyborne", None, "SHAMAN", "1-9 Île de Zéphras"),
                               ("Skyborne", "Alliance", "PRIEST", "1-9 Île de Zéphras"), ("Troll", "Horde", "ROGUE", "1-6 Durotar")]:
    M.race, M.faction, M.class_, M.level = race, fac, cls, 1
    L.execute("MOCK.class = '%s'; Envol.player = {}; Envol.ResetConditionCache(); Envol.RefreshPlayer(); Envol.player.level = 1" % cls)
    gid = L.execute("return Envol.PickStartGuide()")
    name = L.execute("return Envol.GetMeta(Envol.PickStartGuide()).name") if gid else None
    check(name == expect, "%s %s -> %s" % (race, cls, name))

print("== Polestar par niveau (Horde 35, Alliance 47)")
for race, fac, lvl in [("Orc", "Horde", 35), ("Human", "Alliance", 47)]:
    M.race, M.faction, M.level = race, fac, lvl
    L.execute("Envol.player = {}; Envol.ResetConditionCache(); Envol.RefreshPlayer()")
    name = L.execute("return Envol.GetMeta(Envol.PickStartGuide()).name")
    check(name and name.startswith(tuple(str(x) for x in range(lvl - 3, lvl + 1))), "%s %d -> %s" % (race, lvl, name))

print("== Conseils d'équipement (Guerrier Armes niveau 10)")
L.execute("""
MOCK.class = 'WARRIOR'; MOCK.race = 'Orc'; MOCK.faction = 'Horde'; MOCK.level = 10
Envol.player = {}; Envol.ResetConditionCache(); Envol.RefreshPlayer(); Envol.Gear.Invalidate()
MOCK.itemDB['hache'] = { loc = 'INVTYPE_2HWEAPON', class = 2, sub = 1, stats = { ITEM_MOD_STRENGTH_SHORT = 5, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 8 } }
MOCK.itemDB['vieille'] = { loc = 'INVTYPE_2HWEAPON', class = 2, sub = 1, stats = { ITEM_MOD_STRENGTH_SHORT = 1, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 5 } }
MOCK.itemDB['plaques'] = { loc = 'INVTYPE_CHEST', class = 4, sub = 4, stats = { ITEM_MOD_STRENGTH_SHORT = 9 } }
MOCK.itemDB['robe'] = { loc = 'INVTYPE_CHEST', class = 4, sub = 1, stats = { ITEM_MOD_INTELLECT_SHORT = 6 }, sell = 500 }
MOCK.itemDB['cuir'] = { loc = 'INVTYPE_CHEST', class = 4, sub = 2, stats = { ITEM_MOD_STRENGTH_SHORT = 3, RESISTANCE0_NAME = 40 }, sell = 100 }
MOCK.equipped[16] = 'vieille'
""")
spec = L.execute("return Envol.Gear.SpecLabel()")
check(spec == "Auto (Armes)", "spé détectée : %s" % spec)
r = L.execute("return Envol.Gear.Compare('hache')")
check(r and r.upgrade and r.pct > 0, "hache 2M meilleure que l'arme portée (%+.1f %%)" % (r.pct if r else 0))
r = L.execute("return Envol.Gear.Compare('plaques')")
check(r and not r.usable and "40" in (r.reason or ""), "plaques avant 40 : %s" % (r and r.reason))
L.execute("MOCK.choices = {'robe', 'cuir'}")
best, up = L.execute("local b, u = Envol.Gear.BestReward(); return b, u")
check(best == 2 and up, "récompense conseillée : choix %s (amélioration=%s)" % (best, up))
L.execute("MOCK.bags = {'hache'}; Envol.Gear.Scan()")
u = L.globals().Envol.Gear.upgrade
check(u is not None and u.link == "hache", "amélioration repérée dans les sacs")
lines = view_lines()
check(any("Amélioration" in (t or "") for t in lines), "ligne « Amélioration » dans la fenêtre")

print("\nRÉSULTAT :", "tout est bon" if ok else "des tests échouent")
sys.exit(0 if ok else 1)
