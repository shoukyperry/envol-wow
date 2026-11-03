-- Envol : moteur d'étapes (choix de la route, avancement automatique, événements).

local E = Envol
local readable, safe = E.Readable, E.Safe

E.guide = nil      -- route ouverte : { meta = ..., steps = ..., labels = ... }
E.view = nil       -- ce qu'affichent la fenêtre et la flèche

local function charDB() return EnvolChar end

---------------------------------------------------------------------------
-- Chargement des routes
---------------------------------------------------------------------------

local metaById = {}
local function indexMetas()
	for _, m in ipairs(EnvolData.metas) do metaById[m.id] = m end
end

function E.GetMeta(id) return metaById[id] end

local function loadGuide(id)
	local meta = metaById[id]
	local loader = meta and EnvolData.loaders[id]
	if not loader then return nil end
	local ok, steps = pcall(loader)
	if not ok or type(steps) ~= "table" then return nil end
	local labels = {}
	for i, s in ipairs(steps) do
		if s.lbl then labels[s.lbl] = i end
		-- étape sans action bloquante ni lieu : simple conseil, affiché avec l'étape suivante
		local blocking, hasGoto = false, false
		for _, g in ipairs(s.g) do
			if g.k == "g" then
				hasGoto = true
				if g.r and g.r > 0 and not g.op then blocking = true end
			elseif not g.op and not g.info then
				blocking = true
			end
		end
		s.tip = (not blocking and not hasGoto and not s.cw) or nil
		s.gotoOnly = (not blocking and hasGoto) or nil
	end
	return { meta = meta, steps = steps, labels = labels, id = id }
end

