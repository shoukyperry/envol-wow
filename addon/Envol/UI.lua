-- Envol : interface en français (fenêtre de guide, menu des routes, réglages).

local E = Envol
local safe = E.Safe

local frame, header, guideText, body, footer, minimizeBtn
local lines = {}
local WIDTH = 340

local ICON_DONE = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ICON_TODO = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local ICON_BOX = "Interface\\Buttons\\UI-CheckBox-Up"

local COLOR_DIM = "|cff9aa4ad"
local COLOR_HEAD = "|cffffd100"
local COLOR_OK = "|cff6ee36e"

---------------------------------------------------------------------------
-- Textes des objectifs
---------------------------------------------------------------------------

local function progressSuffix(g)
	if not (g.q and g.o) or not E.IsOnQuest(g.q) then return "" end
	local objs = E.GetObjectives(g.q)
	local o = objs and objs[g.o]
	if o and o.numRequired and o.numRequired > 1 then
		return string.format(" (%d/%d)", o.numFulfilled or 0, o.numRequired)
	end
	return ""
end

local DEFAULT_TEXT = {
	v = "Vendez vos objets et réparez",
	tn = "Allez voir votre maître de classe",
	fp = "Prenez le point de vol",
	fly = "Prenez un vol",
	hs = "Utilisez votre pierre de foyer",
	home = "Liez votre pierre de foyer à l'auberge",
	die = "Mourez puis ressuscitez à l'ange (raccourci)",
}

function E.GoalText(g)
	local k = g.k
	if g.x and k ~= "c" then
		return g.x .. progressSuffix(g)
	end
	if k == "a" then
		return "Acceptez « " .. E.QuestName(g.q) .. " »"
	elseif k == "t" then
		return "Rendez « " .. E.QuestName(g.q) .. " »"
	elseif k == "c" then
		if g.o then
			local objs = E.IsOnQuest(g.q) and E.GetObjectives(g.q)
			local o = objs and objs[g.o]
			if o and o.text and o.text ~= "" then
				return (g.x and (g.x .. " — ") or "") .. o.text
			end
		end
		if g.x then return g.x .. progressSuffix(g) end
		return "Terminez « " .. E.QuestName(g.q) .. " »" .. (g.cm and (" : " .. g.cm) or "")
	elseif k == "col" then
		local name = E.ItemName(g.i) or g.cm or ("objet n°" .. g.i)
		return string.format("Récupérez %d × %s", g.n or 1, name) .. progressSuffix(g)
	elseif k == "lv" then
		return "Montez au niveau " .. g.l
	elseif k == "tr" then
		return "Apprenez " .. (E.SpellName(g.s) or ("le sort n°" .. g.s))
	elseif k == "ab" then
		return "Abandonnez « " .. E.QuestName(g.q) .. " »"
	elseif k == "g" then
		return nil -- les points de passage n'ont pas de ligne à eux
	end
	local t = DEFAULT_TEXT[k]
	if t and g.cm then t = t .. " : " .. g.cm end
	return t
end

---------------------------------------------------------------------------
-- Lignes de la fenêtre
---------------------------------------------------------------------------

