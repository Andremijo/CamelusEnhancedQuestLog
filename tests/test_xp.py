import os
from lupa import lua51
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "CamelusEnhancedQuestLog", "CamelusEnhancedQuestLog.lua"), encoding="utf-8").read()
def between(a, b):
    i = src.index(a); j = src.index(b, i); return src[i:j]
safecall = between("local function SafeCall", "local function StripColors")
letter = between('-- "[26] Title" -> "[26D] Title"', "-- If the first line of the title is wider")
xp_and_title = between("-- XP the quest gives, or nil", "local function UpdateCheck")
L = lua51.LuaRuntime()
L.execute(r'''
local titleState = {}
local function BreakFirstLine(button, fs, text, maxWidth) return text end
local function WithHeightFix(button, fs, change) change() end
local playerLevel, maxLevel, rewards = 33, 60, { [101] = 1950, [102] = 0 }
UnitLevel = function() return playerLevel end
GetMaxPlayerLevel = function() return maxLevel end
GetQuestLogRewardXP = function(id) return rewards[id] or 0 end
BreakUpLargeNumbers = function(n) local s = tostring(n); return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")) end
''' + safecall + letter + xp_and_title + r'''
local function check(c, m) if not c then error("FAIL: " .. m) end print("ok  " .. m) end
local fs = { text = "[33] Vahlarriel's Search" }
function fs:GetText() return self.text end
function fs:SetText(t) self.text = t end
local button = {}
local function run(id, showXP, lvl) UpdateTitle(button, fs, lvl or "", showXP and XPSuffix(GetQuestXP(id)) or "", nil) end
run(101, true)
check(fs.text == "[33] Vahlarriel's Search (1,950 XP)", "adds XP: " .. fs.text)
run(101, true)
check(fs.text == "[33] Vahlarriel's Search (1,950 XP)", "no double XP on repeat")
rewards[101] = 2100; run(101, true)
check(fs.text == "[33] Vahlarriel's Search (2,100 XP)", "updates when XP changes")
run(101, true, "D")
check(fs.text == "[33D] Vahlarriel's Search (2,100 XP)", "works together with the D letter")
run(101, false, "D")
check(fs.text == "[33D] Vahlarriel's Search", "option off removes XP")
run(102, true)
check(fs.text == "[33] Vahlarriel's Search", "no (0 XP) for quests without XP")
playerLevel = 60; run(101, true)
check(fs.text == "[33] Vahlarriel's Search", "nothing at max level")
playerLevel = 33
fs.text = "[30] Fiora Longears"  -- Blizzard reuses the row for another quest
run(101, true)
check(fs.text == "[30] Fiora Longears (2,100 XP)", "recycled row starts from the new quest's title")
''')
