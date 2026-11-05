-- Envol : builds de talents (Forever) et apprentissage automatique.
-- Les talents de Forever sont un arbre C_Traits par classe. Un build est une liste ordonnée de
-- {nœud, rang} : à chaque point disponible, on prend le premier choix du build pas encore appris.
-- Rien n'est jamais désappris : Envol ne fait que dépenser les points libres.

local E = Envol
local safe, readable = E.Safe, E.Readable
local T = {}
E.Talents = T

local function data() return EnvolData.talents and EnvolData.talents[E.player.class] end

local function configID()
	if C_ClassTalents and C_ClassTalents.GetActiveConfigID then return safe(C_ClassTalents.GetActiveConfigID) end
	return nil
end

-- Les identifiants de nœuds peuvent changer entre deux versions du jeu : on les retrouve par leur sort.
local nodeMap = nil
local function liveNode(d, cfg, id)
	if not nodeMap then
		nodeMap = {}
		local bySpell = {}
		local ok, list = pcall(C_Traits.GetTreeNodes, d.tree)
		if ok and type(list) == "table" then
			for _, nid in ipairs(list) do
				local okn, info = pcall(C_Traits.GetNodeInfo, cfg, nid)
				local entry = okn and info and info.entryIDs and info.entryIDs[1]
				local okE, e = pcall(C_Traits.GetEntryInfo, cfg, entry)
				local okD, def = okE and e and e.definitionID and pcall(C_Traits.GetDefinitionInfo, e.definitionID)
				local spell = okD and def and readable(def.spellID)
				if spell then bySpell[spell] = nid end
			end
		end
		for nid, n in pairs(d.nodes) do
			nodeMap[nid] = bySpell[n[3]] or nid
		end
	end
	return nodeMap[id] or id
end

function T.Invalidate() nodeMap = nil end

local function nodeInfo(cfg, nid)
	local ok, info = pcall(C_Traits.GetNodeInfo, cfg, nid)
	if ok and type(info) == "table" then return info end
	return nil
end

-- Points de talent disponibles
local function freePoints(d, cfg)
	if C_Traits and C_Traits.GetTreeCurrencyInfo then
		local ok, list = pcall(C_Traits.GetTreeCurrencyInfo, cfg, d.tree, false)
		if ok and type(list) == "table" and list[1] then
			return readable(list[1].quantity) or 0
		end
	end
	return 0
end

function T.Builds()
	local d = data()
	return d and d.builds or {}
end

function T.Current()
	local d = data()
	if not d then return nil end
	local key = EnvolChar.talentBuild
	for _, b in ipairs(d.builds) do
		if b.key == key then return b, d end
	end
	return nil, d
end

-- Nom du talent (celui du client, donc en français), sinon le nom anglais de la source
function T.NodeName(d, id)
	local n = d.nodes[id]
	if not n then return "?" end
	return (E.SpellName(n[3])) or n[5]
end

-- Prochain choix du build pas encore appris : index dans picks, nœud, rang voulu
function T.NextPick()
	local b, d = T.Current()
	if not b then return nil end
	local cfg = configID()
	if not cfg then return nil end
	for i, p in ipairs(b.picks) do
		local nid = liveNode(d, cfg, p[1])
		local info = nodeInfo(cfg, nid)
		local rank = info and (readable(info.currentRank) or readable(info.activeRank)) or 0
		if rank < p[2] then return i, p[1], p[2], nid, info end
	end
	return nil
end

-- Apprend les points libres en suivant le build. Renvoie le nombre de talents appris.
local busy = false
function T.Apply()
	if busy or not EnvolDB.autoTalents then return 0 end
	local b, d = T.Current()
	if not b or not (C_Traits and C_Traits.PurchaseRank) then return 0 end
	if safe(InCombatLockdown) then T.pending = true; return 0 end
	local cfg = configID()
	if not cfg then return 0 end
	busy = true
	local learned, names = 0, {}
	for _ = 1, 60 do
		if freePoints(d, cfg) <= 0 then break end
		local i, id, rank, nid, info = T.NextPick()
		if not i then break end
		if info and info.canPurchaseRank == false then break end -- pas encore accessible (palier)
		local ok, res = pcall(C_Traits.PurchaseRank, cfg, nid)
		if not ok or res == false then break end
		learned = learned + 1
		names[#names + 1] = string.format("%s (%d/%d)", T.NodeName(d, id), rank, d.nodes[id][2])
	end
	if learned > 0 then
		local ok = pcall(C_Traits.CommitConfig, cfg)
		if not ok and C_ClassTalents and C_ClassTalents.CommitConfig then pcall(C_ClassTalents.CommitConfig, cfg) end
		E.Print("talent" .. (learned > 1 and "s" or "") .. " appris : " .. table.concat(names, ", "))
		local lvl = E.player.level or 0
		local note = b.notes and b.notes[lvl]
		if note then E.Print("|cff9aa4ad" .. note .. "|r") end
	end
	busy = false
	T.pending = nil
	if E.UpdateUI then E.UpdateUI() end
	return learned
end

-- Ligne affichée dans la fenêtre quand un point attend (sans apprentissage automatique)
function T.Hint()
	local b, d = T.Current()
	if not b then return nil end
	local cfg = configID()
	if not cfg or freePoints(d, cfg) <= 0 then return nil end
	local i, id, rank = T.NextPick()
	if not i then return nil end
	return string.format("Talent à prendre (%s) : %s, rang %d", b.nom, T.NodeName(d, id), rank)
end

-- Réglages : Aucun -> build 1 -> build 2 -> build 3 -> Aucun
function T.Cycle()
	local list = T.Builds()
	local cur = EnvolChar.talentBuild
	local nextKey = list[1] and list[1].key
	for i, b in ipairs(list) do
		if b.key == cur then nextKey = list[i + 1] and list[i + 1].key or nil end
	end
	EnvolChar.talentBuild = nextKey
	T.Invalidate()
	return T.Label()
end

function T.Label()
	local b = T.Current()
	if not b then return "Aucun" end
	return b.nom .. " (" .. b.split .. ")"
end

-- Liste lisible du build (commande /envol talents)
function T.Report()
	local b, d = T.Current()
	if not b then
		E.Print("aucun build de talents choisi. /envol réglages → « Build de talents ».")
		return
	end
	E.Print("build " .. b.nom .. " (" .. b.split .. ") — apprentissage automatique : " ..
		(EnvolDB.autoTalents and "activé" or "désactivé"))
	local i = T.NextPick()
	if i then
		local p = b.picks[i]
		E.Print("prochain talent : " .. T.NodeName(d, p[1]) .. ", rang " .. p[2] .. " (choix " .. i .. "/" .. #b.picks .. ")")
	else
		E.Print("tous les talents du build sont appris.")
	end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		if EnvolDB.autoTalents == nil then EnvolDB.autoTalents = false end
		for _, name in ipairs({ "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED", "PLAYER_REGEN_ENABLED",
			"PLAYER_ENTERING_WORLD", "TRAIT_TREE_CURRENCY_INFO_UPDATED" }) do
			pcall(ev.RegisterEvent, ev, name)
		end
		return
	end
	if event == "PLAYER_REGEN_ENABLED" and not T.pending then return end
	-- laisse le jeu finir sa propre mise à jour avant d'apprendre
	C_Timer.After(1, function()
		if EnvolDB.autoTalents then T.Apply() elseif E.UpdateUI then E.UpdateUI() end
	end)
end)
