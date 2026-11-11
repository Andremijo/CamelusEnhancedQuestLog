import os
import re, sys
from lupa import lua51
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "QuestLogCompletedMarker", "QuestLogCompletedMarker.lua"), encoding="utf-8").read()
def between(a, b):
    i = src.index(a); j = src.index(b, i); return src[i:j]
strip = between("local function StripColors", "------------------------------------------------------------------------\n-- Quest information")
isfs = between("local function IsFontString", "local function GetTitleFontString")
foreign = between("local foreignCount  -- their FontString", "local function UpdateCompletedCount")
L = lua51.LuaRuntime()
harness = r'''
local ownRegions = {}
QuestLogQuestCount = nil
local numQuests = 17
C_QuestLog = { GetNumQuestLogEntries = function() return 30, numQuests end }
Constants = { QuestLogConsts = { MAXIMUM_NUM_QUESTS_LOG_CAN_ACCEPT = 40 } }
local function NewFS(text)
  local fs = { text = text, visible = true }
  function fs:GetObjectType() return "FontString" end
  function fs:GetText() return self.text end
  function fs:SetText(t) self.text = t end
  function fs:IsVisible() return self.visible end
  return fs
end
local function NewFrame(regions, kids)
  local f = { regions = regions or {}, kids = kids or {} }
  function f:GetRegions() return unpack(self.regions) end
  function f:GetChildren() return unpack(self.kids) end
  function f:IsVisible() return true end
  return f
end
-- Leatrix-like: WorldMapFrame -> titleFrame -> titleTextFrame -> questCount
local leaCount = NewFS("|cffffffff17|r/40")
local zoneText = NewFS("Darkshore")
local titleTextFrame = NewFrame({ zoneText, leaCount })
local titleFrame = NewFrame({}, { titleTextFrame })
local scroll = NewFrame({ NewFS("17/40") }) -- must be skipped (ScrollContainer)
WorldMapFrame = NewFrame({}, { scroll, titleFrame })
WorldMapFrame.ScrollContainer = scroll
''' + strip + isfs + foreign + r'''
local function check(cond, msg) if not cond then error("FAIL: " .. msg) end print("ok  " .. msg) end
local fs = FindForeignCount(QuestCountString())
check(fs == leaCount, "finds Leatrix count, skips the map scroll container")
UpdateForeignCount(fs, 5)
check(leaCount.text == "|cffffffff17|r/40 \194\183 |cffffffff5|r completed", "appends suffix: " .. leaCount.text)
UpdateForeignCount(FindForeignCount(QuestCountString()), 5)
check(leaCount.text == "|cffffffff17|r/40 \194\183 |cffffffff5|r completed", "idempotent on repeat")
UpdateForeignCount(FindForeignCount(QuestCountString()), 6)
check(leaCount.text == "|cffffffff17|r/40 \194\183 |cffffffff6|r completed", "updates number, no double suffix")
-- Leatrix resets its text after a quest is accepted
numQuests = 18; leaCount.text = "|cffffffff18|r/40"
UpdateForeignCount(FindForeignCount(QuestCountString()), 6)
check(leaCount.text == "|cffffffff18|r/40 \194\183 |cffffffff6|r completed", "re-adds after Leatrix resets text")
-- option turned off
UpdateForeignCount(FindForeignCount(QuestCountString()), nil)
check(leaCount.text == "|cffffffff18|r/40", "removes suffix when turned off")
-- box back in use: fs nil removes suffix
UpdateForeignCount(FindForeignCount(QuestCountString()), 3)
UpdateForeignCount(nil, 3)
check(leaCount.text == "|cffffffff18|r/40", "removes suffix when no foreign count is used")
-- no Leatrix: nothing found
leaCount.visible = false
check(FindForeignCount(QuestCountString()) == nil, "finds nothing when their count is hidden")
'''
L.execute(harness)
