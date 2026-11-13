-- Camelus' Enhanced Quest Log
-- Classic-style touches for the modern quest log:
--   * a green check mark to the left of completed quests
--   * "(Complete)" / "(Failed)" in the tag column, where "(Dungeon)" is shown
--   * a letter after the level: [26D] for dungeon quests, [40R] for raid quests
--
-- Options window: /ceql  (also under Options -> AddOns in the game menu)
--
-- Slash commands:
--   /ceql          open the options window
--   /ceql help     list the commands below
--   /ceql both     check mark and (Complete) text
--   /ceql check    only the check mark
--   /ceql text     only the (Complete) text
--   /ceql off      neither
--   /ceql level    toggle the D/R letter after the quest level
--   /ceql replace  toggle replacing Blizzard's "?" completed marker with the check mark
--   /ceql xp       toggle the quest's XP after the title, e.g. (1,950 XP)
--   /ceql count    toggle "Quests completed: 5/34" under "Quests: 34/40"
--   /ceql color    toggle (Complete) colour: green or the quest's own colour
--                 (or /ceql color green, /ceql color quest)
--   /ceql debug    print what the addon finds (open the quest log first)

local ADDON_NAME = ...

------------------------------------------------------------------------
-- Easy-to-change settings
------------------------------------------------------------------------
local TEXT_COMPLETE = "(Complete)"
local TEXT_FAILED   = "(Failed)"
local GREEN         = { 0.25, 1, 0.25 }  -- colour of (Complete) in "green" mode
local CHECK_TEXTURE = "Interface\\RaidFrame\\ReadyCheck-Ready" -- green check mark
local CHECK_SIZE    = 14
local ADDON_ICON    = "Interface\\AddOns\\" .. ADDON_NAME .. "\\CamelusEnhancedQuestLog" -- the .tga in the addon folder
-- Quest tag IDs -> letter after the level. 81 = Dungeon, 62/88/89 = Raid.
local LEVEL_LETTERS = { [81] = "D", [62] = "R", [88] = "R", [89] = "R" }
local TAG_GAP       = 6    -- minimum space between the title and (Complete)
local COUNT_LABEL   = "Quests completed:"
local COUNT_EXTRA   = 14   -- how much taller the "Quests: 34/40" box gets
local MAX_DEPTH     = 4    -- how deep to look for quest title rows
local POLL_INTERVAL = 0.3  -- seconds between re-checks while the quest log is open