local function getLine(n)
	local l = lines[n]
	if l then return l end
	l = CreateFrame("Button", nil, body)
	l:SetWidth(WIDTH - 20)
	l.icon = l:CreateTexture(nil, "ARTWORK")
	l.icon:SetSize(14, 14)
	l.icon:SetPoint("TOPLEFT", 0, -1)
	l.text = l:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	l.text:SetPoint("TOPLEFT", 18, 0)
	l.text:SetWidth(WIDTH - 40)
	l.text:SetJustifyH("LEFT")
	l.text:SetJustifyV("TOP")
	l.text:SetWordWrap(true)
	l:SetScript("OnClick", function(self)
		if self.onClick then self.onClick()
		elseif self.stepIdx and self.gi then E.ToggleGoal(self.stepIdx, self.gi) end
	end)
	l:SetScript("OnEnter", function(self)
		if self.clickHint then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.clickHint, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	l:SetScript("OnLeave", function() GameTooltip:Hide() end)
	lines[n] = l
	return l
end

local used, y

local function addLine(text, icon, opts)
	if not text or text == "" then return end
	used = used + 1
	local l = getLine(used)
	l:ClearAllPoints()
	l:SetPoint("TOPLEFT", body, "TOPLEFT", opts and opts.indent or 0, -y)
	l.text:SetFontObject(opts and opts.font or "GameFontHighlight")
	l.text:SetText(E.Expand(text))
	if icon then
		l.icon:SetTexture(icon)
		l.icon:Show()
		l.text:SetPoint("TOPLEFT", 18, 0)
	else
		l.icon:Hide()
		l.text:SetPoint("TOPLEFT", 0, 0)
	end
	l.stepIdx, l.gi, l.clickHint = opts and opts.stepIdx, opts and opts.gi, opts and opts.hint
	l.onClick = opts and opts.onClick
	l:EnableMouse(l.stepIdx ~= nil or l.onClick ~= nil)
	local h = math.max(l.text:GetStringHeight(), 14)
	l:SetHeight(h)
	l:Show()
	y = y + h + 4
end

local function addSpacer(px) y = y + (px or 6) end

local function textOf(t)
	if type(t) == "table" then
		if E.Applies(t[2]) then return t[1] end
		return nil
	end
	return t
end

-- Lignes d'une étape. dim : étape « en chemin »
local function renderStep(i, dim)
	local s = E.guide.steps[i]
	local font = dim and "GameFontHighlightSmall" or "GameFontHighlight"
	if s.h and not dim then
		addLine(COLOR_HEAD .. s.h .. "|r", nil, { font = "GameFontNormal" })
	end
	if s.t then
		for _, t in ipairs(s.t) do
			local txt = textOf(t)
			if txt then addLine((dim and COLOR_DIM or "") .. txt, nil, { font = font }) end
		end
	end
	local ticks = E.GetTicks(i) or {}
	for gi, g in ipairs(s.g) do
		if E.Applies(g.c) then
			local text = E.GoalText(g)
			if text then
				local st = ticks[gi] and "done" or E.GoalState(g, i, gi)
				if st ~= "na" then
					local manual = (g.k == "m" and not g.info) or g.k == "v" or g.k == "tn" or g.k == "fp"
						or g.k == "fly" or g.k == "hs" or g.k == "home" or g.k == "die" or g.k == "use"
					local icon
					if g.info then
						icon = nil
					elseif st == "done" then
						icon = ICON_DONE
					elseif manual then
						icon = ICON_BOX
					else
						icon = ICON_TODO
					end
					local opts = { font = font }
					if manual and not g.info then
						opts.stepIdx, opts.gi = i, gi
						opts.hint = "Clic : cocher / décocher cette ligne"
					end
					local shown = text
					if st == "done" then shown = COLOR_OK .. text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r" end
					if dim and st ~= "done" then shown = COLOR_DIM .. shown end
					addLine(shown, icon, opts)
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- XP par heure
---------------------------------------------------------------------------

local xp = { start = nil, gained = 0, last = nil, lastMax = nil }

local function xpUpdate()
	local cur = safe(UnitXP, "player")
	local max = safe(UnitXPMax, "player")
	if not cur or not max then return end
	if not xp.start then
		xp.start = GetTime()
		xp.last, xp.lastMax = cur, max
		return
	end
	local delta = cur - xp.last
	if delta < 0 then delta = (xp.lastMax - xp.last) + cur end -- montée de niveau
	if delta > 0 then xp.gained = xp.gained + delta end
	xp.last, xp.lastMax = cur, max
end

local function xpLine()
	if not xp.start then return nil end
	local secs = GetTime() - xp.start
	if secs < 120 or xp.gained <= 0 then return COLOR_DIM .. "XP/h : calcul en cours...|r" end
	local rate = xp.gained / secs * 3600
	local cur = safe(UnitXP, "player") or 0
	local max = safe(UnitXPMax, "player") or 1
	local mins = math.ceil((max - cur) / rate * 60)
	return COLOR_DIM .. "XP/h : " .. E.FormatNumber(rate) .. " · niveau suivant dans ~" .. mins .. " min|r"
end

---------------------------------------------------------------------------
-- Mise à jour de la fenêtre
---------------------------------------------------------------------------

function E.UpdateUI()
	if not frame then return end
	local v = E.view
	used, y = 0, 0
	if not E.guide or not v then
		guideText:SetText("Aucune route")
	else
		local meta = E.guide.meta
		local src = meta.src == "rxp" and "RestedXP" or "Polestar"
		guideText:SetText(E.Expand(meta.name) .. "  " .. COLOR_DIM .. "(" .. src .. ")|r")
		if not EnvolDB.minimized then
			if v.finished then
				addLine(COLOR_OK .. "Route terminée !|r Ouvrez le menu « Routes » pour choisir la suite.")
			else
				if #v.along > 0 then
					addLine(COLOR_DIM .. "En chemin :|r", nil, { font = "GameFontNormalSmall" })
					for _, j in ipairs(v.along) do renderStep(j, true) end
					addSpacer(4)
				end
				renderStep(v.idx, false)
				if v.state == "manual" then
					addSpacer(2)
					addLine(COLOR_DIM .. "Quand c'est fait, cliquez sur « > » (suivant).|r", nil, { font = "GameFontHighlightSmall" })
				end
				local up = EnvolDB.gear and E.Gear and E.Gear.upgrade
				if up then
					addSpacer(4)
					addLine(COLOR_OK .. "Amélioration : |r" .. up.link .. COLOR_OK ..
						string.format(" (%+.1f %%)", up.pct):gsub("%.", ",") .. "|r — cliquez pour l'équiper",
						"Interface\\AddOns\\Envol\\Media\\Fleche",
						{ font = "GameFontHighlightSmall", onClick = E.Gear.EquipUpgrade,
							hint = "Équipe cet objet de vos sacs (hors combat)." })
				end
				if EnvolChar.hold == v.idx then
					addLine(COLOR_DIM .. "Navigation manuelle : « > » pour reprendre le guidage.|r", nil, { font = "GameFontHighlightSmall" })
				end
			end
		end
	end
	for n = used + 1, #lines do lines[n]:Hide() end
	if EnvolDB.minimized then
		body:Hide(); footer:Hide()
		frame:SetHeight(32)
	else
		body:Show(); footer:Show()
		local foot = ""
		if v and E.guide then
			foot = COLOR_DIM .. "Étape " .. math.min(v.idx, v.total) .. " / " .. v.total .. "|r"
			local xl = xpLine()
			if xl then foot = foot .. "\n" .. xl end
		end
		footer:SetText(foot)
		body:SetHeight(math.max(y, 10))
		frame:SetHeight(32 + 6 + math.max(y, 10) + 6 + footer:GetStringHeight() + 10)
	end
end

---------------------------------------------------------------------------
-- Petits outils d'interface
---------------------------------------------------------------------------

local function styleBackdrop(f)
	if not f.SetBackdrop then return end
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	f:SetBackdropColor(0.04, 0.05, 0.07, 0.88)
	f:SetBackdropBorderColor(0.31, 0.76, 0.97, 0.5)
end

local function newPanel(name, w, h)
	local f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetSize(w, h)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) if not EnvolDB.locked then self:StartMoving() end end)
	styleBackdrop(f)
	return f
