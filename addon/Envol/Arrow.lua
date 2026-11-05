-- Envol : flèche directionnelle.
-- Géométrie en coordonnées du monde (mètres de jeu) : "a" croît vers l'ouest,
-- "b" vers le nord ; l'orientation du joueur vaut 0 au nord et croît vers l'ouest.

local E = Envol
local safe = E.Safe
local atan2, sqrt, pi, cos, abs, floor = math.atan2, math.sqrt, math.pi, math.cos, math.abs, math.floor

local arrow, tex, distText, labelText
local target = nil       -- { c, a, b, step, gi, radius, isGoto, isLast, label }
local loopPos = {}       -- étape en boucle -> index du point visé
local halo               -- lueur derrière la flèche : verte dans la bonne direction, rouge à l'opposé
local curAngle = nil     -- angle affiché (suit la cible en douceur)
local pulse = 0          -- horloge de la pulsation à l'arrivée

-- Styles de flèche : variantes de couleur du cristal, plus l'ancienne flèche blanche
E.ARROW_STYLES = { "Arcane", "Givre", "Nature", "Or", "Feu", "Sang", "Ombre", "Classique" }
local shown = nil        -- flèche visible ?

---------------------------------------------------------------------------
-- Conversions carte <-> monde (bornes de chaque carte calculées une fois)
---------------------------------------------------------------------------

local boundsCache = {}
local vec

local function worldOf(map, x, y)
	if not (C_Map and C_Map.GetWorldPosFromMapPos) then return nil end
	vec = vec or (CreateVector2D and CreateVector2D(0, 0)) or {}
	vec.x, vec.y = x, y
	local ok, c, pos = pcall(C_Map.GetWorldPosFromMapPos, map, vec)
	if not ok or not c or not pos then return nil end
	local wx, wy
	if pos.GetXY then wx, wy = pos:GetXY() else wx, wy = pos.x, pos.y end
	if not wx then return nil end
	return c, wx, wy -- wx : axe nord ("b"), wy : axe ouest ("a")
end

local function boundsOf(map)
	local b = boundsCache[map]
	if b == nil then
		b = false
		local c0, top, left = worldOf(map, 0, 0)
		local c1, bottom, right = worldOf(map, 1, 1)
		if c0 and c0 == c1 and top ~= bottom and left ~= right then
			b = { c = c0, top = top, bottom = bottom, left = left, right = right }
		end
		boundsCache[map] = b
	end
	return b or nil
end

-- (carte, x %, y %) -> continent, a, b
local function mapToWorld(map, x, y)
	local b = boundsOf(map)
	if not b then return nil end
	return b.c, b.left + (b.right - b.left) * x / 100, b.top + (b.bottom - b.top) * y / 100
end

local function posToWorld(p)
	if not p then return nil end
	if p[1] == "w" then return p[2], p[3], p[4] end
	return mapToWorld(p[2], p[3], p[4])
end

function E.PlayerWorld()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
	local map = safe(C_Map.GetBestMapForUnit, "player")
	if not map then return nil end
	local ok, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
	if not ok or not pos then return nil end
	local x, y
	if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
	x, y = E.Readable(x), E.Readable(y)
	if not x or not y or (x == 0 and y == 0) then return nil end
	return mapToWorld(map, x * 100, y * 100)
end

---------------------------------------------------------------------------
-- Choix de la cible
---------------------------------------------------------------------------

local function pickCandidate(goal, pc, pa, pb)
	-- maître de classe : le plus proche parmi ceux de la classe du joueur
	local best, bestD
	for _, cand in ipairs(goal.cand) do
		if not cand.cl or E.Applies({ cl = cand.cl }) then
			local c, a, b = posToWorld(cand.p)
			if c then
				local d = (pc == c and pa) and ((a - pa) ^ 2 + (b - pb) ^ 2) or 1e12
				if not bestD or d < bestD then best, bestD = { c, a, b, cand.n }, d end
			end
		end
	end
	return best
end