-- Routes adaptées à ce personnage, dans l'ordre d'affichage du menu
function E.FittingGuides()
	local list = {}
	for _, m in ipairs(EnvolData.metas) do
		if E.GuideFits(m) then list[#list + 1] = m end
	end
	return list
end

-- Route Polestar qui correspond au niveau actuel
local function polestarForLevel(level)
	local best
	for _, m in ipairs(EnvolData.metas) do
		if m.src == "ps" and E.GuideFits(m) and m.max > level and m.min <= level + 1 then
			if m.races then
				if level < 12 then return m end
			elseif not best or m.min < best.min or (m.min == best.min and m.max < best.max) then
				best = m
			end
		end
	end
	if best then return best end
	for _, m in ipairs(EnvolData.metas) do
		if m.src == "ps" and E.GuideFits(m) and m.max > level then return m end
	end
	return nil
end

-- Première route à ouvrir pour ce personnage
function E.PickStartGuide()
	local level = E.player.level or 1
	if EnvolDB.source ~= "ps" then
		local best
		for _, m in ipairs(EnvolData.metas) do
			if m.src == "rxp" and E.GuideFits(m) and m.defaultfor and m.defaultfor ~= "None"
				and E.Applies(m.defaultfor) and m.min <= level and m.max > level then
				if not best or m.min > best.min then best = m end
			end
		end
		if best then return best.id end
	end
	local m = polestarForLevel(level)
	return m and m.id
end

-- Route suivante quand la route ouverte est terminée
function E.NextGuideId(meta)
	if meta.src == "rxp" and meta.next then
		for _, alt in ipairs(meta.next) do
			local names, cond = alt[1], alt[2]
			if E.Applies(cond) then
				for _, name in ipairs(names) do
					for _, m in ipairs(EnvolData.metas) do
						if m.src == "rxp" and m.name == name and E.GuideFits(m) then return m.id end
					end
				end
			end
		end
	end
	if meta.nextid and metaById[meta.nextid] and E.GuideFits(metaById[meta.nextid]) then
		return meta.nextid
	end
	-- fin des routes RestedXP publiques : relais par Polestar selon le niveau
	local m = polestarForLevel(math.max(E.player.level or 1, meta.max or 1))
	if m and m.id ~= meta.id then return m.id end
	return nil
end

---------------------------------------------------------------------------
-- État sauvegardé par personnage
---------------------------------------------------------------------------

local function stepKey(i) return i end

local function ticksFor(i, create)
	local db = charDB()
	local gid = db.guide
	db.ticks[gid] = db.ticks[gid] or {}
	local t = db.ticks[gid][stepKey(i)]
	if not t and create then
		t = {}
		db.ticks[gid][stepKey(i)] = t
	end
	return t
end

local function markOf(i)
	local db = charDB()
	return db.marks[db.guide] and db.marks[db.guide][i]
end

local function setMark(i, v)
	local db = charDB()
	db.marks[db.guide] = db.marks[db.guide] or {}
	db.marks[db.guide][i] = v
end

function E.OpenGuide(id, idx)
	local g = loadGuide(id)
	if not g then
		E.Print("route introuvable : " .. tostring(id))
		return
	end
	local db = charDB()
	if db.guide ~= id then
		-- on ne garde pas l'historique des anciennes routes : fichier de sauvegarde léger
		db.ticks, db.marks = {}, {}
	end
	db.guide = id
	db.idx = idx or 1
	db.hold = nil
	E.guide = g
	E.Refresh(true)
end

---------------------------------------------------------------------------
-- État des objectifs
---------------------------------------------------------------------------

-- Renvoie "done", "todo" ou "na" (sans objet : quête absente, etc.)
local function goalState(g, i, gi)
	local k = g.k
	local ticks = ticksFor(i)
	if ticks and ticks[gi] then return "done" end
	if k == "a" then
		if E.IsOnQuest(g.q) or E.IsQuestDone(g.q) then return "done" end
		return "todo"
	elseif k == "t" then
		if E.IsQuestDone(g.q) then return "done" end
		if not E.IsOnQuest(g.q) then return "na" end
		return "todo"
	elseif k == "c" or (k == "col" and g.q) then
		if E.IsQuestDone(g.q) then return "done" end
		if not E.IsOnQuest(g.q) then
			if k == "col" and E.ItemCount(g.i) >= (g.n or 1) then return "done" end
			return "na"
		end
		if E.IsQuestReady(g.q) then return "done" end
		if g.o then
			local objs = E.GetObjectives(g.q)
			local o = objs and objs[g.o]
			if o and o.finished then return "done" end
		end
		if k == "col" and E.ItemCount(g.i) >= (g.n or 1) then return "done" end
		return "todo"
	elseif k == "col" then
		if E.ItemCount(g.i) >= (g.n or 1) then return "done" end
		return "todo"
	elseif k == "lv" then
		local frac, lvl, xp, max = E.LevelFrac()
		local x = g.xp or 0
		if lvl > g.l then return "done" end
		if x < 0 then
			if lvl >= g.l or (lvl == g.l - 1 and xp >= max + x) then return "done" end
		elseif x >= 1 then
			if lvl == g.l and xp >= x then return "done" end
		else
			if lvl == g.l and xp >= max * x then return "done" end
		end
		return "todo"
	elseif k == "tr" then
		if E.KnowsSpell(g.s) then return "done" end
		return "todo"
	elseif k == "ab" then
		if not E.IsOnQuest(g.q) then return "done" end
		return "todo"
	end
	return "todo"
end
E.GoalState = goalState

local function isBlocking(g)
	if g.op or g.info then return false end
	if g.k == "g" then return g.r and g.r > 0 or false end
	return true
end

---------------------------------------------------------------------------
-- Conditions d'affichage d'une étape
---------------------------------------------------------------------------

local function cmp(a, op, b)
	if op == "<" then return a < b
	elseif op == "<=" then return a <= b
	elseif op == ">" then return a > b
	elseif op == ">=" then return a >= b
	elseif op == "=" or op == "==" then return a == b end
	return false
end

local function anyOnQuest(ids)
	for _, q in ipairs(ids) do if E.IsOnQuest(q) then return true end end
	return false
end

local function currentMap()
	return C_Map and C_Map.GetBestMapForUnit and safe(C_Map.GetBestMapForUnit, "player")
end

-- vrai si le prédicat demande de sauter l'étape
local function predicateSkips(p)
	local kind = p[1]
	if kind == "onq" then
		return not anyOnQuest(p[2])
	elseif kind == "notonq" then
		return anyOnQuest(p[2])
	elseif kind == "qc" then
		local q = p[2][1]
		return not (q and E.IsQuestReady(q))
	elseif kind == "qnc" then
		local q = p[2][1]
		return not (q and E.IsOnQuest(q) and not E.IsQuestReady(q))
	elseif kind == "ti" then
		for _, q in ipairs(p[2]) do if not E.IsQuestDone(q) then return true end end
		return false
	elseif kind == "avail" then
		for _, q in ipairs(p[2]) do
			if not E.IsQuestDone(q) and not E.IsOnQuest(q) then return false end
		end
		return true
	elseif kind == "money" then
		return cmp(E.Money(), p[2] == "<" and "<" or ">=", p[3])
	elseif kind == "ic" then
		local n = 0
		for _, id in ipairs(p[2]) do n = n + E.ItemCount(id) end
		local op, want, eq = p[3], p[4], p[5]
		local ok
		if op == "<" then ok = n < want or (eq and n == want)
		elseif op == ">" then ok = n > want or (eq and n == want)
		else ok = n >= want end
		return not ok
	elseif kind == "zone" then
		local m = currentMap()
		if not m then return false end
		local inside = false
		for _, id in ipairs(p[2]) do if id == m then inside = true end end
		if p[3] == 1 then return not inside end
		return inside
	elseif kind == "sub" then
		local name = E.AreaName(p[2])
		local sub = safe(GetSubZoneText)
		local inside = name ~= nil and sub ~= nil and sub == name
		if p[3] == 1 then return not inside end
		return inside
	elseif kind == "xp" then
		local _, lvl, xp, max = E.LevelFrac()
		local L, x = p[2], p[3] or 0
		local reached
		if x < 0 then
			reached = lvl >= L or (lvl == L - 1 and xp >= max + x)
		elseif x >= 1 then
			reached = lvl > L or (lvl == L and xp >= x)
		else
			reached = lvl > L or (lvl == L and xp >= max * x)
		end
		if p[4] == 1 then return not reached end
		return reached
	elseif kind == "minlvl" then
		return (E.player.level or 1) < p[2]
	elseif kind == "lvlwhen" then
		return not cmp(E.LevelFrac(), p[2], p[3])
	elseif kind == "grp" then
		return not EnvolDB.groupQuests
	elseif kind == "bound" then
		local name = E.AreaName(p[2])
		local bound = safe(GetBindLocation)
		local at = name ~= nil and bound == name
		if p[3] == 1 then return at end
		return not at
	end
	return false
end

local function stepApplies(s)
	if s.c and not E.Applies(s.c) then return false end
	if s.sk then
		for _, p in ipairs(s.sk) do
			if predicateSkips(p) then return false end
		end
	end
	if s.skc then
		for _, p in ipairs(s.skc) do
			if E.Applies(p[#p]) and predicateSkips(p) then return false end
		end
	end
	return true
end

-- "done", "skip", "todo" ou "manual" (attend un clic sur ▶)
local function stepState(i)
	local g = E.guide
	local s = g.steps[i]
	local mark = markOf(i)
	if mark then return mark == "d" and "done" or "skip" end
	if not stepApplies(s) then return "skip" end
	if s.req then
		local ri = g.labels[s.req]
		if ri and markOf(ri) == "s" then return "skip" end
	end
	local blocking, todo, na, applicable = 0, 0, 0, 0
	for gi, goal in ipairs(s.g) do
		if E.Applies(goal.c) then
			applicable = applicable + 1
			if isBlocking(goal) then
				local st = goalState(goal, i, gi)
				if st == "na" then
					na = na + 1
				else
					blocking = blocking + 1
					if st ~= "done" then todo = todo + 1 end
				end
			end
		end
	end
	if blocking == 0 then
		if na > 0 then return "skip" end
		if s.gotoOnly then
			local t = ticksFor(i)
			return (t and t.arrived) and "done" or "todo"
		end
		if s.tip then return "tip" end
		return "manual"
	end
	if todo == 0 then return "done" end
	return "todo"
end
E.StepState = stepState

---------------------------------------------------------------------------
-- Avancement
---------------------------------------------------------------------------

local function alongTarget(i)
	local g = E.guide
	local s = g.steps[i]
	local cw = s.cw
	if cw == "next" then
		for j = i + 1, #g.steps do
			if not g.steps[j].cw and not g.steps[j].tip then return j end
		end
		return #g.steps
	elseif cw == "self" then
		return #g.steps
	elseif cw then
		return g.labels[cw] or (i + 1)
	end
	return nil
end

local function isPassive(s)
	return s.cw or s.tip
end

-- Avance jusqu'à la première étape à faire
local function advance()
	local db = charDB()
	local g = E.guide
	local n = #g.steps
	local i = db.idx or 1
	while i <= n do
		local s = g.steps[i]
		if not isPassive(s) then
			local st = stepState(i)
			if st == "todo" or st == "manual" then break end
			if db.hold == i then break end
		end
		i = i + 1
	end
	db.idx = i
	return i
end

-- Construit ce qu'il faut afficher : étape courante + étapes « en chemin »
local function buildView()
	local g = E.guide
	local db = charDB()
	local cur = db.idx
	local view = { guide = g, idx = cur, total = #g.steps, along = {} }
	if cur > #g.steps then
		view.finished = true
		E.view = view
		return view
	end
	view.step = g.steps[cur]
	view.state = stepState(cur)
	-- conseils et étapes « en chemin » déjà atteints
	for j = cur - 1, math.max(1, cur - 40), -1 do
		local s = g.steps[j]
		if s.cw then
			local t = alongTarget(j)
			if t and t >= cur and stepApplies(s) and not markOf(j) then
				local st = stepState(j)
				if st ~= "done" and st ~= "skip" then
					table.insert(view.along, 1, j)
				end
			end
		end
	end
	-- conseils placés juste avant l'étape courante
	for j = cur - 1, math.max(1, cur - 6), -1 do
		local s = g.steps[j]
		if s.tip then
			if stepApplies(s) and not markOf(j) then table.insert(view.along, 1, j) end
		elseif not s.cw then
			break
		end
	end
	E.view = view
	return view
end

function E.Refresh(force)
	if not E.guide then return end
	E.RefreshPlayer()
	local before = charDB().idx
	local idx = advance()
	if idx > #E.guide.steps then
		local nextId = E.NextGuideId(E.guide.meta)
		if nextId and nextId ~= E.guide.id then
			E.Print("route terminée ! Suite : " .. E.Expand(E.GetMeta(nextId).name or nextId))
			E.OpenGuide(nextId, 1)
			return
		end
	end
	buildView()
	if E.UpdateUI then E.UpdateUI(force or before ~= idx) end
	if E.UpdateArrowTarget then E.UpdateArrowTarget() end
end

local pending = false
function E.RequestRefresh()
	if pending then return end
	pending = true
	C_Timer.After(0.15, function()
		pending = false
		E.Refresh()
	end)
end

-- Bouton ▶ : valide l'étape affichée et passe à la suivante
function E.NextStep()
	local db = charDB()
	if not E.guide then return end
	local i = db.idx
	if i <= #E.guide.steps then
		local st = stepState(i)
		setMark(i, (st == "done" or st == "manual") and "d" or "s")
	end
	db.hold = nil
	db.idx = i + 1
	E.Refresh(true)
end

-- Bouton ◀ : revient à l'étape précédente (navigation manuelle)
function E.PrevStep()
	local db = charDB()
	if not E.guide then return end
	local i = math.min(db.idx, #E.guide.steps + 1) - 1
	while i >= 1 do
		local s = E.guide.steps[i]
		if not isPassive(s) and stepApplies(s) then break end
		i = i - 1
	end
	if i < 1 then return end
	local marks = db.marks[db.guide]
	if marks then marks[i] = nil end
	db.idx = i
	db.hold = i
	E.Refresh(true)
end

-- Clic sur une ligne : coche/décoche un objectif manuel
function E.ToggleGoal(stepIdx, gi)
	local t = ticksFor(stepIdx, true)
	t[gi] = not t[gi] or nil
	E.Refresh(true)
end

-- Coche les objectifs d'un type donné sur les étapes affichées (événements du jeu)
local function tickKind(kind)
	local v = E.view
	if not v or not v.step then return end
	local changed = false
	local function tick(i)
		local s = E.guide.steps[i]
		for gi, g in ipairs(s.g) do
			if g.k == kind and E.Applies(g.c) then
				local t = ticksFor(i, true)
				if not t[gi] then
					t[gi] = true
					changed = true
				end
			end
		end
	end
	tick(v.idx)
	for _, j in ipairs(v.along) do tick(j) end
	if changed then E.RequestRefresh() end
end
E.TickKind = tickKind

-- Appelé par la flèche : point atteint
function E.MarkArrived(stepIdx, gi, isLast)
	local t = ticksFor(stepIdx, true)
	local changed = false
	if gi and not t[gi] then
		t[gi] = true
		changed = true
	end
	if isLast and not t.arrived then
		t.arrived = true
		changed = true
	end
	if changed then E.RequestRefresh() end
end

function E.GetTicks(stepIdx) return ticksFor(stepIdx) end
function E.IsBlocking(g) return isBlocking(g) end

---------------------------------------------------------------------------
-- Acceptation / rendu automatiques des quêtes de la route
---------------------------------------------------------------------------

local function visibleQuestGoals(kind)
	local set = {}
	local v = E.view
	if not v or not v.step then return set end
	local function scan(i)
		for _, g in ipairs(E.guide.steps[i].g) do
			if g.k == kind and g.q and E.Applies(g.c) then set[g.q] = true end
		end
	end
	scan(v.idx)
	for _, j in ipairs(v.along) do scan(j) end
	-- les quelques étapes suivantes aussi : on prend souvent plusieurs quêtes au même PNJ
	for j = v.idx + 1, math.min(#E.guide.steps, v.idx + 4) do scan(j) end
	return set
end

local function questIdOfFrame()
	return safe(GetQuestID)
end

local function onQuestDetail()
	if not EnvolDB.autoQuest or IsShiftKeyDown() then return end
	local q = questIdOfFrame()
	if q and visibleQuestGoals("a")[q] then
		if AcceptQuest then pcall(AcceptQuest) end
	end
end

local function onQuestProgress()
	if not EnvolDB.autoQuest or IsShiftKeyDown() then return end
	local q = questIdOfFrame()
	if q and visibleQuestGoals("t")[q] and IsQuestCompletable and safe(IsQuestCompletable) then
		pcall(CompleteQuest)
	end
end

local function onQuestComplete()
	if not EnvolDB.autoQuest or IsShiftKeyDown() then return end
	local q = questIdOfFrame()
	if q and visibleQuestGoals("t")[q] then
		local choices = safe(GetNumQuestChoices) or 0
		if choices <= 1 then
			pcall(GetQuestReward, choices)
		elseif EnvolDB.autoReward and EnvolDB.gear and E.Gear then
			-- les objets des récompenses arrivent parfois un peu après la fenêtre
			local function pick(tries)
				local best, _, _, pending = E.Gear.BestReward()
				if pending and tries < 5 then
					C_Timer.After(0.3, function() pick(tries + 1) end)
				elseif best then
					pcall(GetQuestReward, best)
				end
			end
			pick(0)
		end
	end
end

local function onGossipShow()
	if not EnvolDB.autoQuest or IsShiftKeyDown() then return end
	if not (C_GossipInfo and C_GossipInfo.GetActiveQuests) then return end
	local turn, take = visibleQuestGoals("t"), visibleQuestGoals("a")
	local ok, active = pcall(C_GossipInfo.GetActiveQuests)
	if ok and type(active) == "table" then
		for _, info in ipairs(active) do
			if info.questID and turn[info.questID] and info.isComplete then
				pcall(C_GossipInfo.SelectActiveQuest, info.questID)
				return
			end
		end
	end
	local ok2, avail = pcall(C_GossipInfo.GetAvailableQuests)
	if ok2 and type(avail) == "table" then
		for _, info in ipairs(avail) do
			if info.questID and take[info.questID] then
				pcall(C_GossipInfo.SelectAvailableQuest, info.questID)
				return
			end
		end
	end
end

---------------------------------------------------------------------------
-- Événements
---------------------------------------------------------------------------

local onTaxi = false
local wasDead = false

local ev = CreateFrame("Frame")
E.eventFrame = ev
local handlers = {}

handlers.QUEST_TURNED_IN = function(q)
	q = readable(q)
	if q then E.turnedIn[q] = true end
	E.RequestRefresh()
end
handlers.MERCHANT_SHOW = function() tickKind("v") end
handlers.TRAINER_SHOW = function() tickKind("tn") end
handlers.TAXIMAP_OPENED = function() tickKind("fp") end
handlers.HEARTHSTONE_BOUND = function() tickKind("home") end
handlers.PLAYER_CONTROL_LOST = function()
	C_Timer.After(0.5, function() if safe(UnitOnTaxi, "player") then onTaxi = true end end)
end
handlers.PLAYER_CONTROL_GAINED = function()
	if onTaxi then
		onTaxi = false
		tickKind("fly")
	end
end
handlers.UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spell)
	if unit ~= "player" then return end
	spell = readable(spell)
	if spell == 8690 then tickKind("hs") end
end
handlers.PLAYER_DEAD = function() wasDead = true end
handlers.PLAYER_UNGHOST = function()
	if wasDead then wasDead = false; tickKind("die") end
end
handlers.PLAYER_ALIVE = function()
	if wasDead and not safe(UnitIsGhost, "player") then wasDead = false; tickKind("die") end
end
handlers.PLAYER_LEVEL_UP = function(level)
	E.player.level = readable(level) or E.player.level
	E.ResetConditionCache()
	E.RequestRefresh()
end
handlers.QUEST_DETAIL = onQuestDetail
handlers.QUEST_PROGRESS = onQuestProgress
handlers.QUEST_COMPLETE = onQuestComplete
handlers.GOSSIP_SHOW = onGossipShow

local refreshEvents = {
	"QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "UNIT_QUEST_LOG_CHANGED",
	"PLAYER_XP_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "ZONE_CHANGED",
	"ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
}

function E.StartEvents()
	for name in pairs(handlers) do pcall(ev.RegisterEvent, ev, name) end
	for _, name in ipairs(refreshEvents) do pcall(ev.RegisterEvent, ev, name) end
	ev:SetScript("OnEvent", function(_, event, ...)
		local h = handlers[event]
		if h then
			h(...)
		else
			E.RequestRefresh()
		end
	end)
	-- filet de sécurité : certaines choses ne déclenchent aucun événement
	C_Timer.NewTicker(2, function() E.RequestRefresh() end)
end

---------------------------------------------------------------------------
-- Démarrage
---------------------------------------------------------------------------

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
	EnvolDB = EnvolDB or {}
	EnvolChar = EnvolChar or {}
	local d = EnvolDB
	if d.arrow == nil then d.arrow = true end
	if d.autoQuest == nil then d.autoQuest = true end
	if d.groupQuests == nil then d.groupQuests = false end
	d.scale = d.scale or 1
	d.arrowScale = d.arrowScale or 1
	d.source = d.source or "rxp"
	local c = EnvolChar
	c.ticks = c.ticks or {}
	c.marks = c.marks or {}
	indexMetas()
	E.RefreshPlayer()
	E.CheckVersion()
	if E.CreateUI then E.CreateUI() end
	if E.CreateArrow then E.CreateArrow() end
	E.StartEvents()
	-- les infos de faction peuvent arriver un peu après la connexion
	C_Timer.After(1, function()
		E.RefreshPlayer()
		local id = c.guide
		if id and metaById[id] and E.GuideFits(metaById[id]) then
			E.OpenGuide(id, c.idx)
		else
			local start = E.PickStartGuide()
			if start then
				E.OpenGuide(start, 1)
				E.Print("route choisie : " .. E.Expand(metaById[start].name) .. " — tapez /envol pour le menu.")
			else
				E.Print("aucune route trouvée pour ce personnage.")
			end
		end
	end)
end)
