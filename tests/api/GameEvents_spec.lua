-- Production api/GameEvents.lua. Feature specs keep tests/helpers/fakes/GameEvents.lua.
-- CreateFrame is a stand-in. Each load gets its own handler tables.

local function Load()
    local frames = {}
    CreateFrame = function()
        local frame = {
            events = {},
            unitEvents = {},
        }
        function frame:SetScript(name, handler)
            self.scripts = self.scripts or {}
            self.scripts[name] = handler
        end
        function frame:RegisterEvent(event)
            self.events[event] = true
            self.unitEvents[event] = nil
        end
        function frame:RegisterUnitEvent(event, ...)
            self.unitEvents[event] = { ... }
            self.events[event] = nil
        end
        function frame:UnregisterEvent(event)
            self.events[event] = nil
            self.unitEvents[event] = nil
        end
        function frame:Fire(event, ...)
            self.scripts.OnEvent(self, event, ...)
        end
        frames[#frames + 1] = frame
        return frame
    end

    local ns = { Api = {} }
    assert(loadfile("api/GameEvents.lua"))("NewEraTools", ns)
    return ns.Api.GameEvents, frames
end

describe("GameEvents production", function()
    local GameEvents, frames
    local savedCreateFrame

    before_each(function()
        savedCreateFrame = CreateFrame
        GameEvents, frames = Load()
    end)

    after_each(function()
        CreateFrame = savedCreateFrame
    end)

    it("registers one frame and unregisters an event when its last handler leaves", function()
        local calls = 0
        local unsubscribe = GameEvents.Listen("GROUP_ROSTER_UPDATE", function()
            calls = calls + 1
        end)
        local frame = frames[1]
        assert.equals(1, #frames)
        assert.is_true(frame.events.GROUP_ROSTER_UPDATE)

        frame:Fire("GROUP_ROSTER_UPDATE", "payload")
        assert.equals(1, calls)

        unsubscribe()
        unsubscribe()
        assert.is_nil(frame.events.GROUP_ROSTER_UPDATE)
        frame:Fire("GROUP_ROSTER_UPDATE")
        assert.equals(1, calls)

        GameEvents.Listen("PARTY_LEADER_CHANGED", function() end)
        assert.equals(1, #frames)
        assert.is_true(frame.events.PARTY_LEADER_CHANGED)
    end)

    it("calls handlers in subscription order with the event payload", function()
        local seen = {}
        GameEvents.Listen("PLAYER_REGEN_DISABLED", function(first, second)
            seen[#seen + 1] = "A" .. tostring(first) .. tostring(second)
        end)
        GameEvents.Listen("PLAYER_REGEN_DISABLED", function()
            seen[#seen + 1] = "B"
        end)
        GameEvents.Listen("PLAYER_ENTERING_WORLD", function()
            seen[#seen + 1] = "other"
        end)
        GameEvents.Listen("PLAYER_REGEN_DISABLED", function()
            seen[#seen + 1] = "C"
        end)

        frames[1]:Fire("PLAYER_REGEN_DISABLED", 1, 2)
        assert.same({ "A12", "B", "C" }, seen)
    end)

    it("still runs handlers that unsubscribe during this dispatch", function()
        local seen = {}
        local unsubscribeA, unsubscribeB, unsubscribeC
        unsubscribeA = GameEvents.Listen("ENCOUNTER_START", function()
            seen[#seen + 1] = "A"
            unsubscribeB()
            unsubscribeC()
        end)
        unsubscribeB = GameEvents.Listen("ENCOUNTER_START", function()
            seen[#seen + 1] = "B"
        end)
        unsubscribeC = GameEvents.Listen("ENCOUNTER_START", function()
            seen[#seen + 1] = "C"
        end)

        frames[1]:Fire("ENCOUNTER_START")
        assert.same({ "A", "B", "C" }, seen)

        frames[1]:Fire("ENCOUNTER_START")
        assert.same({ "A", "B", "C", "A" }, seen)
        unsubscribeA()
    end)

    it("still runs later handlers when an earlier one removes itself", function()
        local seen = {}
        local unsubscribeA
        unsubscribeA = GameEvents.Listen("ENCOUNTER_END", function()
            seen[#seen + 1] = "A"
            unsubscribeA()
        end)
        GameEvents.Listen("ENCOUNTER_END", function()
            seen[#seen + 1] = "B"
        end)
        GameEvents.Listen("ENCOUNTER_END", function()
            seen[#seen + 1] = "C"
        end)

        frames[1]:Fire("ENCOUNTER_END")
        assert.same({ "A", "B", "C" }, seen)

        frames[1]:Fire("ENCOUNTER_END")
        assert.same({ "A", "B", "C", "B", "C" }, seen)
    end)

    it("does not call a handler added during the current dispatch", function()
        local seen = {}
        GameEvents.Listen("CHAT_MSG_ADDON", function()
            seen[#seen + 1] = "A"
            GameEvents.Listen("CHAT_MSG_ADDON", function()
                seen[#seen + 1] = "D"
            end)
        end)
        GameEvents.Listen("CHAT_MSG_ADDON", function()
            seen[#seen + 1] = "B"
        end)

        frames[1]:Fire("CHAT_MSG_ADDON")
        assert.same({ "A", "B" }, seen)

        frames[1]:Fire("CHAT_MSG_ADDON")
        assert.same({ "A", "B", "A", "B", "D" }, seen)
    end)

    it("rejects a ListenUnit subscription without a unit token", function()
        local emptyOk, emptyErr = pcall(GameEvents.ListenUnit, "UNIT_AURA", "", function() end)
        local nilOk, nilErr = pcall(GameEvents.ListenUnit, "UNIT_AURA", nil, function() end)
        assert.is_false(emptyOk)
        assert.is_false(nilOk)
        assert.is_true(tostring(emptyErr):find("requires a unit", 1, true) ~= nil)
        assert.is_true(tostring(nilErr):find("requires a unit", 1, true) ~= nil)
        assert.equals(0, #frames)
    end)

    it("registers a single unit token with RegisterUnitEvent", function()
        local seen = {}
        local unsubscribe = GameEvents.ListenUnit("UNIT_AURA", "target", function(unit, spellId)
            seen[#seen + 1] = unit .. ":" .. tostring(spellId)
        end)
        local frame = frames[1]
        assert.same({ "target" }, frame.unitEvents.UNIT_AURA)
        assert.is_nil(frame.events.UNIT_AURA)

        frame:Fire("UNIT_AURA", "target", 774)
        assert.same({ "target:774" }, seen)

        unsubscribe()
        assert.is_nil(frame.unitEvents.UNIT_AURA)
        assert.is_nil(frame.events.UNIT_AURA)
    end)

    it("registers each distinct unit once and drops a token when its handlers are gone", function()
        local unsubscribePlayer = GameEvents.ListenUnit("UNIT_FLAGS", "player", function() end)
        GameEvents.ListenUnit("UNIT_FLAGS", "target", function() end)
        local unsubscribePlayerAgain = GameEvents.ListenUnit("UNIT_FLAGS", "player", function() end)
        local frame = frames[1]
        assert.same({ "player", "target" }, frame.unitEvents.UNIT_FLAGS)
        assert.is_nil(frame.events.UNIT_FLAGS)

        -- Order follows the handlers that remain, not the first time each token was seen.
        unsubscribePlayer()
        assert.same({ "target", "player" }, frame.unitEvents.UNIT_FLAGS)

        unsubscribePlayerAgain()
        assert.same({ "target" }, frame.unitEvents.UNIT_FLAGS)
        assert.is_nil(frame.events.UNIT_FLAGS)
    end)

    it("delivers a unit event only to ListenUnit callbacks for that token", function()
        local seen = {}
        local function Record(name)
            return function()
                seen[#seen + 1] = name
            end
        end
        GameEvents.ListenUnit("UNIT_FACTION", "player", Record("player"))
        GameEvents.ListenUnit("UNIT_FACTION", "target", Record("target"))
        GameEvents.ListenUnit("UNIT_FACTION", "focus", Record("focus"))
        local frame = frames[1]

        frame:Fire("UNIT_FACTION", "target")
        assert.same({ "target" }, seen)

        frame:Fire("UNIT_FACTION", "player")
        assert.same({ "target", "player" }, seen)
    end)

    it("delivers a unit event to every callback subscribed to that token", function()
        local seen = {}
        GameEvents.ListenUnit("UNIT_FACTION", "target", function(unit)
            seen[#seen + 1] = "A:" .. unit
        end)
        GameEvents.ListenUnit("UNIT_FACTION", "player", function()
            seen[#seen + 1] = "player"
        end)
        GameEvents.ListenUnit("UNIT_FACTION", "target", function(unit, extra)
            seen[#seen + 1] = "B:" .. unit .. ":" .. tostring(extra)
        end)

        frames[1]:Fire("UNIT_FACTION", "target", 7)
        assert.same({ "A:target", "B:target:7" }, seen)
    end)

    it("snapshots unit handlers and still skips a token that does not match", function()
        local seen = {}
        local unsubscribeC
        GameEvents.ListenUnit("UNIT_FLAGS", "target", function()
            seen[#seen + 1] = "A"
            unsubscribeC()
        end)
        GameEvents.ListenUnit("UNIT_FLAGS", "player", function()
            seen[#seen + 1] = "player"
        end)
        unsubscribeC = GameEvents.ListenUnit("UNIT_FLAGS", "target", function()
            seen[#seen + 1] = "C"
        end)

        frames[1]:Fire("UNIT_FLAGS", "target")
        assert.same({ "A", "C" }, seen)

        frames[1]:Fire("UNIT_FLAGS", "target")
        assert.same({ "A", "C", "A" }, seen)
    end)

    it("stops delivering a unit after its listeners unsubscribe", function()
        local seen = {}
        local unsubscribeTarget = GameEvents.ListenUnit("UNIT_FLAGS", "target", function()
            seen[#seen + 1] = "target"
        end)
        GameEvents.ListenUnit("UNIT_FLAGS", "player", function()
            seen[#seen + 1] = "player"
        end)
        unsubscribeTarget()
        local frame = frames[1]
        assert.same({ "player" }, frame.unitEvents.UNIT_FLAGS)

        frame:Fire("UNIT_FLAGS", "target")
        assert.same({}, seen)

        frame:Fire("UNIT_FLAGS", "player")
        assert.same({ "player" }, seen)
    end)

    -- One frame cannot RegisterEvent and RegisterUnitEvent for the same event.
    -- RegisterUnitEvent would hide units a plain Listen must still receive, so a mixed
    -- subscription uses RegisterEvent. ListenUnit filters on the unit argument either way.
    it("uses RegisterEvent when Listen and ListenUnit share an event", function()
        local seen = {}
        local unsubscribePlain = GameEvents.Listen("UNIT_FACTION", function(unit)
            seen[#seen + 1] = "plain:" .. tostring(unit)
        end)
        local unsubscribeFocus = GameEvents.ListenUnit("UNIT_FACTION", "focus", function(unit)
            seen[#seen + 1] = "focus:" .. tostring(unit)
        end)
        local frame = frames[1]
        assert.is_true(frame.events.UNIT_FACTION)
        assert.is_nil(frame.unitEvents.UNIT_FACTION)

        frame:Fire("UNIT_FACTION", "focus")
        assert.same({ "plain:focus", "focus:focus" }, seen)

        frame:Fire("UNIT_FACTION", "party1")
        assert.same({ "plain:focus", "focus:focus", "plain:party1" }, seen)

        unsubscribeFocus()
        assert.is_true(frame.events.UNIT_FACTION)
        assert.is_nil(frame.unitEvents.UNIT_FACTION)

        unsubscribePlain()
        GameEvents.ListenUnit("UNIT_FACTION", "player", function() end)
        assert.same({ "player" }, frame.unitEvents.UNIT_FACTION)
        assert.is_nil(frame.events.UNIT_FACTION)
    end)
end)