-- Cible d'une étape : le premier point utile dans l'ordre de l'étape
local function stepTarget(i)
	local s = E.guide.steps[i]
	local ticks = E.GetTicks(i) or {}
	local gotos = {}
	for gi, g in ipairs(s.g) do
		if g.k == "g" and E.Applies(g.c) and not (g.r == 0 and not g.op) then
			gotos[#gotos + 1] = gi
		end
	end
	if s.loop and #gotos > 0 then
		local n = loopPos[i] or 1
		if n > #gotos then n = 1 end
		loopPos[i] = n
		local gi = gotos[n]
		local g = s.g[gi]
		return { pos = g.p, step = i, gi = gi, radius = (g.r and g.r > 0) and g.r or 25, loop = true,
			label = g.x }
	end
	-- objectifs avec un lieu (routes Polestar), ou chemin de points (routes RestedXP)
	local pc, pa, pb = E.PlayerWorld()
	for gi, g in ipairs(s.g) do
		if E.Applies(g.c) and not ticks[gi] then
			if g.k == "g" then
				if not (g.r == 0 and not g.op) then
					local last = gotos[#gotos] == gi
					return { pos = g.p, step = i, gi = gi, radius = (g.r and g.r > 0) and g.r or 10,
						isGoto = true, isLast = last, label = g.x }
				end
			elseif (g.p or g.cand) and E.GoalState(g, i, gi) == "todo" then
				if g.cand then
					local best = pickCandidate(g, pc, pa, pb)
					if best then
						return { world = best, step = i, gi = gi, radius = 6, label = best[4] }
					end
				elseif g.p then
					return { pos = g.p, step = i, gi = gi, radius = 6, label = g.x }
				end
			end
		end
	end
	-- tous les points du chemin atteints : on garde le dernier en vue
	if #gotos > 0 then
		local gi = gotos[#gotos]
		local g = s.g[gi]
		return { pos = g.p, step = i, gi = gi, radius = (g.r and g.r > 0) and g.r or 10, isGoto = true,
			isLast = true, label = g.x, reached = true }
	end
	return nil
end

function E.UpdateArrowTarget()
	target = nil
	local v = E.view
	if not v or not v.step or not E.guide then return end
	target = stepTarget(v.idx)
	if not target then
		for _, j in ipairs(v.along) do
			target = stepTarget(j)
			if target then break end
		end
	end
	if target then
		if target.world then
			target.c, target.a, target.b = target.world[1], target.world[2], target.world[3]
		else
			target.c, target.a, target.b = posToWorld(target.pos)
		end
		if not target.c then target = nil end
	end
end

---------------------------------------------------------------------------
-- Cadre de la flèche
---------------------------------------------------------------------------

local function savePos()
	local p, _, rp, x, y = arrow:GetPoint()
	EnvolDB.arrowPos = { p, rp, x, y }
end

function E.ApplyArrowSettings()
	if not arrow then return end
	arrow:SetScale(EnvolDB.arrowScale or 1)
	arrow:EnableMouse(shown ~= false and not EnvolDB.locked)
end

local function setVisible(self, v)
	if shown == v then return end
	shown = v
	self:SetAlpha(v and 1 or 0)
	self:EnableMouse(v and not EnvolDB.locked)
end

local RELIEF_ANGLES, RELIEF_COLS = 64, 8

-- flèche en relief : planche de 64 vues (8 x 8), une par direction
local function relief()
	return EnvolDB.arrow3D ~= false and (EnvolDB.arrowStyle or "Arcane") ~= "Classique"
end
E.ArrowRelief = relief

local lastFrame
local function setReliefAngle(a)
	local step = 2 * pi / RELIEF_ANGLES
	local i = floor(((a % (2 * pi)) / step) + 0.5) % RELIEF_ANGLES
	if i == lastFrame then return end
	lastFrame = i
	local c, r = i % RELIEF_COLS, floor(i / RELIEF_COLS)
	tex:SetTexCoord(c / RELIEF_COLS, (c + 1) / RELIEF_COLS, r / RELIEF_COLS, (r + 1) / RELIEF_COLS)
end
E.SetReliefAngle = setReliefAngle

function E.ApplyArrowStyle()
	if not tex then return end
	local style = EnvolDB.arrowStyle or "Arcane"
	lastFrame = nil
	tex:SetRotation(0)
	tex:SetTexCoord(0, 1, 0, 1)
	if relief() then
		tex:SetTexture("Interface\\AddOns\\Envol\\Media\\Relief\\" .. style)
		tex:SetVertexColor(1, 1, 1)
		tex:SetSize(76, 76)
		setReliefAngle(curAngle or 0)
		return
	end
	if style == "Classique" then
		tex:SetTexture("Interface\\AddOns\\Envol\\Media\\Fleche")
		tex:SetSize(56, 56)
	else
		tex:SetTexture("Interface\\AddOns\\Envol\\Media\\Fleche_" .. style)
		tex:SetVertexColor(1, 1, 1)
		tex:SetSize(64, 64)
	end
end

function E.CycleArrowStyle()
	local cur = EnvolDB.arrowStyle or "Arcane"
	local n = 1
	for i, s in ipairs(E.ARROW_STYLES) do if s == cur then n = i end end
	EnvolDB.arrowStyle = E.ARROW_STYLES[n % #E.ARROW_STYLES + 1]
	E.ApplyArrowStyle()
	return EnvolDB.arrowStyle
end

-- plus court chemin entre deux angles
local function wrap(a) return ((a + pi) % (2 * pi)) - pi end

local elapsed = 0
local function onUpdate(self, dt)
	elapsed = elapsed + dt
	if elapsed < 0.02 then return end
	dt = elapsed
	elapsed = 0
	if not EnvolDB.arrow or not target then
		setVisible(self, false)
		return
	end
	setVisible(self, true)
	if safe(UnitOnTaxi, "player") then
		tex:Hide(); halo:Hide(); distText:SetText(""); labelText:SetText("En vol...")
		return
	end
	local pc, pa, pb = E.PlayerWorld()
	if not pc then
		tex:Hide(); halo:Hide(); distText:SetText("?"); labelText:SetText("Position inconnue ici")
		return
	end
	if pc ~= target.c then
		tex:Hide(); halo:Hide(); distText:SetText("")
		labelText:SetText("Cible sur un autre continent")
		return
	end
	local dw, dn = target.a - pa, target.b - pb
	local dist = sqrt(dw * dw + dn * dn)
	-- point atteint
	if dist <= target.radius then
		if target.loop then
			loopPos[target.step] = (loopPos[target.step] or 1) + 1
			E.UpdateArrowTarget()
			return
		elseif target.isGoto and not target.reached then
			E.MarkArrived(target.step, target.gi, target.isLast)
			target.reached = true
		end
	end
	local facing = safe(GetPlayerFacing)
	local classic = (EnvolDB.arrowStyle == "Classique")
	local arrived = dist <= target.radius
	tex:Show()
	local r, g, b = 0.8, 0.8, 0.8
	if facing then
		local angle = wrap(atan2(dw, dn) - facing)
		-- rotation fluide : la flèche rattrape la direction sans à-coups
		if not curAngle then curAngle = angle end
		curAngle = wrap(curAngle + wrap(angle - curAngle) * math.min(1, dt * 12))
		if relief() then setReliefAngle(curAngle) else tex:SetRotation(curAngle) end
		-- vert quand on va dans la bonne direction, rouge à l'opposé
		local off = abs(angle) / pi
		if arrived then
			r, g, b = 0.3, 0.8, 1
		else
			r, g, b = math.min(1, off * 2), math.min(1, 2 - off * 2), 0.2
		end
	else
		curAngle = nil
		if relief() then setReliefAngle(0) else tex:SetRotation(0) end
	end
	if classic then tex:SetVertexColor(r, g, b) end
	-- halo et pulsation
	pulse = arrived and (pulse + dt) or 0
	if EnvolDB.arrowHalo ~= false and not classic then
		halo:Show()
		halo:SetVertexColor(r, g, b)
		local k = arrived and (0.5 + 0.25 * math.sin(pulse * 6)) or 0.45
		halo:SetAlpha(k)
		local sz = arrived and (84 + 10 * math.sin(pulse * 6)) or 84
		halo:SetSize(sz, sz)
	else
		halo:Hide()
	end
	local scale = arrived and (1 + 0.08 * math.sin(pulse * 6)) or 1
	local base = classic and 56 or (relief() and 76 or 64)
	tex:SetSize(base * scale, base * scale)
	if dist <= target.radius then
		distText:SetText("Vous y êtes")
	else
		distText:SetText(floor(dist + 0.5) .. " m")
	end
	labelText:SetText(target.label and E.Expand((target.label:gsub("|T.-|t", ""))) or "")
end

function E.CreateArrow()
	arrow = CreateFrame("Frame", "EnvolArrow", UIParent)
	arrow:SetSize(70, 70)
	local p = EnvolDB.arrowPos
	if p then arrow:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else arrow:SetPoint("CENTER", UIParent, "CENTER", 0, 180) end
	arrow:SetMovable(true)
	arrow:SetClampedToScreen(true)
	arrow:RegisterForDrag("LeftButton")
	arrow:SetScript("OnDragStart", function(self) if not EnvolDB.locked then self:StartMoving() end end)
	arrow:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos() end)
	arrow:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" and E.ToggleOptions then E.ToggleOptions() end
	end)

	halo = arrow:CreateTexture(nil, "BACKGROUND")
	halo:SetTexture("Interface\\AddOns\\Envol\\Media\\Halo")
	halo:SetBlendMode("ADD")
	halo:SetSize(84, 84)
	halo:SetPoint("CENTER", 0, 4)
	halo:Hide()

	tex = arrow:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("CENTER", 0, 4)
	E.ApplyArrowStyle()

	distText = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	distText:SetPoint("TOP", arrow, "BOTTOM", 0, 6)
	labelText = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	labelText:SetPoint("TOP", distText, "BOTTOM", 0, -2)
	labelText:SetWidth(240)
	labelText:SetMaxLines(2)

	arrow:SetScript("OnUpdate", onUpdate)
	E.ApplyArrowSettings()
end
