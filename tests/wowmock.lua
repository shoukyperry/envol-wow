-- Faux client WoW minimal pour tester Envol hors du jeu.
MOCK = {
	class = "WARRIOR", race = "Tauren", faction = "Horde", level = 1, xp = 0, xpmax = 400,
	onQuest = {}, done = {}, ready = {}, objectives = {}, items = {}, spells = {}, money = 0,
	map = 1412, px = 0.4492, py = 0.7712, facing = 0, timers = {}, events = {}, chat = {},
	texts = {}, rotation = nil,
}
local M = MOCK

local era = {
	[1412] = { c = 1, left = 2047.917, right = -3089.583, top = -272.917, bottom = -3697.917 },
	[1413] = { c = 1, left = 2622.917, right = -7510.417, top = 1612.5, bottom = -5143.75 },
	[1454] = { c = 1, left = -3680.601, right = -5083.206, top = 2273.877, bottom = 1338.461 },
	[1456] = { c = 1, left = 516.667, right = -527.083, top = -850, bottom = -1545.833 },
}

-- Cadres factices : toute méthode inconnue ne fait rien
local frameMT = {}
frameMT.__index = function(t, k)
	return function(self, ...) return nil end
end
local function newObj(kind)
	local o = { kind = kind, scripts = {}, shown = true, events = {} }
	o.SetScript = function(self, name, fn) self.scripts[name] = fn end
	o.GetScript = function(self, name) return self.scripts[name] end
	o.RegisterEvent = function(self, ev) self.events[ev] = true; M.events[#M.events + 1] = { self, ev } end
	o.CreateTexture = function() return newObj("Texture") end
	o.CreateFontString = function()
		local fs = newObj("FontString")
		fs.SetText = function(self, t) self.text = t; M.texts[#M.texts + 1] = t end
		fs.GetText = function(self) return self.text end
		fs.GetStringHeight = function() return 14 end
		fs.GetStringWidth = function() return 40 end
		return fs
	end
	o.GetFontString = function() return o.fs end
	o.SetText = function(self, t) self.text = t end
	o.Show = function(self) self.shown = true end
	o.Hide = function(self) self.shown = false end
	o.IsShown = function(self) return self.shown end
	o.GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end
	o.GetChecked = function() return false end
	o.SetRotation = function(self, r) M.rotation = r end
	o.SetTexCoord = function(self, ...) M.texcoord = { ... } end
	o.SetTexture = function(self, t) M.texture = t end
	o.SetVertexColor = function(self, r, g, b) M.color = { r, g, b } end
	o.SetAlpha = function(self, a) self.alpha = a end
	return setmetatable(o, frameMT)
end
function CreateFrame(kind, name) local f = newObj(kind); if name then _G[name] = f end; return f end
UIParent = newObj("Frame")
GameTooltip = newObj("Frame")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) M.chat[#M.chat + 1] = m end }
SlashCmdList = {}
BackdropTemplateMixin = {}
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function GetTime() return M.time or 1000 end
function IsShiftKeyDown() return false end
function unpack(t) return table.unpack and table.unpack(t) or _G.unpackOrig(t) end

C_Timer = {
	After = function(_, fn) M.timers[#M.timers + 1] = fn end,
	NewTicker = function() return {} end,
}
function MOCK.RunTimers()
	for _ = 1, 20 do
		local list = M.timers
		M.timers = {}
		if #list == 0 then return end
		for _, fn in ipairs(list) do fn() end
	end
end
function MOCK.Fire(ev, ...)
	for _, e in ipairs(M.events) do
		if e[2] == ev and e[1].scripts.OnEvent then e[1].scripts.OnEvent(e[1], ev, ...) end
	end
	M.RunTimers()
end

function UnitClass() return "Guerrier", M.class end
function UnitRace() return M.race, M.race end
function UnitFactionGroup() return M.faction end
function UnitLevel() return M.level end
function UnitXP() return M.xp end
function UnitXPMax() return M.xpmax end
function UnitOnTaxi() return false end
function UnitIsGhost() return false end
function GetMoney() return M.money end
function GetBindLocation() return "" end
function GetSubZoneText() return "" end
function GetPlayerFacing() return M.facing end
function GetLocale() return "frFR" end
function time(t) return os.time(t) end

C_QuestLog = {
	IsQuestFlaggedCompleted = function(q) return M.done[q] == true end,
	IsOnQuest = function(q) return M.onQuest[q] == true end,
	ReadyForTurnIn = function(q) return M.ready[q] == true end,
	IsComplete = function(q) return M.ready[q] == true end,
	GetQuestObjectives = function(q) return M.objectives[q] or {} end,
	GetTitleForQuestID = function(q) return nil end,
}
M.itemDB, M.equipped, M.choices, M.bags = {}, {}, {}, {}
C_Item = {
	GetItemCount = function(i) return M.items[i] or 0 end,
	GetItemNameByID = function(i) return "Objet" .. i end,
	GetItemInfo = function(link)
		local d = M.itemDB[link]
		if not d then return nil end
		return link, link, 2, 10, d.minLevel or 1, "", "", 1, d.loc, 0, d.sell or 0, d.class, d.sub
	end,
	GetItemStats = function(link) local d = M.itemDB[link]; return d and d.stats end,
}
function GetInventoryItemLink(_, slot) return M.equipped[slot] end
function GetNumQuestChoices() return #M.choices end
function GetQuestItemLink(_, i) return M.choices[i] end
function GetQuestItemInfo(_, i) return "x", 0, 1 end
function InCombatLockdown() return false end
C_Container = {
	GetContainerNumSlots = function(bag) return bag == 0 and #M.bags or 0 end,
	GetContainerItemLink = function(bag, slot) return M.bags[slot] end,
}
C_Spell = { GetSpellName = function(s) return "Sort" .. s end }
function IsPlayerSpell(s) return M.spells[s] == true end

local function v2(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
function CreateVector2D(x, y) return v2(x, y) end
C_Map = {
	GetBestMapForUnit = function() return M.map end,
	GetPlayerMapPosition = function() return v2(M.px, M.py) end,
	GetWorldPosFromMapPos = function(map, v)
		local b = era[map]
		if not b then return nil end
		local a = b.left + (b.right - b.left) * v.x
		local n = b.top + (b.bottom - b.top) * v.y
		return b.c, v2(n, a) -- x : axe nord, y : axe ouest (comme le client)
	end,
	GetAreaInfo = function(id) return "Zone" .. id end,
	GetMapInfo = function(id) return { name = "Carte" .. id } end,
}