end

local function textButton(parent, label, w, tip, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, 20)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	if tip then
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(tip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	return b
end

local function savePoint(f, key)
	local p, _, rp, x, yy = f:GetPoint()
	EnvolDB[key] = { p, rp, x, yy }
end

local function restorePoint(f, key, default)
	local p = EnvolDB[key]
	f:ClearAllPoints()
	if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint(unpack(default)) end
end

---------------------------------------------------------------------------
-- Fenêtre principale
---------------------------------------------------------------------------

function E.CreateUI()
	frame = newPanel("EnvolFrame", WIDTH, 120)
	restorePoint(frame, "framePos", { "TOPRIGHT", UIParent, "TOPRIGHT", -260, -200 })
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePoint(self, "framePos") end)
	frame:SetScale(EnvolDB.scale or 1)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 8, -9)
	title:SetText(E.ADDON_COLOR .. "Envol|r")

	guideText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	guideText:SetPoint("LEFT", title, "RIGHT", 6, 0)
	guideText:SetPoint("RIGHT", frame, "TOPRIGHT", -150, -16)
	guideText:SetJustifyH("LEFT")
	guideText:SetWordWrap(false)

	minimizeBtn = textButton(frame, "-", 22, "Réduire / agrandir", function()
		EnvolDB.minimized = not EnvolDB.minimized
		E.UpdateUI()
	end)
	minimizeBtn:SetPoint("TOPRIGHT", -5, -6)
	local opt = textButton(frame, "Réglages", 64, "Réglages d'Envol", function() E.ToggleOptions() end)
	opt:SetPoint("RIGHT", minimizeBtn, "LEFT", -2, 0)
	local menu = textButton(frame, "Routes", 54, "Choisir une autre route", function() E.ToggleMenu() end)
	menu:SetPoint("RIGHT", opt, "LEFT", -2, 0)

	body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT", 10, -36)
	body:SetSize(WIDTH - 20, 10)

	footer = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	footer:SetPoint("BOTTOMLEFT", 10, 8)
	footer:SetPoint("BOTTOMRIGHT", -70, 8)
	footer:SetJustifyH("LEFT")

	local nextB = textButton(frame, ">", 28, "Étape suivante (valide l'étape affichée)", function() E.NextStep() end)
	nextB:SetPoint("BOTTOMRIGHT", -6, 6)
	local prevB = textButton(frame, "<", 28, "Étape précédente", function() E.PrevStep() end)
	prevB:SetPoint("RIGHT", nextB, "LEFT", -2, 0)
	frame.prevB, frame.nextB = prevB, nextB

	local xpFrame = CreateFrame("Frame")
	xpFrame:RegisterEvent("PLAYER_XP_UPDATE")
	xpFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	xpFrame:SetScript("OnEvent", xpUpdate)

	if EnvolDB.hidden then frame:Hide() end
	E.UpdateUI()
