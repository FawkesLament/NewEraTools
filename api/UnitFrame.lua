local _, ns = ...

local UnitFrame = {}
ns.Api.UnitFrame = UnitFrame

local SINGLETON_NAMES = {
    "PlayerFrame",
    "PetFrame",
    "TargetFrame",
    "TargetFrameToT",
    "FocusFrame",
    "FocusFrameToT",
}

local compactHooked = false
---@type fun(frame: Frame)[]
local createdListeners = {}
local watchedClickCast
-- Compact frames seen through the setup hook, so ForEach reaches pools outside the name list.
---@type table<Frame, boolean>
local compactFrames = setmetatable({}, { __mode = "k" })
---@type fun(frame: Frame, key: string, value: any)[]
local attributeListeners = {}
-- Method hooks cannot be removed, so each frame is hooked at most once for its lifetime.
---@type table<Frame, boolean>
local attributeHooked = setmetatable({}, { __mode = "k" })

---@param frame any
---@return string|nil
local function FrameName(frame)
    if type(frame) ~= "table" and type(frame) ~= "userdata" then
        return nil
    end
    if type(frame.GetName) ~= "function" then
        return nil
    end
    local ok, name = pcall(frame.GetName, frame)
    if not ok or type(name) ~= "string" or name == "" then
        return nil
    end
    return name
end

---True when `frame` is a usable secure unit button. Nameplates and forbidden frames are excluded.
---@param frame any
---@return boolean
function UnitFrame.IsConfigurable(frame)
    if type(frame) ~= "table" and type(frame) ~= "userdata" then
        return false
    end
    if type(frame.GetAttribute) ~= "function" or type(frame.SetAttribute) ~= "function" then
        return false
    end
    if frame.IsForbidden then
        local ok, forbidden = pcall(frame.IsForbidden, frame)
        if ok and forbidden then
            return false
        end
    end
    if frame.namePlateUnitToken ~= nil then
        return false
    end
    local name = FrameName(frame)
    if name and name:find("^NamePlate") then
        return false
    end
    if frame.IsProtected then
        local ok, protected = pcall(frame.IsProtected, frame)
        if ok and protected == false then
            return false
        end
    end
    return true
end

---@param handler fun(frame: Frame)
---@param frame any
local function Emit(handler, frame)
    if UnitFrame.IsConfigurable(frame) then
        handler(frame)
    end
end

---@param handler fun(frame: Frame)
---@param name string
local function EmitNamed(handler, name)
    Emit(handler, _G[name])
end

---@param handler fun(frame: Frame)
---@param prefix string
---@param count integer
local function EmitIndexed(handler, prefix, count)
    for index = 1, count do
        EmitNamed(handler, prefix .. index)
    end
end

local function NotifyCreated(frame)
    if not UnitFrame.IsConfigurable(frame) then
        return
    end
    for i = 1, #createdListeners do
        createdListeners[i](frame)
    end
end

local function WatchClickCastFrames()
    local current = _G.ClickCastFrames
    if type(current) ~= "table" or watchedClickCast == current then
        return
    end

    local mt = getmetatable(current)
    if mt == nil then
        local ok = pcall(setmetatable, current, {
            __newindex = function(t, frame, value)
                rawset(t, frame, value)
                if value then
                    NotifyCreated(frame)
                end
            end,
        })
        if ok then
            watchedClickCast = current
        end
        return
    end

    if type(mt) ~= "table" or type(mt.__newindex) ~= "function" then
        return
    end
    if mt.__neweraToolsClickCast then
        watchedClickCast = current
        return
    end
    local previous = mt.__newindex
    local ok = pcall(function()
        mt.__newindex = function(t, frame, value)
            previous(t, frame, value)
            if value then
                NotifyCreated(frame)
            end
        end
        mt.__neweraToolsClickCast = true
    end)
    if ok then
        watchedClickCast = current
    end
end

local function HookCompactUnitFrames()
    if compactHooked or not hooksecurefunc or not _G.CompactUnitFrame_SetUpFrame then
        return
    end
    compactHooked = true
    hooksecurefunc("CompactUnitFrame_SetUpFrame", function(frame)
        if UnitFrame.IsConfigurable(frame) then
            compactFrames[frame] = true
        end
        NotifyCreated(frame)
    end)
end

---Invokes `handler(frame)` for known Blizzard unit frames, set-up compact frames, and current
---`ClickCastFrames` entries. A frame may be visited more than once.
---Only this walk is authoritative for `ClickCastFrames`: other addons may replace the table,
---`rawset` entries, or clear existing keys, none of which reach `OnCreated`.
---@param handler fun(frame: Frame)
function UnitFrame.ForEach(handler)
    WatchClickCastFrames()
    for i = 1, #SINGLETON_NAMES do
        EmitNamed(handler, SINGLETON_NAMES[i])
    end
    EmitIndexed(handler, "PartyMemberFrame", 4)
    for index = 1, 8 do
        EmitNamed(handler, "Boss" .. index .. "TargetFrame")
    end
    EmitIndexed(handler, "ArenaEnemyMatchFrame", 5)
    EmitIndexed(handler, "ArenaEnemyFrame", 5)
    EmitIndexed(handler, "CompactPartyFrameMember", 5)
    EmitIndexed(handler, "CompactArenaFrameMember", 5)
    EmitIndexed(handler, "CompactRaidFrame", 80)
    for group = 1, 8 do
        for member = 1, 5 do
            EmitNamed(handler, "CompactRaidGroup" .. group .. "Member" .. member)
        end
    end

    local party = _G.PartyFrame
    if type(party) == "table" then
        local pool = party.PartyMemberFramePool
        if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
            for member in pool:EnumerateActive() do
                Emit(handler, member)
                if type(member) == "table" or type(member) == "userdata" then
                    Emit(handler, member.PetFrame)
                end
            end
        end
        for index = 1, 5 do
            Emit(handler, party["MemberFrame" .. index])
        end
    end

    local bosses = _G.BossTargetFrameContainer
    if type(bosses) == "table" then
        for index = 1, 8 do
            Emit(handler, bosses["Boss" .. index])
        end
    end

    for frame in pairs(compactFrames) do
        Emit(handler, frame)
    end

    local clickCast = _G.ClickCastFrames
    if type(clickCast) == "table" then
        for frame, enabled in pairs(clickCast) do
            if enabled then
                Emit(handler, frame)
            end
        end
    end
end

local function NotifyAttributeSet(frame, key, value)
    for i = 1, #attributeListeners do
        attributeListeners[i](frame, key, value)
    end
end

---Reports later Lua `frame:SetAttribute` calls to `OnAttributeSet` listeners. Idempotent per frame.
---Writes made from secure snippets through frame handles are not observed.
---@param frame Frame
function UnitFrame.WatchAttributes(frame)
    if attributeHooked[frame] or not hooksecurefunc then
        return
    end
    attributeHooked[frame] = true
    hooksecurefunc(frame, "SetAttribute", NotifyAttributeSet)
end

---Calls `handler(frame, key, value)` after an attribute write on any watched frame,
---including writes made by the handler's own addon.
---@param handler fun(frame: Frame, key: string, value: any)
function UnitFrame.OnAttributeSet(handler)
    attributeListeners[#attributeListeners + 1] = handler
end

---Calls `handler(frame)` when a compact unit frame is set up or a new ClickCastFrames key is
---assigned. Best effort; pair with periodic `ForEach` to catch what this misses.
---@param handler fun(frame: Frame)
function UnitFrame.OnCreated(handler)
    createdListeners[#createdListeners + 1] = handler
    HookCompactUnitFrames()
    WatchClickCastFrames()
end