------------------------------------------------------------------------
local db
-- Everything we add is tracked in our own tables (weak keys), never as
-- fields on Blizzard's frames, so we don't taint Blizzard's code.
local checks     = setmetatable({}, { __mode = "k" }) -- row -> check texture
local ourTags    = setmetatable({}, { __mode = "k" }) -- row -> our "(Complete)" FontString
local measurers  = setmetatable({}, { __mode = "k" }) -- row -> invisible FontString for measuring
local fadedTags  = setmetatable({}, { __mode = "k" }) -- row -> Blizzard tag we made invisible
local fadedPOIs  = setmetatable({}, { __mode = "k" }) -- Blizzard "?" button -> questID we made it invisible for
local titleState = setmetatable({}, { __mode = "k" }) -- row -> { base = Blizzard's text, shown = our text }
local ownRegions = setmetatable({}, { __mode = "k" }) -- set of regions we created
local learnedTag -- where Blizzard puts its tag, learned from a row that has one

local function Print(msg)
    print("|cff40ff40Camelus' Enhanced Quest Log:|r " .. msg)
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

local function StripColors(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

------------------------------------------------------------------------
-- Quest information
------------------------------------------------------------------------
-- Returns "complete", "failed" or nil.
local function QuestStatus(questID, logIndex)
    local api = C_QuestLog
    local apiSaysComplete -- true / false / nil (unknown)
    if api and questID then
        if SafeCall(api.IsFailed, questID) == true then return "failed" end
        local done = SafeCall(api.IsComplete, questID)
        if done == nil then done = SafeCall(api.ReadyForTurnIn, questID) end
        if done ~= nil then apiSaysComplete = (done == true or done == 1) end
        if apiSaysComplete then return "complete" end
        if not logIndex then logIndex = SafeCall(api.GetLogIndexForQuestID, questID) end
    end
    if not logIndex and questID then logIndex = SafeCall(GetQuestLogIndexByID, questID) end
    if type(logIndex) == "number" and logIndex > 0 and type(GetQuestLogTitle) == "function" then
        -- Classic: 6th return value is 1 when complete, -1 when failed.
        local c = select(6, GetQuestLogTitle(logIndex))
        if c == -1 then return "failed" end
        if apiSaysComplete == nil and (c == 1 or c == true) then return "complete" end
    end
    return nil
end

-- "D" for dungeon quests, "R" for raid quests, "" otherwise.
local function GetLevelLetter(questID, tagText)
    local tagID
    if questID then
        if C_QuestLog and C_QuestLog.GetQuestTagInfo then
            local info = SafeCall(C_QuestLog.GetQuestTagInfo, questID)
            if type(info) == "table" then tagID = info.tagID end
        end
        if not tagID then tagID = SafeCall(GetQuestTagInfo, questID) end
    end
    if type(tagID) == "number" and LEVEL_LETTERS[tagID] then return LEVEL_LETTERS[tagID] end

    -- Fallback: read the tag Blizzard shows, e.g. "(Dungeon)".
    if tagText then
        local t = tagText:lower()
        local dungeon = (type(LFG_TYPE_DUNGEON) == "string" and LFG_TYPE_DUNGEON or "Dungeon"):lower()
        local raid = (type(RAID) == "string" and RAID or "Raid"):lower()
        if t:find(dungeon, 1, true) or t:find("dungeon", 1, true) then return "D" end
        if t:find(raid, 1, true) or t:find("raid", 1, true) then return "R" end
    end
    return ""
end

------------------------------------------------------------------------
-- Finding things in the quest log
------------------------------------------------------------------------
local function IsFontString(v)
    return type(v) == "table" and v.GetObjectType and v:GetObjectType() == "FontString"
end

local function GetTitleFontString(f)
    local fs = f.Text or f.Title
    if IsFontString(fs) then return fs end
end

local function GetQuestID(f)
    local id = f.questID
    if type(id) == "number" and id > 0 then return id end
end

local function IsTitleButton(f)
    if not (f.IsObjectType and f:IsObjectType("Button")) then return false end
    if not (GetQuestID(f) or type(f.questLogIndex) == "number") then return false end
    return GetTitleFontString(f) ~= nil
end

-- Blizzard's visible tag on this row, e.g. "(Dungeon)". Returns fs, plainText.
local function FindBlizzardTag(button, titleFs)
    local regions = { button:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        if r ~= titleFs and not ownRegions[r] and IsFontString(r) and r:IsShown() then
            local text = r:GetText()
            if text then
                local plain = StripColors(text)
                if plain:match("^%s*%(.+%)%s*$") then return r, plain end
            end
        end
    end
end

local function FindCheckbox(button)
    local cb = button.Checkbox or button.CheckBox or button.Check
    if type(cb) == "table" and cb.GetLeft then return cb end
    local kids = { button:GetChildren() }
    for i = 1, #kids do
        if kids[i]:IsObjectType("CheckButton") then return kids[i] end
    end
end

local function GetRoots()
    local roots = {}
    local sf = QuestScrollFrame
    if sf then
        local content = sf.Contents or (sf.GetScrollChild and sf:GetScrollChild())
        roots[#roots + 1] = content or sf
    elseif QuestMapFrame then
        roots[#roots + 1] = QuestMapFrame
    end
    return roots
end

local function Scan(frame, depth, fn)
    if not (frame and frame.GetChildren) then return end
    local kids = { frame:GetChildren() }
    for i = 1, #kids do
        local child = kids[i]
        if IsTitleButton(child) then
            if child:IsShown() then fn(child) end
        elseif depth < MAX_DEPTH then
            Scan(child, depth + 1, fn)
        end
    end
end

------------------------------------------------------------------------
-- Measuring
------------------------------------------------------------------------
local function CopyFont(target, source)
    local fontObject = source:GetFontObject()
    if fontObject then target:SetFontObject(fontObject) end
    local font, size, flags = source:GetFont()
    if font then target:SetFont(font, size, flags) end
end

-- Top of the first line of visible text. A FontString can be taller than
-- its text (the text is then centered in it), so its own top is not enough.
local function TextTop(fs)
    local top, bottom = fs:GetTop(), fs:GetBottom()
    if not (top and bottom) then return nil end
    local h = fs:GetStringHeight() or 0
    if (top - bottom) <= h + 0.5 then return top end
    local jv = fs:GetJustifyV()
    if jv == "TOP" then return top end
    if jv == "BOTTOM" then return bottom + h end
    return (top + bottom) / 2 + h / 2
end

-- Right edge of the visible text of a FontString.
local function TextRight(fs)
    local l, r = fs:GetLeft(), fs:GetRight()
    if not (l and r) then return nil end
    local w = fs:GetStringWidth() or 0
    local j = fs:GetJustifyH()
    if j == "LEFT" then return l + w end
    if j == "CENTER" then return (l + r) / 2 + w / 2 end
    return r
end

-- Width of a text on one line, in the title's font. The measuring
-- FontString only holds text while we measure and is emptied and hidden
-- straight after, so it can never show up on screen.
local function MeasureWidth(button, fs, text)
    local m = measurers[button]
    if not m then
        m = button:CreateFontString(nil, "BACKGROUND")
        m:SetPoint("TOPLEFT", button, "TOPLEFT")
        if m.SetWordWrap then m:SetWordWrap(false) end
        measurers[button] = m
        ownRegions[m] = true
    end
    CopyFont(m, fs)
    m:Show()
    m:SetText(text)
    local width = m:GetStringWidth() or 0
    m:SetText("")
    m:Hide()
    return width
end

------------------------------------------------------------------------
-- Changing a row
------------------------------------------------------------------------
-- Runs change(), then grows/shrinks the row if the title now has more or
-- fewer lines, so it doesn't overlap the objective line below it.
local function WithHeightFix(button, fs, change)
    local before = fs:GetStringHeight() or 0
    change()
    local delta = (fs:GetStringHeight() or 0) - before
    if math.abs(delta) > 0.5 then
        button:SetHeight(math.max(1, button:GetHeight() + delta))
    end
end

-- "[26] Title" -> "[26D] Title"
local function ApplyLevelLetter(text, letter)
    local pre, level, current, rest = text:match("^(.-)%[(%d+)([DR]?)%](.*)$")
    if not level or current == letter then return text end
    return pre .. "[" .. level .. letter .. "]" .. rest
end

-- If the first line of the title is wider than maxWidth, move words to a
-- new line so the title doesn't run into (Complete).
local function BreakFirstLine(button, fs, text, maxWidth)
    if not maxWidth or maxWidth < 30 then return text end
    if MeasureWidth(button, fs, text) <= maxWidth then return text end
    local breakAt
    for spaceAt in text:gmatch("() ") do
        if MeasureWidth(button, fs, text:sub(1, spaceAt - 1)) <= maxWidth then
            breakAt = spaceAt
        else
            break
        end
    end
    if not breakAt then return text end
    return text:sub(1, breakAt - 1) .. "\n" .. text:sub(breakAt + 1)
end

-- XP the quest gives, or nil (no XP, data not loaded yet, or max level).
local function GetQuestXP(questID)
    if not questID or type(GetQuestLogRewardXP) ~= "function" then return nil end
    local level, maxLevel = SafeCall(UnitLevel, "player"), SafeCall(GetMaxPlayerLevel)
    if type(level) == "number" and type(maxLevel) == "number" and level >= maxLevel then return nil end
    local xp = SafeCall(GetQuestLogRewardXP, questID)
    if type(xp) == "number" and xp > 0 then return xp end
end

-- " (1,950 XP)"
local function XPSuffix(xp)
    if not xp then return "" end
    local number = (type(BreakUpLargeNumbers) == "function" and SafeCall(BreakUpLargeNumbers, xp)) or tostring(xp)
    return " (" .. number .. " XP)"
end

local function UpdateTitle(button, fs, letter, xpSuffix, maxFirstLine)
    local text = fs:GetText()
    if not text then return end
    local st = titleState[button]
    if not st then st = {}; titleState[button] = st end
    -- If the text is what we set last time, start again from Blizzard's text.
    local base = (st.shown and text == st.shown) and st.base or text
    local want = BreakFirstLine(button, fs, ApplyLevelLetter(base, letter) .. xpSuffix, maxFirstLine)
    st.base, st.shown = base, want
    if want ~= text then
        WithHeightFix(button, fs, function() fs:SetText(want) end)
    end
end

------------------------------------------------------------------------
-- Blizzard's own completed marker: the "?" in a circle at the top left of
-- a quest row (a POI button, shown when "Quest Objectives" / the questPOI
-- setting is on). With "replace" on, it is made invisible (alpha 0, so it
-- still works when clicked) and the check mark takes its place.
------------------------------------------------------------------------
local function ShowsCheckMark() return db.mode == "both" or db.mode == "check" end

-- Should Blizzard's marker for this quest be replaced by our check mark?
local function ShouldReplacePOI(questID, status)
    return db.replacePOI and ShowsCheckMark() and status == "complete" and questID ~= nil
end

-- The quest's "?"/"..." button in the quest log, if there is one. Only looks
-- it up (FindButtonByQuestID), never creates one.
local function FindPOIButton(questID)
    local contents = QuestScrollFrame and QuestScrollFrame.Contents
    if not (questID and contents and type(contents.FindButtonByQuestID) == "function") then return nil end
    local ok, poi = pcall(contents.FindButtonByQuestID, contents, questID)
    if ok and poi and poi:IsShown() then return poi end
    return nil
end

-- Gives back every marker we hid that shouldn't be hidden any more: the
-- option is off, the quest isn't complete, or Blizzard reused the button
-- for another quest.
local function RestorePOIs()
    for poi, questID in pairs(fadedPOIs) do
        local current = poi.GetQuestID and poi:GetQuestID()
        if not poi:IsShown() or current ~= questID
            or not ShouldReplacePOI(questID, QuestStatus(questID)) then
            poi:SetAlpha(1)
            fadedPOIs[poi] = nil
        end
    end
end

local function UpdateCheck(button, fs, show, poi)
    local tex = checks[button]
    if not show then
        if tex then tex:Hide() end
        return
    end
    if not tex then
        tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(CHECK_TEXTURE)
        checks[button] = tex
        ownRegions[tex] = true
    end
    tex:ClearAllPoints()
    if poi then
        -- In the place of Blizzard's "?" marker, a little bigger.
        tex:SetSize(CHECK_SIZE + 4, CHECK_SIZE + 4)
        tex:SetPoint("CENTER", poi, "CENTER", 0, 0)
        tex:Show()
        return
    end
    tex:SetSize(CHECK_SIZE, CHECK_SIZE)
    local textTop, fsTop = TextTop(fs), fs:GetTop()
    local dy = (textTop and fsTop) and (textTop - fsTop) or 0
    tex:SetPoint("TOPRIGHT", fs, "TOPLEFT", -3, dy + 1)
    tex:Show()
end

-- Where (Complete) goes: x = right edge, y = top, both as offsets from the
-- row's top right corner.
local function GetTagOffsets(button, titleFs, blizzTag)
    local bRight, bTop, tTop = button:GetRight(), button:GetTop(), TextTop(titleFs)
    if not (bRight and bTop and tTop) then return nil end
    if blizzTag then
        local right, top = TextRight(blizzTag), TextTop(blizzTag)
        if right and top then learnedTag = { x = right - bRight, dy = top - tTop } end
    end
    if learnedTag then
        return learnedTag.x, (tTop - bTop) + learnedTag.dy
    end
    -- No dungeon quest seen yet: just left of the tracking checkbox.
    local cb = FindCheckbox(button)
    local x = (cb and cb:GetLeft()) and (cb:GetLeft() - bRight - 4) or -30
    return x, tTop - bTop
end

local function Decorate(button)
    local fs = GetTitleFontString(button)
    if not fs then return end
    local questID = GetQuestID(button)
    local status = QuestStatus(questID, button.questLogIndex)
    local blizzTag, tagText = FindBlizzardTag(button, fs)
    local letter = db.level and GetLevelLetter(questID, tagText) or ""
    local showTag = status and (db.mode == "both" or db.mode == "text")

    local tag = ourTags[button]
    local maxFirstLine
    if showTag then
        if not tag then
            tag = button:CreateFontString(nil, "OVERLAY")
            tag:SetJustifyH("RIGHT")
            ourTags[button] = tag
            ownRegions[tag] = true
        end
        CopyFont(tag, blizzTag or fs)
        if db.color == "quest" then
            tag:SetTextColor(fs:GetTextColor())
        else
            tag:SetTextColor(GREEN[1], GREEN[2], GREEN[3])
        end
        tag:SetText(status == "failed" and TEXT_FAILED or TEXT_COMPLETE)
        local x = GetTagOffsets(button, fs, blizzTag)
        local left, bRight = fs:GetLeft(), button:GetRight()
        if x and left and bRight then
            maxFirstLine = (bRight + x - (tag:GetStringWidth() or 0) - TAG_GAP) - left
        end
    end

    -- Title first (it may get a line break), then place things next to it.
    UpdateTitle(button, fs, letter, db.showXP and XPSuffix(GetQuestXP(questID)) or "", maxFirstLine)
    local poi = ShouldReplacePOI(questID, status) and FindPOIButton(questID) or nil
    if poi then
        poi:SetAlpha(0)
        fadedPOIs[poi] = questID
    end
    UpdateCheck(button, fs, status == "complete" and ShowsCheckMark(), poi)

    local x, y
    if showTag then x, y = GetTagOffsets(button, fs, blizzTag) end
    if x then
        tag:ClearAllPoints()
        tag:SetPoint("TOPRIGHT", button, "TOPRIGHT", x, y)
        tag:Show()
        if blizzTag then
            blizzTag:SetAlpha(0)
            fadedTags[button] = blizzTag
        end
    else
        if tag then tag:Hide() end
        if fadedTags[button] then
            fadedTags[button]:SetAlpha(1)
            fadedTags[button] = nil
        end
    end
end

------------------------------------------------------------------------
-- "Quests completed: 5/34" under "Quests: 34/40"
--
-- In WoW Forever the count sits in a 20 pixel high box (QuestLogCount)
-- right of the search box, with the quest list starting just below. To fit
-- a second line, the box grows downwards by COUNT_EXTRA and the list moves
-- down by the same amount. The search box keeps its place.
--
-- Some map addons hide that box and show their own count instead, e.g.
-- Leatrix Maps' "Use simple map frame" shows "17/40" in its title bar. Then
-- the layout is left alone and " · 5 completed" is added after their count.
------------------------------------------------------------------------
local countLine          -- our FontString under Blizzard's count
local countLayout = false
local searchBaseWidth    -- search box width as Blizzard last set it
local countBaseWidth     -- the count box's own width
local shiftedPoints = {} -- region -> the anchor we set, so we only undo our own change

local function ShiftPoint(region, point, dy)
    for i = 1, region:GetNumPoints() do
        local p, rel, relPoint, x, y = region:GetPoint(i)
        if p == point then
            region:SetPoint(p, rel, relPoint, x, (y or 0) + dy)
            shiftedPoints[region] = { point = p, rel = rel, relPoint = relPoint, y = (y or 0) + dy }
            return true
        end
    end
    return false
end

-- Undoes ShiftPoint, but only if nobody (e.g. a map addon) has re-anchored
-- the region since. Otherwise their position is left alone.
local function UnshiftPoint(region, dy)
    local rec = shiftedPoints[region]
    shiftedPoints[region] = nil
    if not rec then return end
    for i = 1, region:GetNumPoints() do
        local p, rel, relPoint, x, y = region:GetPoint(i)
        if p == rec.point and rel == rec.rel and relPoint == rec.relPoint
            and math.abs((y or 0) - rec.y) < 0.01 then
            region:SetPoint(p, rel, relPoint, x, (y or 0) - dy)
            return
        end
    end
end

-- Makes room for the second line (on = true) or puts everything back.
local function SetCountLayout(on)
    if countLayout == on then return true end
    if InCombatLockdown and InCombatLockdown() then return false end -- retried after combat
    local sf, box = QuestScrollFrame, QuestLogCount
    local sb = sf and sf.SearchBox
    if not (sf and box and sb) then return false end
    if on then
        if not ShiftPoint(sf, "TOPLEFT", -COUNT_EXTRA) then return false end -- list down
        ShiftPoint(sb, "BOTTOMLEFT", COUNT_EXTRA)                            -- search box stays put
    else
        UnshiftPoint(sf, -COUNT_EXTRA)
        UnshiftPoint(sb, COUNT_EXTRA)
    end
    local d = on and COUNT_EXTRA or -COUNT_EXTRA
    box:SetHeight(box:GetHeight() + d) -- box grows downwards
    for _, key in ipairs({ "Left", "Middle", "Right" }) do
        local t = box[key]
        if t and t.SetHeight then t:SetHeight(t:GetHeight() + d) end
    end
    countLayout = on
    return true
end

local function CountCompleted()
    local api = C_QuestLog
    if not (api and api.GetNumQuestLogEntries and api.GetInfo) then return nil end
    local numEntries, numQuests = api.GetNumQuestLogEntries()
    local done, total = 0, 0
    for i = 1, numEntries or 0 do
        local info = api.GetInfo(i)
        if info and not info.isHeader and not info.isHidden and not info.isTask and not info.isBounty then
            total = total + 1
            if QuestStatus(info.questID, i) == "complete" then done = done + 1 end
        end
    end
    return done, numQuests or total
end

-- Same style as Blizzard's "Quests: 34/40" (white first number).
local function CountText(done, total)
    local numbers
    local template = type(QUEST_LOG_COUNT_TEMPLATE) == "string" and QUEST_LOG_COUNT_TEMPLATE
    local body = template and template:match("^[^%%]*(%%.*)$")
    if body then
        local ok, result = pcall(string.format, body, "|cffffffff", done, total)
        if ok then numbers = result end
    end
    numbers = numbers or ("|cffffffff%d|r/%d"):format(done, total)
    return COUNT_LABEL .. " " .. numbers
end

-- Is Blizzard's own "Quests: 34/40" box in use? Map addons such as
-- Leatrix Maps hide it (Hide and/or alpha 0). IsShown, not IsVisible, so a
-- collapsed quest log panel doesn't count as "taken over".
local function BlizzardCountBoxInUse()
    local box = QuestLogCount
    return box ~= nil and box:IsShown() and box:GetAlpha() > 0.01
end

------------------------------------------------------------------------
-- Another addon's quest count, e.g. Leatrix Maps' "17/40"
------------------------------------------------------------------------
local foreignCount  -- their FontString
local foreignSuffix -- the text we added after their count

-- "17/40" as the game counts it, or nil.
local function QuestCountString()
    local api = C_QuestLog
    local consts = Constants and Constants.QuestLogConsts
    local max = consts and consts.MAXIMUM_NUM_QUESTS_LOG_CAN_ACCEPT
    if not (api and api.GetNumQuestLogEntries and max) then return nil end
    local _, numQuests = api.GetNumQuestLogEntries()
    if not numQuests then return nil end
    return numQuests .. "/" .. max
end

-- Text of a FontString without the suffix we added. Returns plain, raw.
local function TextWithoutSuffix(fs)
    local text = fs:GetText() or ""
    if fs == foreignCount and foreignSuffix and #text >= #foreignSuffix
        and text:sub(-#foreignSuffix) == foreignSuffix then
        text = text:sub(1, #text - #foreignSuffix)
    end
    return StripColors(text), text
end

-- Looks for a visible FontString on the world map that shows exactly the
-- quest count ("17/40"). The map itself (ScrollContainer) is skipped.
local function FindForeignCount(want)
    if not want then return nil end
    if foreignCount and foreignCount:IsVisible() and TextWithoutSuffix(foreignCount) == want then
        return foreignCount
    end
    local map = WorldMapFrame
    if not (map and map:IsVisible()) then return nil end
    local found
    local function search(frame, depth)
        if found or frame == map.ScrollContainer then return end
        local regions = { frame:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if IsFontString(r) and r ~= QuestLogQuestCount and not ownRegions[r] and r:IsVisible()
                and TextWithoutSuffix(r) == want then
                found = r
                return
            end
        end
        if depth < 3 then
            local kids = { frame:GetChildren() }
            for i = 1, #kids do
                search(kids[i], depth + 1)
                if found then return end
            end
        end
    end
    search(map, 0)
    return found
end

-- Adds " · 5 completed" after their count (done = nil removes it).
local function UpdateForeignCount(fs, done)
    if foreignCount and foreignCount ~= fs then
        local _, base = TextWithoutSuffix(foreignCount)
        if base ~= foreignCount:GetText() then foreignCount:SetText(base) end
        foreignCount, foreignSuffix = nil, nil
    end
    if not fs then return end
    if fs ~= foreignCount then foreignCount, foreignSuffix = fs, nil end
    local _, base = TextWithoutSuffix(fs)
    local suffix = done and (" \194\183 |cffffffff%d|r completed"):format(done) or nil -- \194\183 = middle dot
    local text = suffix and (base .. suffix) or base
    if fs:GetText() ~= text then fs:SetText(text) end
    foreignSuffix = suffix
end

local function UpdateCompletedCount()
    if not db then return end
    local done, total
    if db.showCount then done, total = CountCompleted() end

    local ownBox = BlizzardCountBoxInUse()
    UpdateForeignCount((not ownBox) and FindForeignCount(QuestCountString()) or nil, done)

    local box, cf = QuestLogCount, QuestLogQuestCount
    local sb = QuestScrollFrame and QuestScrollFrame.SearchBox
    if not (box and cf and sb) then return end

    local show = ownBox and done ~= nil and SetCountLayout(true)
    if not show then
        if countLine then countLine:Hide() end
        if countBaseWidth then box:SetWidth(countBaseWidth) end
        if searchBaseWidth and ownBox then sb:SetWidth(searchBaseWidth) end
        -- Put the layout back when the option is off, or when another addon
        -- has taken over the box (only undoes our own anchor changes).
        if not db.showCount or not ownBox then SetCountLayout(false) end
        return
    end

    if not countLine then
        countLine = box:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        countLine:SetJustifyH("RIGHT")
        countLine:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 0, -3)
    end
    CopyFont(countLine, cf)
    countLine:SetText(CountText(done, total))
    countLine:Show()

    -- Widen the box to fit the longer text and shorten the search box by
    -- the same amount, so the row keeps its width.
    countBaseWidth = countBaseWidth or box:GetWidth()
    searchBaseWidth = searchBaseWidth or sb:GetWidth()
    local need = math.max(cf:GetStringWidth() or 0, countLine:GetStringWidth() or 0) + 14
    local boxWidth = math.max(countBaseWidth, math.ceil(need))
    box:SetWidth(boxWidth)
    sb:SetWidth(math.max(80, searchBaseWidth - (boxWidth - countBaseWidth)))
end

local function Refresh()
    if not db then return end
    RestorePOIs()
    for _, root in ipairs(GetRoots()) do
        if root:IsVisible() then Scan(root, 0, Decorate) end
    end
    if WorldMapFrame and WorldMapFrame:IsVisible() then UpdateCompletedCount() end
end

------------------------------------------------------------------------
-- When to refresh
------------------------------------------------------------------------
local hooked = {}
local function TryInstallHooks()
    if not hooked.update and type(QuestLogQuests_Update) == "function" then
        hooksecurefunc("QuestLogQuests_Update", Refresh)
        hooked.update = true
    end
    if not hooked.count and type(QuestLogQuests_ShowQuestCount) == "function" then
        -- Blizzard sets the search box width here on every update, so this
        -- is the moment to read it and then adjust it.
        hooksecurefunc("QuestLogQuests_ShowQuestCount", function()
            local sb = QuestScrollFrame and QuestScrollFrame.SearchBox
            if sb then searchBaseWidth = sb:GetWidth() end
            UpdateCompletedCount()
        end)
        hooked.count = true
    end
    if not hooked.map and WorldMapFrame and WorldMapFrame.HookScript then
        WorldMapFrame:HookScript("OnShow", function() C_Timer.After(0, Refresh) end)
        hooked.map = true
    end
    if not hooked.show and QuestScrollFrame and QuestScrollFrame.HookScript then
        QuestScrollFrame:HookScript("OnShow", function() C_Timer.After(0, Refresh) end)
        hooked.show = true
    end
end

local pending = false
local function ScheduleRefresh()
    if pending then return end
    pending = true
    C_Timer.After(0.05, function()
        pending = false
        Refresh()
    end)
end

local MODES = { both = true, check = true, text = true, off = true }

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_ENABLED") -- finish layout changes that waited for combat to end
frame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON_NAME then
        CamelusEnhancedQuestLogDB = CamelusEnhancedQuestLogDB or {}
        db = CamelusEnhancedQuestLogDB
        if not MODES[db.mode] then
            -- Settings from version 1.0 (separate check/text switches)
            if db.check == false and db.text == false then db.mode = "off"
            elseif db.check == false then db.mode = "text"
            elseif db.text == false then db.mode = "check"
            else db.mode = "both" end
        end
        db.check, db.text = nil, nil
        if db.level == nil then db.level = true end
        if db.showCount == nil then db.showCount = true end
        if db.showXP == nil then db.showXP = true end
        if db.replacePOI == nil then db.replacePOI = true end
        if db.color ~= "green" and db.color ~= "quest" then db.color = "green" end
    end
    if event == "ADDON_LOADED" or event == "PLAYER_LOGIN" then
        TryInstallHooks()
    end
    ScheduleRefresh()
end)

-- Safety net: while the quest log is open, re-check a few times per second.
-- Cheap, and catches redraws that don't go through the hooked function.
local elapsedTotal = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    elapsedTotal = elapsedTotal + elapsed
    if elapsedTotal < POLL_INTERVAL then return end
    elapsedTotal = 0
    if WorldMapFrame and WorldMapFrame:IsVisible() then Refresh() end
end)

------------------------------------------------------------------------
-- Slash commands
------------------------------------------------------------------------
local MODE_NAMES = {
    both  = "check mark and (Complete) text",
    check = "only check mark",
    text  = "only (Complete) text",
    off   = "nothing",
}

local function Describe(region)
    local name = region.GetName and region:GetName() or nil
    local s = region:GetObjectType() .. (name and (" " .. name) or "")
    if IsFontString(region) then
        s = s .. (" text=\"%s\" justify=%s/%s h=%.0f/%.0f"):format(tostring(region:GetText()),
            tostring(region:GetJustifyH()), tostring(region:GetJustifyV()),
            region:GetStringHeight() or 0, region:GetHeight() or 0)
    end
    s = s .. (region:IsShown() and " shown" or " hidden")
    if region.GetNumPoints then
        for i = 1, region:GetNumPoints() do
            local p, rel, rp, x, y = region:GetPoint(i)
            local relName = rel and (rel.GetName and rel:GetName() or rel:GetObjectType()) or "?"
            s = s .. (" @%s->%s:%s(%.0f,%.0f)"):format(tostring(p), tostring(relName), tostring(rp), x or 0, y or 0)
        end
    end
    return s
end

local function DumpRow(label, row)
    Print(label)
    local regions = { row:GetRegions() }
    for i = 1, #regions do
        if not ownRegions[regions[i]] then Print("    " .. Describe(regions[i])) end
    end
    local kids = { row:GetChildren() }
    for i = 1, #kids do Print("    child " .. Describe(kids[i])) end
end

local function Debug()
    Print(("client %s, interface %s"):format(GetBuildInfo(), tostring(select(4, GetBuildInfo()))))
    Print("QuestLogQuests_Update: " .. (type(QuestLogQuests_Update) == "function" and "found" or "NOT found")
        .. ", QuestScrollFrame: " .. (QuestScrollFrame and "found" or "NOT found"))
    Print("C_QuestLog.IsComplete: " .. ((C_QuestLog and C_QuestLog.IsComplete) and "found" or "NOT found")
        .. ", tag info: " .. (((C_QuestLog and C_QuestLog.GetQuestTagInfo) or GetQuestTagInfo) and "found" or "NOT found"))
    Print("Blizzard count box in use: " .. tostring(BlizzardCountBoxInUse())
        .. ", other addon's count: " .. (foreignCount and ("\"" .. tostring(foreignCount:GetText()) .. "\"") or "none"))
    Print("QuestLogCount: " .. (QuestLogCount and "found" or "NOT found")
        .. ", QuestLogQuestCount: " .. (QuestLogQuestCount and "found" or "NOT found")
        .. ", ShowQuestCount: " .. (type(QuestLogQuests_ShowQuestCount) == "function" and "found" or "NOT found")
        .. ", layout " .. (countLayout and "applied" or "not applied"))
    local count, withTag, completeNoTag = 0, nil, nil
    for _, root in ipairs(GetRoots()) do
        Scan(root, 0, function(b)
            count = count + 1
            local fs = GetTitleFontString(b)
            local _, tagText = FindBlizzardTag(b, fs)
            local status = QuestStatus(GetQuestID(b), b.questLogIndex)
            if tagText and not withTag then withTag = b end
            if status and not tagText and not completeNoTag then completeNoTag = b end
            if count <= 8 then
                Print(("  #%d id=%s status=%s tag=%s letter=%s ?-marker=%s \"%s\""):format(count,
                    tostring(GetQuestID(b)), tostring(status), tostring(tagText),
                    GetLevelLetter(GetQuestID(b), tagText),
                    FindPOIButton(GetQuestID(b)) and "yes" or "no", tostring(fs:GetText())))
            end
        end)
    end
    Print("quest title rows found: " .. count .. (count == 0 and " (open the quest log first)" or ""))
    if withTag then DumpRow("first row with a Blizzard tag:", withTag) end
    if completeNoTag then DumpRow("first completed row without a tag:", completeNoTag) end
end

------------------------------------------------------------------------
-- Options window
------------------------------------------------------------------------
local updaters = {}      -- functions that make the controls match db
local optionsWindow      -- the window /ceql opens
local settingsCategory   -- our page under Options -> AddOns (modern menu)

local function SyncControls()
    for i = 1, #updaters do updaters[i]() end
end

local function SettingsChanged()
    SyncControls()
    Refresh()
end

local function ShowsCheck() return db.mode == "both" or db.mode == "check" end
local function ShowsText()  return db.mode == "both" or db.mode == "text" end

local function SetMode(check, text)
    if check and text then db.mode = "both"
    elseif check then db.mode = "check"
    elseif text then db.mode = "text"
    else db.mode = "off" end
    SettingsChanged()
end

-- Creates a frame from a template, trying the templates in order, since
-- not every game version has every template.
local function CreateFromTemplates(frameType, parent, ...)
    for i = 1, select("#", ...) do
        local template = select(i, ...)
        local ok, f = pcall(CreateFrame, frameType, nil, parent, template)
        if ok and f then return f, template end
    end
    return CreateFrame(frameType, nil, parent), nil
end

local function AddLabel(button, text)
    local label = button:GetParent():CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", button, "RIGHT", 4, 0)
    label:SetText(text)
    local builtIn = button.text or button.Text
    if builtIn and builtIn ~= label then builtIn:SetText("") end
    -- Clicking the label also clicks the button.
    button:SetHitRectInsets(0, -((label:GetStringWidth() or 0) + 8), 0, 0)
    return label
end

-- The version from the .toc file, e.g. "1.6.1".
local function GetVersion()
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = getMetadata and SafeCall(getMetadata, ADDON_NAME, "Version")
    return type(version) == "string" and version ~= "" and version or nil
end

-- Builds all controls inside `parent`. top = y offset of the first line.
-- Returns the height used and a function that gives the width needed by
-- the widest line, so the window can be made wide enough for every label.
local function BuildOptions(parent, top, withTitle)
    local x, y = 16, top
    local lines = {} -- { left = offset from the left edge, fs = FontString }
    local function NeededWidth()
        local widest = 0
        for i = 1, #lines do
            widest = math.max(widest, lines[i].left + (lines[i].fs:GetStringWidth() or 0))
        end
        return widest
    end
    local function Header(text, gap)
        y = y - (gap or 0)
        local h = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        h:SetPoint("TOPLEFT", x, y)
        h:SetText(text)
        lines[#lines + 1] = { left = x, fs = h }
        y = y - 20
    end
    local function Button(kind, text, onClick)
        local b, labelLeft
        if kind == "radio" then
            b = CreateFromTemplates("CheckButton", parent, "UIRadioButtonTemplate", "UICheckButtonTemplate")
            b:SetSize(18, 18)
            b:SetPoint("TOPLEFT", x + 7, y - 3)
            labelLeft = x + 7 + 18 + 4
        else
            b = CreateFromTemplates("CheckButton", parent, "UICheckButtonTemplate")
            b:SetSize(26, 26)
            b:SetPoint("TOPLEFT", x + 2, y)
            labelLeft = x + 2 + 26 + 4
        end
        lines[#lines + 1] = { left = labelLeft, fs = AddLabel(b, text) }
        b:SetScript("OnClick", onClick)
        y = y - 26
        return b
    end

    if withTitle then
        local icon = parent:CreateTexture(nil, "ARTWORK")
        icon:SetTexture(ADDON_ICON)
        icon:SetSize(24, 24)
        icon:SetPoint("TOPLEFT", x, y + 4)
        local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        title:SetText("Camelus' Enhanced Quest Log")
        y = y - 32
    end

    Header("Completed quests")
    local checkBox = Button("check", "Show a check mark to the left of the title",
        function(b) SetMode(b:GetChecked() and true or false, ShowsText()) end)
    local replaceBox = Button("check", "Replace Blizzard's completed marker (?) with the check mark",
        function(b) db.replacePOI = b:GetChecked() and true or false; SettingsChanged() end)
    local textBox = Button("check", "Show (Complete) where (Dungeon) is shown",
        function(b) SetMode(ShowsCheck(), b:GetChecked() and true or false) end)

    Header("Colour of (Complete)", 8)
    local green = Button("radio", "|cff40ff40Green|r",
        function() db.color = "green"; SettingsChanged() end)
    local quest = Button("radio", "Same colour as the quest title",
        function() db.color = "quest"; SettingsChanged() end)

    Header("Quest title", 8)
    local level = Button("check", "Add D for dungeon and R for raid quests, e.g. [26D]",
        function(b) db.level = b:GetChecked() and true or false; SettingsChanged() end)
    local xpBox = Button("check", "Show the quest's XP after the title, e.g. (1,250 XP)",
        function(b) db.showXP = b:GetChecked() and true or false; SettingsChanged() end)

    Header("Quest count", 8)
    local countBox = Button("check", "Show how many quests are completed",
        function(b) db.showCount = b:GetChecked() and true or false; SettingsChanged() end)

    -- Preview of a completed dungeon quest with the current settings
    Header("Preview", 8)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(330, 20)
    row:SetPoint("TOPLEFT", x + 8, y - 2)
    local pCheck = row:CreateTexture(nil, "OVERLAY")
    pCheck:SetTexture(CHECK_TEXTURE)
    pCheck:SetSize(CHECK_SIZE, CHECK_SIZE)
    pCheck:SetPoint("LEFT", 0, 0)
    local pTitle = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    pTitle:SetPoint("LEFT", 20, 0)
    pTitle:SetTextColor(1, 0.5, 0.25) -- orange, like a quest a few levels above you
    local pTag = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    pTag:SetPoint("RIGHT", 0, 0)
    pTag:SetJustifyH("RIGHT")

    updaters[#updaters + 1] = function()
        if not db then return end
        checkBox:SetChecked(ShowsCheck())
        replaceBox:SetChecked(db.replacePOI)
        if replaceBox.SetEnabled then replaceBox:SetEnabled(ShowsCheck()) end
        textBox:SetChecked(ShowsText())
        green:SetChecked(db.color == "green")
        quest:SetChecked(db.color == "quest")
        level:SetChecked(db.level)
        xpBox:SetChecked(db.showXP)
        countBox:SetChecked(db.showCount)

        if ShowsCheck() then pCheck:Show() else pCheck:Hide() end
        pTitle:SetText((db.level and "[27D] The Day After" or "[27] The Day After") .. (db.showXP and XPSuffix(1250) or ""))
        if ShowsText() then
            pTag:SetText(TEXT_COMPLETE)
            if db.color == "quest" then pTag:SetTextColor(1, 0.5, 0.25)
            else pTag:SetTextColor(GREEN[1], GREEN[2], GREEN[3]) end
        else
            pTag:SetText("(Dungeon)")
            pTag:SetTextColor(1, 0.5, 0.25)
        end
    end
    -- Version in the bottom right corner, small and grey.
    local version = GetVersion()
    if version then
        local versionText = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        versionText:SetPoint("BOTTOMRIGHT", -14, 12)
        versionText:SetText("Version " .. version)
    end

    parent:HookScript("OnShow", SyncControls)
    return -y, NeededWidth
end

local function CreateOptionsWindow()
    local w, template = CreateFromTemplates("Frame", UIParent, "BasicFrameTemplateWithInset", "BackdropTemplate")
    w:SetSize(400, 10)
    w:SetPoint("CENTER")
    w:SetFrameStrata("DIALOG")
    w:SetToplevel(true)
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", w.StartMoving)
    w:SetScript("OnDragStop", w.StopMovingOrSizing)

    local top = -32
    local hasTitleBar = template == "BasicFrameTemplateWithInset" and w.TitleText ~= nil
    if hasTitleBar then
        w.TitleText:SetText("Camelus' Enhanced Quest Log")
        local icon = w:CreateTexture(nil, "OVERLAY")
        icon:SetTexture(ADDON_ICON)
        icon:SetSize(16, 16)
        icon:SetPoint("RIGHT", w.TitleText, "LEFT", -4, 0)
    elseif template ~= "BasicFrameTemplateWithInset" and w.SetBackdrop then
        -- Older look if the modern window template is missing
        w:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        local close = CreateFromTemplates("Button", w, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -6, -6)
        top = -18
    end
    local height, neededWidth = BuildOptions(w, top, not hasTitleBar)
    -- At least 400 wide, wider if a label needs it (16 px margin on the right).
    local function FitWidth() w:SetWidth(math.max(400, math.ceil(neededWidth() + 16))) end
    FitWidth()
    w:HookScript("OnShow", FitWidth)
    w:SetHeight(height + 58) -- room for the preview row and the version line
    w:Hide()

    -- Close with Escape
    _G.CamelusEnhancedQuestLogOptionsWindow = w
    tinsert(UISpecialFrames, "CamelusEnhancedQuestLogOptionsWindow")
    return w
end

local function OpenOptions()
    if not optionsWindow then optionsWindow = CreateOptionsWindow() end
    if optionsWindow:IsShown() then optionsWindow:Hide() else optionsWindow:Show() end
end

-- Page under Options -> AddOns (modern menu) or Interface -> AddOns (old menu)
local function RegisterSettingsPage()
    local panel = CreateFrame("Frame")
    panel.name = "Camelus' Enhanced Quest Log"
    BuildOptions(panel, -16, true)

    local openButton = CreateFromTemplates("Button", panel, "UIPanelButtonTemplate")
    openButton:SetSize(200, 24)
    openButton:SetPoint("TOPRIGHT", -16, -14)
    openButton:SetText("Open as separate window")
    openButton:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
        if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() and HideUIPanel then HideUIPanel(InterfaceOptionsFrame) end
        if not optionsWindow then optionsWindow = CreateOptionsWindow() end
        optionsWindow:Show()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(settingsCategory)
    elseif type(InterfaceOptions_AddCategory) == "function" then
        InterfaceOptions_AddCategory(panel)
    end
end

local optionsLoader = CreateFrame("Frame")
optionsLoader:RegisterEvent("PLAYER_LOGIN")
optionsLoader:SetScript("OnEvent", function()
    -- The addon used to be called "QuestLogCompleted" (up to 1.4.0) and
    -- "QuestLogCompletedMarker" (1.5.0 - 1.8.0). If an old folder is still
    -- installed, both would draw on the quest log.
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    for _, oldName in ipairs({ "QuestLogCompleted", "QuestLogCompletedMarker" }) do
        if isLoaded and isLoaded(oldName) then
            Print("|cffff4040the old \"" .. oldName .. "\" addon is also installed.|r "
                .. "Delete the Interface\\AddOns\\" .. oldName .. " folder, it has been replaced by this one.")
        end
    end
    local ok, err = pcall(RegisterSettingsPage)
    if not ok then Print("could not add the page under Options -> AddOns (" .. tostring(err) .. "). /ceql still works.") end
end)

------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------
SLASH_CAMELUSENHANCEDQUESTLOG1 = "/ceql"
SLASH_CAMELUSENHANCEDQUESTLOG2 = "/qlc" -- the old command keeps working
SlashCmdList.CAMELUSENHANCEDQUESTLOG = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" or msg == "options" or msg == "config" then
        OpenOptions()
        return
    elseif MODES[msg] then
        db.mode = msg
    elseif msg == "level" then
        db.level = not db.level
    elseif msg == "replace" then
        db.replacePOI = not db.replacePOI
    elseif msg == "xp" then
        db.showXP = not db.showXP
    elseif msg == "count" then
        db.showCount = not db.showCount
    elseif msg == "color" or msg == "colour" then
        db.color = (db.color == "green") and "quest" or "green"
    elseif msg == "color green" or msg == "colour green" then
        db.color = "green"
    elseif msg == "color quest" or msg == "colour quest" then
        db.color = "quest"
    elseif msg == "debug" then
        Debug()
        return
    else
        Print("/ceql  - open the options window")
        Print("/ceql both | check | text | off  - what to show on completed quests")
        Print("/ceql level  - toggle D/R after the level, e.g. [26D]")
        Print("/ceql replace  - toggle replacing Blizzard's \"?\" completed marker with the check mark")
        Print("/ceql xp  - toggle the quest's XP after the title, e.g. (1,950 XP)")
        Print("/ceql count  - toggle \"Quests completed\" under the quest count")
        Print("/ceql color  - (Complete) in green or in the quest's colour (/ceql color green | quest)")
        Print("/ceql debug  - troubleshooting info")
    end
    Print("showing: " .. MODE_NAMES[db.mode] .. "; level letter " ..
        (db.level and "|cff40ff40on|r" or "|cffff4040off|r") ..
        "; replace \"?\" " .. (db.replacePOI and "|cff40ff40on|r" or "|cffff4040off|r") ..
        "; XP " .. (db.showXP and "|cff40ff40on|r" or "|cffff4040off|r") ..
        "; completed count " .. (db.showCount and "|cff40ff40on|r" or "|cffff4040off|r") ..
        "; (Complete) colour: " .. (db.color == "green" and "|cff40ff40green|r" or "quest colour"))
    SettingsChanged()
end
