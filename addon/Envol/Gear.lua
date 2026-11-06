-- Envol : conseils d'équipement (à la manière de Pawn).
-- Chaque objet reçoit un score = somme (statistique × poids de votre spé à votre niveau),
-- comparé à ce que vous portez dans le même emplacement.

local E = Envol
local safe, readable = E.Safe, E.Readable
local G = {}
E.Gear = G

local DATA -- EnvolData.gear, lu à la connexion

-- Statistiques renvoyées par le client -> clés des tables de poids
local STATS = {
	ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
	ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi", RESISTANCE0_NAME = "armor",
	ITEM_MOD_HEALTH_SHORT = "health", ITEM_MOD_MANA_SHORT = "mana",
	ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
	ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
	ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp", ITEM_MOD_SPELL_POWER_SHORT = "sp",
	ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
	ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_POWER_REGEN0_SHORT = "mp5",
	ITEM_MOD_HEALTH_REGEN_SHORT = "hp5", ITEM_MOD_HEALTH_REGENERATION_SHORT = "hp5",
	ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "crit",
	ITEM_MOD_HIT_RATING_SHORT = "hit", ITEM_MOD_HIT_MELEE_RATING_SHORT = "hit",
	ITEM_MOD_CRIT_SPELL_RATING_SHORT = "spellCrit", ITEM_MOD_HIT_SPELL_RATING_SHORT = "spellHit",
	ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "defense", ITEM_MOD_DODGE_RATING_SHORT = "dodge",
	ITEM_MOD_PARRY_RATING_SHORT = "parry", ITEM_MOD_BLOCK_RATING_SHORT = "block",
	ITEM_MOD_BLOCK_VALUE_SHORT = "blockValue",
}

-- Type d'équipement -> emplacements du personnage
local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_RELIC = { 18 },
}
local RANGED = { INVTYPE_RANGED = true, INVTYPE_THROWN = true, INVTYPE_RANGEDRIGHT = true }
local OFFHAND = { INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }

local function fmtPct(p)
	local s = string.format("%+.1f", p):gsub("%.", ",")
	return s .. " %"
end

---------------------------------------------------------------------------
-- Spécialisation
---------------------------------------------------------------------------

local function classInfo()
	return DATA and DATA.classes[E.player.class]
end

local function pointsIn(i)
	local S = C_SpecializationInfo
	if S and S.GetSpecializationInfo then
		local ok, _, _, _, _, _, _, points = pcall(S.GetSpecializationInfo, i)
		points = ok and readable(points)
		if type(points) == "number" then return points end
	end
	if GetTalentTabInfo then
		local r = { pcall(GetTalentTabInfo, i) }
		if r[1] then
			if type(r[4]) == "number" then return r[4] end -- Classic : nom, icône, points
			if type(r[6]) == "number" then return r[6] end
		end
	end
	return 0
end

-- -> clé de spé, nom français, détectée automatiquement ?
function G.Spec()
	local info = classInfo()
	if not info then return nil end
	local forced = EnvolChar.gearSpec
	for _, s in ipairs(info.specs) do
		if s.key == forced then return s.key, s.fr, false end
	end
	local build = EnvolChar.talentBuild
	for _, s in ipairs(info.specs) do
		if s.key == build then return s.key, s.fr, true end
	end
	local S = C_SpecializationInfo
	if S and S.IsSpecSelectionEnabled and S.GetSpecialization then
		local _, _, classID = UnitClass("player")
		local ok, enabled = pcall(S.IsSpecSelectionEnabled, classID)
		if ok and readable(enabled) then
			local ok2, idx = pcall(S.GetSpecialization)
			idx = ok2 and readable(idx)
			if type(idx) == "number" and info.specs[idx] then
				return info.specs[idx].key, info.specs[idx].fr, true
			end
		end
	end
	local best, bestPts = nil, 0
	for i, s in ipairs(info.specs) do
		local p = pointsIn(i)
		if p > bestPts then best, bestPts = s, p end
	end
	if not best then
		for _, s in ipairs(info.specs) do
			if s.key == info.default then best = s end
		end
	end
	return best.key, best.fr, true
end