end

function E.ToggleMain()
	if frame:IsShown() then frame:Hide(); EnvolDB.hidden = true
	else frame:Show(); EnvolDB.hidden = nil; E.UpdateUI() end
end

function E.ApplyScale()
	if frame then frame:SetScale(EnvolDB.scale or 1) end
	if E.ApplyArrowSettings then E.ApplyArrowSettings() end
end

---------------------------------------------------------------------------
-- Menu des routes
---------------------------------------------------------------------------

local menu, menuRows, menuPage = nil, {}, 1
local PER_PAGE = 14

local function menuList()
	local rxp, ps = {}, {}
	for _, m in ipairs(E.FittingGuides()) do
		if m.src == "rxp" then rxp[#rxp + 1] = m else ps[#ps + 1] = m end
	end
	local order = function(a, b)
		if a.min ~= b.min then return a.min < b.min end
		return a.max < b.max
	end
	table.sort(rxp, order)
	table.sort(ps, order)
	local list = {}
	if #rxp > 0 then
		list[#list + 1] = { header = "RestedXP — routes speedrun (début du jeu)" }
		for _, m in ipairs(rxp) do list[#list + 1] = m end
	end
	if #ps > 0 then
		list[#list + 1] = { header = "Polestar — routes jusqu'au niveau 60" }
		for _, m in ipairs(ps) do list[#list + 1] = m end
	end
	return list
end

local function refreshMenu()
	local list = menuList()
	local pages = math.max(1, math.ceil(#list / PER_PAGE))
	if menuPage > pages then menuPage = pages end
	for r = 1, PER_PAGE do
		local row = menuRows[r]
		local item = list[(menuPage - 1) * PER_PAGE + r]
		if item then
			row.item = item
			if item.header then
				row.text:SetText(COLOR_HEAD .. item.header .. "|r")
				row:EnableMouse(false)
			else
				local cur = E.guide and E.guide.id == item.id
				row.text:SetText((cur and (COLOR_OK .. "> ") or "   ") .. E.Expand(item.name) .. (cur and "|r" or ""))
				row:EnableMouse(true)
			end
			row:Show()
		else
			row:Hide()
		end
	end
	menu.pageText:SetText("Page " .. menuPage .. " / " .. pages)
end

function E.ToggleMenu()
	if not menu then
		menu = newPanel("EnvolMenu", 360, 70 + PER_PAGE * 20)
		menu:SetFrameStrata("DIALOG")
		menu:SetPoint("CENTER")
		menu:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
		local t = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		t:SetPoint("TOPLEFT", 10, -10)
		t:SetText("Choisir une route")
		local close = textButton(menu, "Fermer", 60, nil, function() menu:Hide() end)
		close:SetPoint("TOPRIGHT", -6, -6)
		for r = 1, PER_PAGE do
			local row = CreateFrame("Button", nil, menu)
			row:SetSize(340, 18)
			row:SetPoint("TOPLEFT", 10, -36 - (r - 1) * 20)
			row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
			row.text:SetAllPoints()
			row.text:SetJustifyH("LEFT")
			local hl = row:CreateTexture(nil, "HIGHLIGHT")
			hl:SetAllPoints()
			hl:SetColorTexture(0.31, 0.76, 0.97, 0.15)
			row:SetScript("OnClick", function(self)
				if self.item and self.item.id then
					E.OpenGuide(self.item.id, 1)
					E.Print("route ouverte : " .. E.Expand(self.item.name))
					menu:Hide()
				end
			end)
			menuRows[r] = row
		end
		local prev = textButton(menu, "<", 30, nil, function() menuPage = math.max(1, menuPage - 1); refreshMenu() end)
		prev:SetPoint("BOTTOMLEFT", 10, 8)
		local nxt = textButton(menu, ">", 30, nil, function() menuPage = menuPage + 1; refreshMenu() end)
		nxt:SetPoint("LEFT", prev, "RIGHT", 4, 0)
		menu.pageText = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		menu.pageText:SetPoint("LEFT", nxt, "RIGHT", 8, 0)
		local hint = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		hint:SetPoint("BOTTOMRIGHT", -10, 12)
		hint:SetText(COLOR_DIM .. "Seules les routes adaptées à votre personnage sont listées|r")
		menu:Hide()
	end
	if menu:IsShown() then menu:Hide() else refreshMenu(); menu:Show() end
end

---------------------------------------------------------------------------
-- Réglages
---------------------------------------------------------------------------

local options

local function checkbox(parent, label, tip, get, set, yOff)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint("TOPLEFT", 10, yOff)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	fs:SetWidth(330)
	fs:SetJustifyH("LEFT")
	fs:SetText(label)
	cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	if tip then
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(tip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	cb.refresh = function() cb:SetChecked(get()) end
	return cb
end

local function stepper(parent, label, get, set, yOff)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	fs:SetPoint("TOPLEFT", 14, yOff - 4)
	local val = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	local minus = textButton(parent, "-", 24, nil, function() set(math.max(0.5, get() - 0.1)); val:SetText(string.format("%d %%", get() * 100 + 0.5)) end)
	minus:SetPoint("TOPLEFT", 220, yOff)
	val:SetPoint("LEFT", minus, "RIGHT", 6, 0)
	val:SetWidth(50)
	local plus = textButton(parent, "+", 24, nil, function() set(math.min(2, get() + 0.1)); val:SetText(string.format("%d %%", get() * 100 + 0.5)) end)
	plus:SetPoint("LEFT", val, "RIGHT", 6, 0)
	fs:SetText(label)
	return function() val:SetText(string.format("%d %%", get() * 100 + 0.5)) end
end

function E.ToggleOptions()
	if not options then
		options = newPanel("EnvolOptions", 400, 452)
		options:SetFrameStrata("DIALOG")
		options:SetPoint("CENTER")
		options:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
		local t = options:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		t:SetPoint("TOPLEFT", 10, -10)
		t:SetText("Réglages d'Envol")
		local close = textButton(options, "Fermer", 60, nil, function() options:Hide() end)
		close:SetPoint("TOPRIGHT", -6, -6)
		local D = EnvolDB
		local items = {}
		items[#items + 1] = checkbox(options, "Afficher la flèche directionnelle", nil,
			function() return D.arrow end, function(v) D.arrow = v end, -40)
		items[#items + 1] = checkbox(options, "Accepter et rendre automatiquement les quêtes de la route",
			"Seulement les quêtes prévues par l'étape en cours. Maintenez Maj en parlant au PNJ pour l'empêcher. Quand il faut choisir une récompense, Envol vous laisse choisir.",
			function() return D.autoQuest end, function(v) D.autoQuest = v end, -68)
		items[#items + 1] = checkbox(options, "Inclure les quêtes de groupe (élites)",
			"Les routes Polestar proposent quelques quêtes d'élite à faire en groupe. Décoché : elles sont sautées.",
			function() return D.groupQuests end, function(v) D.groupQuests = v; E.RequestRefresh() end, -96)
		items[#items + 1] = checkbox(options, "Verrouiller la fenêtre et la flèche", nil,
			function() return D.locked end, function(v) D.locked = v; E.ApplyScale() end, -124)
		items[#items + 1] = checkbox(options, "Commencer par les routes RestedXP (sinon : Polestar seul)",
			"RestedXP : routes de speedrunners, testées, jusqu'au niveau 20-22. Ensuite Envol enchaîne avec Polestar. S'applique au prochain choix automatique de route.",
			function() return D.source ~= "ps" end, function(v) D.source = v and "rxp" or "ps" end, -152)
		items[#items + 1] = checkbox(options, "Conseils d'équipement (infobulles, récompenses, sacs)",
			"Comme Pawn : compare chaque objet à ce que vous portez, selon votre spé et votre niveau.",
			function() return D.gear end, function(v) D.gear = v; E.Gear.Invalidate() end, -180)
		items[#items + 1] = checkbox(options, "Choisir automatiquement la meilleure récompense",
			"Pour les quêtes de la route rendues automatiquement : l'amélioration la plus forte, sinon l'objet qui se revend le plus cher.",
			function() return D.autoReward end, function(v) D.autoReward = v end, -208)
		local specBtn = textButton(options, "", 170, "Spé utilisée pour noter les objets. Auto = celle où vous avez mis le plus de points.", nil)
		specBtn:SetPoint("TOPLEFT", 220, -238)
		local specLbl = options:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		specLbl:SetPoint("TOPLEFT", 14, -242)
		specLbl:SetText("Spé pour l'équipement")
		local function refreshSpec() specBtn:SetText(E.Gear.SpecLabel()) end
		specBtn:SetScript("OnClick", function() E.Gear.CycleSpec(); refreshSpec() end)
		local r1 = stepper(options, "Taille de la fenêtre", function() return D.scale end,
			function(v) D.scale = v; E.ApplyScale() end, -270)
		local r2 = stepper(options, "Taille de la flèche", function() return D.arrowScale end,
			function(v) D.arrowScale = v; E.ApplyScale() end, -298)
		local reset = textButton(options, "Choisir la route automatiquement", 230,
			"Abandonne la route actuelle et laisse Envol choisir celle qui correspond à votre race et votre niveau.",
			function()
				local id = E.PickStartGuide()
				if id then E.OpenGuide(id, 1); E.Print("route choisie : " .. E.Expand(E.GetMeta(id).name)) end
			end)
		reset:SetPoint("TOPLEFT", 14, -336)
		local credit = options:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		credit:SetPoint("BOTTOMLEFT", 12, 10)
		credit:SetWidth(376)
		credit:SetJustifyH("LEFT")
		local ver = options:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ver:SetPoint("BOTTOMLEFT", 12, 48)
		ver:SetWidth(376)
		ver:SetJustifyH("LEFT")
		local b = E.BuildInfo()
		ver:SetText("Version " .. b.version .. " · routes du " .. E.FormatDate(b.date) .. "\n" .. COLOR_DIM ..
			"Mise à jour : lancez « Mettre à jour Envol » sur votre PC, puis /reload en jeu.|r")
		credit:SetText(COLOR_DIM .. "Routes : RestedXP (CC BY-NC-SA 4.0) et Polestar Guides (GPLv3). " ..
			"Envol n'est affilié à aucun des deux. /envol aide pour les commandes.|r")
		options.refresh = function()
			for _, cb in ipairs(items) do cb.refresh() end
			r1(); r2(); refreshSpec()
		end
		options:Hide()
	end
	if options:IsShown() then options:Hide() else options.refresh(); options:Show() end
end

---------------------------------------------------------------------------
-- Commandes
---------------------------------------------------------------------------

SLASH_ENVOL1 = "/envol"
SlashCmdList.ENVOL = function(msg)
	msg = string.lower(strtrim(msg or ""))
	if msg == "" then
		E.ToggleMain()
	elseif msg == "menu" or msg == "routes" then
		E.ToggleMenu()
	elseif msg == "options" or msg == "reglages" or msg == "réglages" then
		E.ToggleOptions()
	elseif msg == "suivant" or msg == "s" then
		E.NextStep()
	elseif msg == "precedent" or msg == "précédent" or msg == "p" then
		E.PrevStep()
	elseif msg == "fleche" or msg == "flèche" then
		EnvolDB.arrow = not EnvolDB.arrow
		E.Print("flèche " .. (EnvolDB.arrow and "affichée" or "masquée"))
	elseif msg == "équipement" or msg == "equipement" or msg == "stuff" then
		E.Gear.Report()
	elseif msg == "version" then
		local b = E.BuildInfo()
		E.Print("version " .. b.version .. " · routes du " .. E.FormatDate(b.date) ..
			" (RestedXP " .. (b.rxp or "?") .. ", Polestar " .. (b.ps or "?") .. ")")
	elseif msg == "reset" then
		local id = E.PickStartGuide()
		if id then E.OpenGuide(id, 1); E.Print("route choisie : " .. E.Expand(E.GetMeta(id).name)) end
	else
		E.Print("commandes :")
		E.Print("/envol — afficher / masquer la fenêtre")
		E.Print("/envol routes — choisir une route")
		E.Print("/envol réglages — options")
		E.Print("/envol suivant (ou s) — étape suivante · /envol précédent (ou p) — étape précédente")
		E.Print("/envol flèche — afficher / masquer la flèche")
		E.Print("/envol reset — laisser Envol choisir la route selon votre race et votre niveau")
		E.Print("/envol équipement — spé utilisée et meilleure amélioration dans vos sacs")
		E.Print("/envol version — version installée et date des routes")
	end
end
