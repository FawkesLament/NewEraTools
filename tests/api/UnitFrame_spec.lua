-- Production api/UnitFrame.lua. Feature specs keep tests/helpers/fakes/UnitFrame.lua.

local function Load()
    local ns = { Api = {} }
    assert(loadfile("api/UnitFrame.lua"))("NewEraTools", ns)
    return ns.Api.UnitFrame
end

local function Button(name, extras)
    local frame = {
        name = name,
        attributes = {},
        forbidden = extras and extras.forbidden,
        protected = extras and extras.protected,
        namePlateUnitToken = extras and extras.namePlateUnitToken,
    }
    function frame:GetName()
        return self.name
    end
    function frame:GetAttribute(key)
        return self.attributes[key]
    end
    function frame:SetAttribute(key, value)
        self.attributes[key] = value
    end
    function frame:IsForbidden()
        return self.forbidden == true
    end
    function frame:IsProtected()
        return self.protected ~= false
    end
    return frame
end

describe("UnitFrame production", function()
    local UnitFrame
    local saved = {}

    local function SaveGlobals()
        saved.PlayerFrame = _G.PlayerFrame
        saved.TargetFrame = _G.TargetFrame
        saved.ClickCastFrames = _G.ClickCastFrames
        saved.PartyFrame = _G.PartyFrame
        saved.BossTargetFrameContainer = _G.BossTargetFrameContainer
        saved.CompactRaidFrame1 = _G.CompactRaidFrame1
        saved.hooksecurefunc = hooksecurefunc
        saved.CompactUnitFrame_SetUpFrame = _G.CompactUnitFrame_SetUpFrame
    end

    before_each(function()
        SaveGlobals()
        _G.PlayerFrame = nil
        _G.TargetFrame = nil
        _G.ClickCastFrames = nil
        _G.PartyFrame = nil
        _G.BossTargetFrameContainer = nil
        _G.CompactRaidFrame1 = nil
        local hooks = {}
        hooksecurefunc = function(name, fn, post)
            if type(name) == "table" then
                local target, method = name, fn
                local original = target[method]
                target[method] = function(...)
                    original(...)
                    post(...)
                end
                return
            end
            hooks[name] = hooks[name] or {}
            table.insert(hooks[name], fn)
        end
        _G.CompactUnitFrame_SetUpFrame = function(frame)
            local list = hooks.CompactUnitFrame_SetUpFrame
            if not list then
                return
            end
            for i = 1, #list do
                list[i](frame)
            end
        end
        UnitFrame = Load()
    end)

    after_each(function()
        _G.PlayerFrame = saved.PlayerFrame
        _G.TargetFrame = saved.TargetFrame
        _G.ClickCastFrames = saved.ClickCastFrames
        _G.PartyFrame = saved.PartyFrame
        _G.BossTargetFrameContainer = saved.BossTargetFrameContainer
        _G.CompactRaidFrame1 = saved.CompactRaidFrame1
        hooksecurefunc = saved.hooksecurefunc
        _G.CompactUnitFrame_SetUpFrame = saved.CompactUnitFrame_SetUpFrame
    end)

    it("accepts protected unit buttons and rejects nameplates, forbidden, and unprotected frames", function()
        assert.is_true(UnitFrame.IsConfigurable(Button("PlayerFrame")))
        assert.is_false(UnitFrame.IsConfigurable(nil))
        assert.is_false(UnitFrame.IsConfigurable({}))
        assert.is_false(UnitFrame.IsConfigurable(Button("NamePlate1")))
        assert.is_false(UnitFrame.IsConfigurable(Button("NamePlate2", { namePlateUnitToken = "nameplate2" })))
        assert.is_false(UnitFrame.IsConfigurable(Button("PlayerFrame", { forbidden = true })))
        assert.is_false(UnitFrame.IsConfigurable(Button("PlayerFrame", { protected = false })))
    end)

    it("walks named Blizzard frames, party members, and ClickCastFrames", function()
        local player = Button("PlayerFrame")
        local target = Button("TargetFrame")
        local party = Button("PartyMember1")
        local elv = Button("ElvUF_Player")
        _G.PlayerFrame = player
        _G.TargetFrame = target
        _G.PartyFrame = {
            MemberFrame1 = party,
        }
        _G.ClickCastFrames = { [elv] = true }
        local seen = {}
        UnitFrame.ForEach(function(frame)
            seen[#seen + 1] = frame
        end)
        assert.same({ player, target, party, elv }, seen)
    end)

    it("notifies when a compact unit frame is set up", function()
        local seen = {}
        UnitFrame.OnCreated(function(frame)
            seen[#seen + 1] = frame
        end)
        local raid = Button("CompactRaidFrame1")
        _G.CompactUnitFrame_SetUpFrame(raid)
        assert.same({ raid }, seen)
        _G.CompactUnitFrame_SetUpFrame(Button("NamePlate3"))
        assert.same({ raid }, seen)
    end)

    it("keeps walking compact frames the setup hook reported, even outside the name list", function()
        UnitFrame.OnCreated(function() end)
        local pet = Button("CompactPartyFramePet1")
        _G.CompactUnitFrame_SetUpFrame(pet)
        _G.CompactUnitFrame_SetUpFrame(Button("NamePlate4"))
        local seen = {}
        UnitFrame.ForEach(function(frame)
            seen[#seen + 1] = frame
        end)
        assert.same({ pet }, seen)
    end)

    it("follows a replaced ClickCastFrames table and sees rawset or cleared entries on the next walk", function()
        _G.ClickCastFrames = {}
        local notified = {}
        UnitFrame.OnCreated(function(frame)
            notified[#notified + 1] = frame
        end)
        UnitFrame.ForEach(function() end)

        -- A click-cast addon swaps in its own metatable-backed table, as DandersFrames does.
        local ownerSaw = {}
        local replacement = setmetatable({}, {
            __newindex = function(t, frame, value)
                rawset(t, frame, value)
                ownerSaw[#ownerSaw + 1] = frame
            end,
        })
        _G.ClickCastFrames = replacement
        local silent = Button("DFParty1")
        rawset(replacement, silent, true)

        local walked = {}
        UnitFrame.ForEach(function(frame)
            walked[#walked + 1] = frame
        end)
        assert.same({ silent }, walked)
        assert.same({}, notified)

        local late = Button("DFParty2")
        replacement[late] = true
        assert.same({ late }, ownerSaw)
        assert.same({ late }, notified)

        replacement[silent] = false
        walked = {}
        UnitFrame.ForEach(function(frame)
            walked[#walked + 1] = frame
        end)
        assert.same({ late }, walked)
    end)

    it("reports attribute writes on watched frames once, however often a frame is watched", function()
        local seen = {}
        UnitFrame.OnAttributeSet(function(frame, key, value)
            seen[#seen + 1] = { frame.name, key, value }
        end)
        local target = Button("TargetFrame")
        local other = Button("FocusFrame")
        target:SetAttribute("shift-type1", "early")
        UnitFrame.WatchAttributes(target)
        UnitFrame.WatchAttributes(target)
        target:SetAttribute("shift-type1", "")
        other:SetAttribute("shift-type1", "")
        assert.same({ { "TargetFrame", "shift-type1", "" } }, seen)
        assert.equals("", target:GetAttribute("shift-type1"))
    end)

    it("notifies when ClickCastFrames gains a frame", function()
        _G.ClickCastFrames = {}
        local seen = {}
        UnitFrame.OnCreated(function(frame)
            seen[#seen + 1] = frame
        end)
        UnitFrame.ForEach(function() end)
        local cell = Button("CellParty1")
        _G.ClickCastFrames[cell] = true
        assert.same({ cell }, seen)
    end)
end)
