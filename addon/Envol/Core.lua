-- Envol : guide de leveling en français pour WoW Forever.
-- Noyau : registre des routes, conditions, fonctions de compatibilité.

EnvolData = EnvolData or { metas = {}, loaders = {} }

-- Les fichiers Data/ appellent EnvolData.Add(meta, chargeur) pour chaque route.
-- Les étapes ne sont décodées qu'au moment où la route est ouverte.
function EnvolData.Add(meta, loader)
	local list = EnvolData.metas
	list[#list + 1] = meta
	EnvolData.loaders[meta.id] = loader
end

Envol = Envol or {}
local E = Envol

E.VERSION = "1.0.0"
E.ADDON_COLOR = "|cff4fc3f7"

---------------------------------------------------------------------------
-- Valeurs « secrètes » (restrictions de combat de type Midnight sur Forever)
---------------------------------------------------------------------------

local function isSecret(v)
	return v ~= nil and issecretvalue ~= nil and issecretvalue(v) and true or false
end

function E.Readable(v)
	if isSecret(v) then return nil end
	return v
end
local readable = E.Readable

local function safe(fn, ...)
	if not fn then return nil end
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok then return nil end
	return readable(a), readable(b), readable(c), readable(d)
end
E.Safe = safe

---------------------------------------------------------------------------
-- Joueur
---------------------------------------------------------------------------

E.player = {}

function E.RefreshPlayer()
	local p = E.player
	local _, class = UnitClass("player")
	local _, race = UnitRace("player")
	p.class = class and string.upper(class) or p.class
	p.race = race or p.race
	if p.race == "Undead" then p.race = "Scourge" end
	local fac = safe(UnitFactionGroup, "player")
	local newFac = (fac == "Alliance" or fac == "Horde") and fac or nil
	if newFac ~= p.faction then
		p.faction = newFac
		if E.ResetConditionCache then E.ResetConditionCache() end
	end
	p.level = safe(UnitLevel, "player") or p.level or 1
end

-- Niveau avec fraction : 12.5 = à mi-chemin du niveau 12.
function E.LevelFrac()
	local lvl = safe(UnitLevel, "player") or E.player.level or 1
	local xp = safe(UnitXP, "player") or 0
	local max = safe(UnitXPMax, "player") or 1
	if max <= 0 then max = 1 end
	return lvl + xp / max, lvl, xp, max
end

---------------------------------------------------------------------------
-- Conditions
-- Chaîne au format RestedXP : "Warrior/Shaman", "Alliance !Hunter",
-- "Orc Hunter/Troll Hunter" ('/' = ou, espace = et, '!' = non, nombre = niveau mini)
-- ou table Polestar : { cl = {classes}, ra = {races}, fa = {factions} }
---------------------------------------------------------------------------

local condCache = {}

local function tokenMatches(tok)
	local p = E.player
	if tok == "Undead" then tok = "Scourge" end
	local up = string.upper(tok)
	local n = tonumber(tok)
	if n then return (p.level or 1) >= n end
	if up == p.class then return true end
	if tok == p.race then return true end
	if tok == p.faction then return true end
	-- personnage encore neutre (Skyborne avant le choix de faction) : les deux factions conviennent
	if not p.faction and (tok == "Alliance" or tok == "Horde") then return true end
	if up == "FOREVER" then return true end
	return false
end

local function evalString(s)
	for alt in string.gmatch(s, "[^/]+") do
		local ok, any = true, false
		for entry in string.gmatch(alt, "!?[%w_]+") do
			any = true
			local neg = false
			if string.sub(entry, 1, 1) == "!" then
				neg = true
				entry = string.sub(entry, 2)
			end
			if tokenMatches(entry) == neg then
				ok = false
				break
			end
		end
		if ok and any then return true end
	end
	return false
end

local function inList(list, v)
	for i = 1, #list do
		if list[i] == v then return true end
	end
	return false
end

function E.Applies(c)
	if c == nil then return true end
	if type(c) == "string" then
		-- les conditions qui dépendent du niveau ne sont pas mises en cache
		if string.find(c, "%d") then return evalString(c) end
		local v = condCache[c]
		if v == nil then
			v = evalString(c)
			condCache[c] = v
		end
		return v
	end
	local p = E.player
	if c.cl and not inList(c.cl, p.class) then return false end
	if c.ra then
		local race = p.race
		if not (inList(c.ra, race) or (race == "Scourge" and inList(c.ra, "Undead"))) then return false end
	end
	if c.fa and not inList(c.fa, p.faction) then return false end
	return true
end

function E.ResetConditionCache()
	condCache = {}
end

-- Une route convient-elle à ce personnage ?
function E.GuideFits(meta)
	local p = E.player
	if meta.faction and p.faction and meta.faction ~= p.faction then return false end
	if meta.races then
		local ok = inList(meta.races, p.race) or (p.race == "Scourge" and inList(meta.races, "Undead"))
		if not ok then return false end
	end
	if meta.cond and not E.Applies(meta.cond) then return false end
	return true
end

---------------------------------------------------------------------------
-- Quêtes
---------------------------------------------------------------------------

E.turnedIn = {}

function E.IsQuestDone(q)
	if E.turnedIn[q] then return true end
	if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
		return safe(C_QuestLog.IsQuestFlaggedCompleted, q) and true or false
	end
	if IsQuestFlaggedCompleted then return safe(IsQuestFlaggedCompleted, q) and true or false end
	return false
end

function E.IsOnQuest(q)
	if C_QuestLog and C_QuestLog.IsOnQuest then
		return safe(C_QuestLog.IsOnQuest, q) and true or false
	end
	if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
		local i = safe(C_QuestLog.GetLogIndexForQuestID, q)
		return i ~= nil and i > 0
	end
	if GetQuestLogIndexByID then
		local i = safe(GetQuestLogIndexByID, q)
		return i ~= nil and i > 0
	end
	return false
end

function E.IsQuestReady(q)
	if not E.IsOnQuest(q) then return false end
	if C_QuestLog then
		if C_QuestLog.ReadyForTurnIn and safe(C_QuestLog.ReadyForTurnIn, q) then return true end
		if C_QuestLog.IsComplete and safe(C_QuestLog.IsComplete, q) then return true end
	end
	return false
end

function E.GetObjectives(q)
	if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return nil end
	local ok, raw = pcall(C_QuestLog.GetQuestObjectives, q)
	if not ok or type(raw) ~= "table" or #raw == 0 then return nil end
	return raw
end

function E.QuestName(q)
	local n = EnvolData.questNames and EnvolData.questNames[q]
	if n then return n end
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		n = safe(C_QuestLog.GetTitleForQuestID, q)
		if n and n ~= "" then return n end
	end
	return "quête n°" .. tostring(q)
end

function E.ItemCount(id)
	local n
	if C_Item and C_Item.GetItemCount then
		n = safe(C_Item.GetItemCount, id)
	end
	if n == nil and GetItemCount then n = safe(GetItemCount, id) end
	return n or 0
end

function E.ItemName(id)
	local n
	if C_Item and C_Item.GetItemNameByID then n = safe(C_Item.GetItemNameByID, id) end
	if not n and GetItemInfo then n = safe(GetItemInfo, id) end
	return n
end

function E.SpellName(id)
	local n
	if C_Spell and C_Spell.GetSpellName then n = safe(C_Spell.GetSpellName, id) end
	if not n and GetSpellInfo then n = safe(GetSpellInfo, id) end
	return n
end

function E.KnowsSpell(id)
	if IsPlayerSpell and safe(IsPlayerSpell, id) then return true end
	if IsSpellKnown and safe(IsSpellKnown, id) then return true end
	return false
end

function E.AreaName(id)
	if C_Map and C_Map.GetAreaInfo then return safe(C_Map.GetAreaInfo, id) end
	return nil
end

function E.Money()
	return safe(GetMoney) or 0
end

---------------------------------------------------------------------------
-- Divers
---------------------------------------------------------------------------

function E.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(E.ADDON_COLOR .. "Envol|r : " .. tostring(msg))
end

-- Noms de lieux résolus par le client (donc en français) : "{area:17|The Barrens}"
local placeCache = {}
local function placeName(kind, id, fallback)
	local key = kind .. id
	local n = placeCache[key]
	if n then return n end
	id = tonumber(id)
	if kind == "area" then
		n = E.AreaName(id)
	elseif C_Map and C_Map.GetMapInfo then
		local info = safe(C_Map.GetMapInfo, id)
		n = type(info) == "table" and info.name or nil
	end
	if not n or n == "" then return fallback ~= "" and fallback or "?" end
	placeCache[key] = n
	return n
end

function E.Expand(text)
	if not text or not string.find(text, "{", 1, true) then return text end
	return (string.gsub(text, "{(%a+):(%d+)|?([^}]*)}", placeName))
end

---------------------------------------------------------------------------
-- Version et mises à jour
---------------------------------------------------------------------------

function E.BuildInfo()
	return EnvolData.build or { version = "dev", date = "?" }
end

-- "2026-11-04" -> nombre de jours écoulés (nil si date illisible)
function E.DaysSince(d)
	local y, m, j = string.match(d or "", "^(%d+)-(%d+)-(%d+)$")
	if not y then return nil end
	local t = time({ year = tonumber(y), month = tonumber(m), day = tonumber(j), hour = 12 })
	return math.floor((time() - t) / 86400)
end

function E.FormatDate(d)
	local y, m, j = string.match(d or "", "^(%d+)-(%d+)-(%d+)$")
	if not y then return d or "?" end
	return j .. "/" .. m .. "/" .. y
end

function E.CheckVersion()
	local b = E.BuildInfo()
	local last = EnvolDB.lastVersion
	if last and last ~= b.version then
		E.Print("mis à jour ! Version " .. b.version .. ", routes du " .. E.FormatDate(b.date) .. ".")
	end
	EnvolDB.lastVersion = b.version
	local age = E.DaysSince(b.date)
	if age and age >= 14 then
		E.Print("vos routes datent du " .. E.FormatDate(b.date) .. " (" .. age .. " jours). " ..
			"Lancez « Mettre à jour Envol » sur votre PC pour récupérer les dernières.")
	end
end

-- 12345 -> "12 345"
function E.FormatNumber(n)
	local s = tostring(math.floor((n or 0) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^%s+", ""))
end
