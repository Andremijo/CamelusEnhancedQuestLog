import os
from lupa import lua51
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "CamelusEnhancedQuestLog", "CamelusEnhancedQuestLog.lua"), encoding="utf-8").read()
i = src.index("local shiftedPoints = {}"); j = src.index("local function CountCompleted")
code = src[i:j]
L = lua51.LuaRuntime()
L.execute(r'''
local COUNT_EXTRA = 14
local countLayout = false
InCombatLockdown = function() return false end
local function NewRegion(points)
  local r = { pts = points, h = 20 }
  function r:GetNumPoints() return #self.pts end
  function r:GetPoint(i) local p = self.pts[i]; return p[1], p[2], p[3], p[4], p[5] end
  function r:SetPoint(p, rel, rp, x, y)
    for _, q in ipairs(self.pts) do if q[1] == p then q[2], q[3], q[4], q[5] = rel, rp, x, y; return end end
    table.insert(self.pts, { p, rel, rp, x, y })
  end
  function r:ClearAllPoints() self.pts = {} end
  function r:GetHeight() return self.h end
  function r:SetHeight(h) self.h = h end
  return r
end
local parent = {}
QuestScrollFrame = NewRegion({ { "TOPLEFT", parent, "TOPLEFT", 0, -29 }, { "BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0 } })
QuestScrollFrame.SearchBox = NewRegion({ { "BOTTOMLEFT", QuestScrollFrame, "TOPLEFT", 6, 7 } })
QuestLogCount = NewRegion({})
QuestLogCount.Left, QuestLogCount.Middle, QuestLogCount.Right = NewRegion({}), NewRegion({}), NewRegion({})
''' + code + r'''
local function check(c, m) if not c then error("FAIL: " .. m) end print("ok  " .. m) end
local sf, sb = QuestScrollFrame, QuestScrollFrame.SearchBox
SetCountLayout(true)
check(select(5, sf:GetPoint(1)) == -43 and select(5, sb:GetPoint(1)) == 21 and QuestLogCount.h == 34, "layout on: list -43, search box 21, box 34")
SetCountLayout(false)
check(select(5, sf:GetPoint(1)) == -29 and select(5, sb:GetPoint(1)) == 7 and QuestLogCount.h == 20, "layout off restores Blizzard's positions")
SetCountLayout(true)
-- a map addon (Leatrix) re-anchors the list and the search box
sf:ClearAllPoints(); sf:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -50); sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
sb:ClearAllPoints(); sb:SetPoint("LEFT", {}, "RIGHT", -300, 1)
SetCountLayout(false)
check(select(5, sf:GetPoint(1)) == -50, "undo leaves the map addon's list position alone (-50)")
check(select(1, sb:GetPoint(1)) == "LEFT" and select(5, sb:GetPoint(1)) == 1, "undo leaves the map addon's search box alone")
check(QuestLogCount.h == 20, "box height restored")
''')