local weightsCache = {}
function G.Weights()
	local spec = G.Spec()
	local class = E.player.class
	local level = E.player.level or 1
	local key = (class or "?") .. spec .. level
	local w = weightsCache[key]
	if w then return w end
	local bands = DATA and DATA.bands[class] and DATA.bands[class][spec]
	if not bands then return nil end
	local band = bands[#bands]
	for _, b in ipairs(bands) do
		if level <= b.upTo then band = b; break end
	end
	w = {}
	for k, v in pairs(band.w) do w[k] = v end
	-- Combat farouche : les formes frappent avec le DPS de l'arme (14 PA = 1 DPS)
	if not w.dps and spec == "feral" then w.dps = 14 * (w.ap or 0) end
	weightsCache[key] = w
	return w
end

function G.Invalidate()
	weightsCache = {}
	G.scoreCache = {}
	G.RequestScan()
end

---------------------------------------------------------------------------
-- Objets
---------------------------------------------------------------------------

local function itemInfo(link)
	if not (C_Item and C_Item.GetItemInfo) and not GetItemInfo then return nil end
	local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local ok, name, _, quality, _, minLevel, _, _, _, equipLoc, _, sellPrice, classID, subclassID = pcall(f, link)
	if not ok or not name then return nil end
	return { equipLoc = equipLoc, classID = classID, sub = subclassID, minLevel = minLevel or 0,
		sell = sellPrice or 0, quality = quality }
end

local function itemStats(link)
	local f = (C_Item and C_Item.GetItemStats) or GetItemStats
	if not f then return nil end
	local ok, t = pcall(f, link)
	if ok and type(t) == "table" then return t end
	return nil
end

-- Votre classe peut-elle le porter ? -> vrai, ou faux + raison
function G.Usable(info)
	local prof = DATA and DATA.prof[E.player.class]
	if not prof or not info then return false, "inconnu" end
	if info.classID == 4 then -- armure
		local sub = info.sub
		if sub == 0 then return true end
		if sub >= 1 and sub <= 4 then
			local max = ((E.player.level or 1) >= 40 and prof.armor40) or prof.armor
			if sub <= max then return true end
			if prof.armor40 and sub <= prof.armor40 then return false, "portable au niveau 40" end
			return false, "type d'armure non portable"
		end
		if sub == 6 then return prof.shield and true or false, "bouclier non portable" end
		if sub == 7 or sub == 8 or sub == 9 then return prof.relic == sub, "relique d'une autre classe" end
		return false, "non portable"
	elseif info.classID == 2 then -- arme
		if prof.weapons[tostring(info.sub)] then return true end
		return false, "arme non maîtrisée par votre classe"
	end
	return false, nil
end

local function canDualWield()
	local prof = DATA and DATA.prof[E.player.class]
	return prof and prof.dw and (E.player.level or 1) >= prof.dw
end

G.scoreCache = {}
-- Score d'un objet ; asSlot = emplacement où il serait porté (main gauche : DPS compté à moitié)
function G.Score(link, asSlot)
	if not link then return 0 end
	local ck = link .. "#" .. (asSlot or 0)
	local c = G.scoreCache[ck]
	if c then return c end
	local w = G.Weights()
	local stats = itemStats(link)
	local info = itemInfo(link)
	if not (w and stats and info) then return nil end
	local score = 0
	for k, v in pairs(stats) do
		local key = STATS[k]
		if key and type(v) == "number" then
			if key == "dps" then
				if RANGED[info.equipLoc] then
					score = score + v * (w.rdps or 0)
				else
					local factor = (asSlot == 17 or info.equipLoc == "INVTYPE_WEAPONOFFHAND") and 0.5 or 1
					score = score + v * (w.dps or 0) * factor
				end
			else
				score = score + v * (w[key] or 0)
			end
		end
	end
	G.scoreCache[ck] = score
	return score
end

local function equippedLink(slot)
	return GetInventoryItemLink and readable(GetInventoryItemLink("player", slot)) or nil
end

local function isTwoHander(link)
	local info = link and itemInfo(link)
	return info and info.equipLoc == "INVTYPE_2HWEAPON"
end

-- Compare un objet à l'équipement porté.
-- -> { usable, reason, score, current, delta, pct, upgrade, slot, needLevel }
function G.Compare(link)
	local info = itemInfo(link)
	if not info then return nil end
	local slots = SLOTS[info.equipLoc]
	if not slots then return nil end
	local r = {}
	local ok, why = G.Usable(info)
	r.usable, r.reason = ok, why
	if not ok then return r end
	if (info.minLevel or 0) > (E.player.level or 1) then r.needLevel = info.minLevel end
	if info.equipLoc == "INVTYPE_WEAPON" and not canDualWield() then slots = { 16 } end
	if info.equipLoc == "INVTYPE_WEAPONOFFHAND" and not canDualWield() then
		r.usable, r.reason = false, "ambidextrie pas encore apprise"
		return r
	end
	local new
	if info.equipLoc == "INVTYPE_2HWEAPON" then
		new = G.Score(link, 16)
		local mh, oh = equippedLink(16), equippedLink(17)
		local cur = (mh and G.Score(mh, 16) or 0) + (oh and G.Score(oh, 17) or 0)
		r.score, r.current, r.slot = new, cur, 16
	elseif OFFHAND[info.equipLoc] and isTwoHander(equippedLink(16)) then
		r.score = G.Score(link, 17)
		r.note = "à comparer avec une arme à une main"
		return r
	else
		local bestSlot, cur
		for _, s in ipairs(slots) do
			local l = equippedLink(s)
			if l == link then
				r.equipped = true
			end
			local sc = l and G.Score(l, s) or 0
			if not cur or sc < cur then cur, bestSlot = sc, s end
		end
		new = G.Score(link, bestSlot)
		r.score, r.current, r.slot = new, cur, bestSlot
	end
	if not r.score or not r.current then return r end
	r.delta = r.score - r.current
	if r.current > 0 then
		r.pct = r.delta / r.current * 100
	else
		r.pct = r.score > 0 and 100 or 0
	end
	r.upgrade = not r.equipped and r.delta > 0.05 and (r.pct or 0) >= 0.5
	return r
end

---------------------------------------------------------------------------
-- Infobulles
---------------------------------------------------------------------------

local function tooltipLines(tt, link)
	if not EnvolDB.gear or not link then return end
	local r = G.Compare(link)
	if not r then return end
	local _, specName = G.Spec()
	local head = E.ADDON_COLOR .. "Envol|r" .. (specName and (" · " .. specName) or "") .. " : "
	if not r.usable then
		if r.reason then tt:AddLine(head .. "|cff9aa4ad" .. r.reason .. "|r") end
		return true
	end
	if r.note then
		tt:AddLine(head .. "|cff9aa4ad" .. r.note .. "|r")
	elseif r.equipped then
		tt:AddLine(head .. "|cff9aa4adéquipé|r")
	elseif r.pct then
		local col, word
		if r.upgrade then
			col, word = "|cff6ee36e", (r.current == 0 and "amélioration (emplacement vide)" or "amélioration")
		elseif math.abs(r.pct) < 0.5 then
			col, word = "|cff9aa4ad", "équivalent"
		else
			col, word = "|cffff6b6b", "moins bien"
		end
		local txt = (r.current == 0 and r.score > 0) and "" or (fmtPct(r.pct) .. " · ")
		tt:AddLine(head .. col .. txt .. word .. "|r")
	end
	if r.needLevel then tt:AddLine("|cffffd100   niveau " .. r.needLevel .. " requis|r") end
	return true
end

local function hookTooltips()
	local P = TooltipDataProcessor
	local T = Enum and Enum.TooltipDataType
	local function handler(tt)
		if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
		local ok, _, link = pcall(tt.GetItem, tt)
		if ok and link then tooltipLines(tt, link) end
	end
	if P and P.AddTooltipPostCall and T and T.Item then
		P.AddTooltipPostCall(T.Item, handler)
		return
	end
	for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
		if tt and tt.HookScript then
			tt:HookScript("OnTooltipSetItem", function(self)
				if handler(self) then self:Show() end
			end)
		end
	end
end

---------------------------------------------------------------------------
-- Récompenses de quête
---------------------------------------------------------------------------

local marks = {}

local function rewardButtons()
	local f = (QuestInfoFrame and QuestInfoFrame.rewardsFrame) or QuestInfoRewardsFrame
	if not (f and type(f.RewardButtons) == "table") then return nil end
	return f.RewardButtons
end

local function hideMarks()
	for _, m in pairs(marks) do m:Hide() end
end

-- -> index du meilleur choix, est-ce une amélioration ?, résultat de la comparaison
function G.BestReward()
	local n = safe(GetNumQuestChoices) or 0
	if n < 2 then return nil end
	local best, bestUp, bestR, bestVal
	for i = 1, n do
		local link = GetQuestItemLink and safe(GetQuestItemLink, "choice", i)
		if not link then return nil, nil, nil, true end -- données pas encore chargées
		local r = G.Compare(link)
		if r and r.usable and r.upgrade and not r.needLevel then
			if not bestUp or r.delta > bestVal then best, bestUp, bestR, bestVal = i, true, r, r.delta end
		elseif not bestUp then
			local info = itemInfo(link)
			local _, _, qty = safe(GetQuestItemInfo, "choice", i)
			local value = (info and info.sell or 0) * (qty or 1)
			if not best or value > bestVal then best, bestR, bestVal = i, r, value end
		end
	end
	return best, bestUp, bestR
end

local function markReward(tries)
	hideMarks()
	if not EnvolDB.gear then return end
	local best, up, r, pending = G.BestReward()
	if pending and (tries or 0) < 5 then
		C_Timer.After(0.3, function() markReward((tries or 0) + 1) end)
		return
	end
	if not best then return end
	local buttons = rewardButtons()
	if buttons then
		for _, b in pairs(buttons) do
			if b and b.type == "choice" and b.IsShown and b:IsShown() and b:GetID() == best then
				local m = marks[b]
				if not m then
					m = b:CreateTexture(nil, "OVERLAY", nil, 7)
					m:SetSize(18, 18)
					m:SetPoint("TOPLEFT", b, "TOPLEFT", -4, 4)
					marks[b] = m
				end
				-- flèche verte = amélioration ; pièce d'or = rien de mieux, se revend le plus cher
				m:SetTexture(up and "Interface\\AddOns\\Envol\\Media\\Amelioration" or "Interface\\Icons\\INV_Misc_Coin_01")
				m:Show()
			end
		end
	end
	local link = safe(GetQuestItemLink, "choice", best)
	if link then
		if up then
			E.Print("meilleure récompense : " .. link .. " (" .. fmtPct(r.pct) .. ")")
		else
			E.Print("aucune récompense n'améliore votre équipement : " .. link .. " se revend le plus cher.")
		end
	end
end
G.MarkReward = markReward

---------------------------------------------------------------------------
-- Améliorations dans les sacs
---------------------------------------------------------------------------

G.upgrade = nil       -- meilleure amélioration portable maintenant
local announced = {}

local function numSlots(bag)
	if C_Container and C_Container.GetContainerNumSlots then return safe(C_Container.GetContainerNumSlots, bag) or 0 end
	return GetContainerNumSlots and safe(GetContainerNumSlots, bag) or 0
end

local function bagLink(bag, slot)
	if C_Container and C_Container.GetContainerItemLink then return safe(C_Container.GetContainerItemLink, bag, slot) end
	return GetContainerItemLink and safe(GetContainerItemLink, bag, slot)
end

function G.Scan()
	G.upgrade = nil
	if not EnvolDB.gear or not DATA then return end
	local best
	for bag = 0, 4 do
		for slot = 1, numSlots(bag) do
			local link = bagLink(bag, slot)
			if link then
				local r = G.Compare(link)
				if r and r.upgrade and r.usable and not r.needLevel then
					if not best or r.pct > best.pct then
						best = { link = link, pct = r.pct, bag = bag, slot = slot }
					end
				end
			end
		end
	end
	G.upgrade = best
	if best and not announced[best.link] then
		announced[best.link] = true
		E.Print("amélioration dans vos sacs : " .. best.link .. " (" .. fmtPct(best.pct) .. "). " ..
			"Cliquez sur la ligne dans la fenêtre d'Envol pour l'équiper.")
	end
end

local scanPending = false
function G.RequestScan()
	if scanPending then return end
	scanPending = true
	C_Timer.After(0.8, function()
		scanPending = false
		G.Scan()
		G.UpdateBagArrows()
		if E.UpdateUI then E.UpdateUI() end
	end)
end

function G.EquipUpgrade()
	local u = G.upgrade
	if not u then return end
	if safe(InCombatLockdown) then
		E.Print("impossible d'équiper en combat.")
		return
	end
	local f = (C_Item and C_Item.EquipItemByName) or EquipItemByName
	if f then pcall(f, u.link) end
	G.RequestScan()
end

-- Liste des emplacements et de ce qui serait mieux (commande /envol équipement)
function G.Report()
	local key, name, auto = G.Spec()
	E.Print("spé utilisée pour les conseils : " .. (name or "?") .. (auto and " (détectée)" or " (choisie)") ..
		" · niveau " .. (E.player.level or 1))
	G.Scan()
	if G.upgrade then
		E.Print("meilleure amélioration dans vos sacs : " .. G.upgrade.link .. " (" .. fmtPct(G.upgrade.pct) .. ")")
	else
		E.Print("rien de mieux dans vos sacs pour l'instant.")
	end
end

-- Bouton des réglages : Auto -> spé 1 -> spé 2 -> spé 3 -> Auto
function G.CycleSpec()
	local info = classInfo()
	if not info then return end
	local cur = EnvolChar.gearSpec
	local nextKey
	if not cur then
		nextKey = info.specs[1].key
	else
		for i, s in ipairs(info.specs) do
			if s.key == cur then nextKey = info.specs[i + 1] and info.specs[i + 1].key end
		end
	end
	EnvolChar.gearSpec = nextKey
	G.Invalidate()
end

function G.SpecLabel()
	local _, name, auto = G.Spec()
	if not name then return "?" end
	return auto and ("Auto (" .. name .. ")") or name
end

---------------------------------------------------------------------------
-- Flèche verte sur les icônes des sacs (comme Pawn)
---------------------------------------------------------------------------

local function containerFrames()
	local list = {}
	if ContainerFrameCombinedBags then list[#list + 1] = ContainerFrameCombinedBags end
	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		local f = _G["ContainerFrame" .. i]
		if f then list[#list + 1] = f end
	end
	return list
end

local function eachButton(f, fn)
	if f.EnumerateValidItems then
		if pcall(function() for _, b in f:EnumerateValidItems() do fn(b) end end) then return end
	end
	if type(f.Items) == "table" then
		for _, b in ipairs(f.Items) do fn(b) end
		return
	end
	local name = f.GetName and f:GetName()
	if not name then return end
	for j = 1, 40 do
		local b = _G[name .. "Item" .. j]
		if not b then break end
		fn(b)
	end
end

local function buttonSlot(b)
	local bag = b.GetBagID and safe(b.GetBagID, b)
	if bag == nil then
		local p = b.GetParent and b:GetParent()
		bag = p and p.GetID and safe(p.GetID, p)
	end
	return bag, b.GetID and safe(b.GetID, b)
end

local function setArrow(b, show)
	local t = rawget(b, "EnvolUp")
	if not show then
		if t then t:Hide() end
		return
	end
	if not t then
		t = b:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetTexture("Interface\\AddOns\\Envol\\Media\\Amelioration")
		t:SetSize(15, 15)
		t:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
		b.EnvolUp = t
	end
	t:Show()
end

function G.UpdateBagArrows()
	for _, f in ipairs(containerFrames()) do
		if f.IsShown and f:IsShown() then
			eachButton(f, function(b)
				local show = false
				if EnvolDB.gear and DATA and (not b.IsShown or b:IsShown()) then
					local bag, slot = buttonSlot(b)
					local link = bag and slot and bagLink(bag, slot)
					local r = link and G.Compare(link)
					show = r and r.usable and r.upgrade and not r.needLevel and true or false
				end
				setArrow(b, show)
			end)
		end
	end
end

local arrowsPending = false
local function requestArrows()
	if arrowsPending then return end
	arrowsPending = true
	C_Timer.After(0, function() arrowsPending = false; G.UpdateBagArrows() end)
end

local function hookBags()
	for _, f in ipairs(containerFrames()) do
		if f.HookScript then pcall(f.HookScript, f, "OnShow", requestArrows) end
		if hooksecurefunc then
			for _, m in ipairs({ "UpdateItems", "Update" }) do
				if type(f[m]) == "function" then pcall(hooksecurefunc, f, m, requestArrows) end
			end
		end
	end
	if hooksecurefunc and type(ContainerFrame_Update) == "function" then
		pcall(hooksecurefunc, "ContainerFrame_Update", requestArrows)
	end
end

---------------------------------------------------------------------------
-- Démarrage
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		DATA = EnvolData.gear
		if EnvolDB.gear == nil then EnvolDB.gear = true end
		if EnvolDB.autoReward == nil then EnvolDB.autoReward = false end
		hookTooltips()
		hookBags()
		for _, name in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP",
			"CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "QUEST_COMPLETE",
			"QUEST_FINISHED", "GET_ITEM_INFO_RECEIVED" }) do
			pcall(ev.RegisterEvent, ev, name)
		end
		C_Timer.After(3, G.RequestScan)
	elseif event == "QUEST_COMPLETE" then
		C_Timer.After(0.1, function() markReward(0) end)
	elseif event == "QUEST_FINISHED" then
		hideMarks()
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		G.scoreCache = {}
		G.RequestScan()
	elseif event == "PLAYER_LEVEL_UP" or event == "CHARACTER_POINTS_CHANGED" or event == "PLAYER_TALENT_UPDATE"
		or event == "ACTIVE_TALENT_GROUP_CHANGED" then
		C_Timer.After(0.5, G.Invalidate)
	else
		G.RequestScan()
	end
end)
