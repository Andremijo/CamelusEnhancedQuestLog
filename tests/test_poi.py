import os
from lupa import lua51

# Replacing Blizzard's "?" completed marker with the check mark: when it is
# hidden, and that it always comes back when it should.
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "CamelusEnhancedQuestLog", "CamelusEnhancedQuestLog.lua"), encoding="utf-8").read()
i = src.index("local function ShowsCheckMark()"); j = src.index("local function UpdateCheck")
code = src[i:j]
L = lua51.LuaRuntime()
L.execute(r'''
local fadedPOIs = setmetatable({}, { __mode = "k" })
local db = { mode = "both", replacePOI = true }
local statuses = { [1] = "complete", [2] = nil, [3] = "complete" }
local function QuestStatus(id) return statuses[id] end
local function NewPOI(id)
  local b = { id = id, alpha = 1, shown = true }
  function b:GetQuestID() return self.id end
  function b:IsShown() return self.shown end
  function b:SetAlpha(a) self.alpha = a end
  return b
end
local pois = { [1] = NewPOI(1), [2] = NewPOI(2), [3] = NewPOI(3) }
QuestScrollFrame = { Contents = {} }
-- like Blizzard's POIButtonOwnerMixin:FindButtonByQuestID: searches the active buttons by their current quest
function QuestScrollFrame.Contents:FindButtonByQuestID(id)
  for _, b in pairs(pois) do if b.shown and b:GetQuestID() == id then return b end end
end
''' + code + r'''
local function check(c, m) if not c then error("FAIL: " .. m) end print("ok  " .. m) end
-- what Decorate does for each row
local function decorate(id)
  local poi = ShouldReplacePOI(id, QuestStatus(id)) and FindPOIButton(id) or nil
  if poi then poi:SetAlpha(0); fadedPOIs[poi] = id end
  return poi
end
local function refresh() RestorePOIs(); for id = 1, 3 do decorate(id) end end

refresh()
check(pois[1].alpha == 0 and pois[3].alpha == 0, "completed quests' markers are hidden")
check(pois[2].alpha == 1, "an unfinished quest keeps its marker")
statuses[3] = nil; refresh()
check(pois[3].alpha == 1, "marker comes back when a quest is no longer complete")
pois[1].id = 2; refresh()   -- Blizzard reuses quest 1's button for quest 2
check(pois[1].alpha == 1, "a reused button for an unfinished quest is visible again")
pois[1].id = 1; db.replacePOI = false; refresh()
check(pois[1].alpha == 1, "option off shows Blizzard's marker")
db.replacePOI = true; db.mode = "text"; refresh()
check(pois[1].alpha == 1, "no replacement when the check mark itself is turned off")
db.mode = "check"; refresh()
check(pois[1].alpha == 0, "check-only mode replaces the marker")
pois[1].shown = false; refresh()
check(pois[1].alpha == 1, "a released (hidden) button gets its alpha back")
QuestScrollFrame.Contents.FindButtonByQuestID = nil
check(FindPOIButton(1) == nil, "no lookup function: nothing replaced, no error")
''')
