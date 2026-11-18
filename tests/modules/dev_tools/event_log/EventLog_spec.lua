local Loader = require("helpers.loader")

describe("EventLog", function()
    local ns, Module, Encounter, GameEvents, Timer, Unit, savedIsSecret, secrets

    local function Secret()
        local value = setmetatable({}, {
            __eq = function()
                error("secret payload was read")
            end,
            __tostring = function()
                error("secret payload was read")
            end,
            __lt = function()
                error("secret payload was read")
            end,
        })
        secrets[value] = true
        return value
    end

    local function StartEncounter()
        Encounter.FireStart(1, "Boss", 16, 20)
    end

    local function EndEncounter()
        Encounter.FireEnd(1, "Boss", 16, 20, 1)
    end

    before_each(function()
        savedIsSecret = issecretvalue
        secrets = {}
        issecretvalue = function(value)
            return secrets[value] == true
        end
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("EventLog")
        Encounter = ns.Api.Encounter
        GameEvents = ns.Api.GameEvents
        Timer = ns.Api.Timer
        Unit = ns.Api.Unit
        Module:StartListening()
        Unit.SetForTests("boss1", { exists = true, isEnemy = true })
        Unit.SetForTests("player", { exists = true, isEnemy = false })
        Timer.now = 10
    end)

    after_each(function()
        issecretvalue = savedIsSecret
    end)

    it("starts off with no saved logs", function()
        assert.is_false(Module:IsEnabled())
        assert.equals(1, Module:GetMaxLogs())
        assert.same({}, Module:GetSavedLogs())
        assert.same({}, Module:GetLines())
        assert.is_nil(Module:GetLogText())
    end)

    it("does not record while disabled", function()
        StartEncounter()
        GameEvents.Fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        assert.same({}, Module:GetLines())
        assert.same({}, Module:GetSavedLogs())
    end)

    it("does not record until the next encounter start after enabling", function()
        StartEncounter()
        Module:SetEnabled(true)
        GameEvents.Fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        assert.same({}, Module:GetLines())
    end)

    describe("while enabled in an encounter", function()
        before_each(function()
            Module:SetEnabled(true)
            StartEncounter()
        end)

        it("records the event name, relative timestamp, and payload values", function()
            Timer.now = 12.25
            GameEvents.Fire("UNIT_SPELLCAST_SUCCEEDED", "boss1", "Cast-1", 441395)
            assert.same({ "UNIT_SPELLCAST_SUCCEEDED 2.250 boss1 Cast-1 441395" }, Module:GetLines())
        end)

        it("records an event with no payload", function()
            GameEvents.Fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
            assert.same({ "INSTANCE_ENCOUNTER_ENGAGE_UNIT 0.000" }, Module:GetLines())
        end)

        it("keeps a nil payload slot", function()
            GameEvents.Fire("ENCOUNTER_STATE_CHANGED", "a", nil, "b")
            assert.same({ "ENCOUNTER_STATE_CHANGED 0.000 a nil b" }, Module:GetLines())
        end)

        it("flattens table payloads and substitutes secrets", function()
            Timer.now = 11
            GameEvents.Fire("ENCOUNTER_TIMELINE_EVENT_ADDED", {
                id = 8,
                spellID = 123,
                text = Secret(),
            })
            assert.same({ "ENCOUNTER_TIMELINE_EVENT_ADDED 1.000 8 123 <secret>" }, Module:GetLines())
        end)

        it("ignores friendly and secret-token spellcasts", function()
            GameEvents.Fire("UNIT_SPELLCAST_START", "player", "Cast-player", 1)
            GameEvents.Fire("UNIT_SPELLCAST_CHANNEL_START", Secret(), "Cast-secret", 2)
            GameEvents.Fire("UNIT_SPELLCAST_STOP", "boss1", "Cast-boss", 3)
            assert.same({ "UNIT_SPELLCAST_STOP 0.000 boss1 Cast-boss 3" }, Module:GetLines())
        end)

        it("ignores friendly and secret-token nameplates", function()
            Unit.SetForTests("nameplate1", { exists = true, isEnemy = false })
            Unit.SetForTests("nameplate2", { exists = true, isEnemy = true })
            GameEvents.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
            GameEvents.Fire("NAME_PLATE_UNIT_ADDED", Secret())
            GameEvents.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
            GameEvents.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
            GameEvents.Fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
            assert.same({
                "NAME_PLATE_UNIT_ADDED 0.000 nameplate2",
                "NAME_PLATE_UNIT_REMOVED 0.000 nameplate2",
            }, Module:GetLines())
        end)

        it("replaces the only log when a new encounter starts with the default limit", function()
            GameEvents.Fire("ENCOUNTER_WARNING", { text = "first" })
            Timer.now = 40
            StartEncounter()
            GameEvents.Fire("ENCOUNTER_STATE_CHANGED", 2)
            assert.equals(1, #Module:GetSavedLogs())
            assert.same({ "ENCOUNTER_STATE_CHANGED 0.000 2" }, Module:GetLines())
        end)

        it("stops recording after the encounter ends", function()
            GameEvents.Fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
            EndEncounter()
            GameEvents.Fire("INSTANCE_ENCOUNTER_OBJECTIVE_START", 1)
            assert.same({ "INSTANCE_ENCOUNTER_ENGAGE_UNIT 0.000" }, Module:GetLines())
        end)

        it("stops recording when disabled mid-encounter", function()
            GameEvents.Fire("INSTANCE_ENCOUNTER_ADD_TIMER", 5)
            Module:SetEnabled(false)
            GameEvents.Fire("INSTANCE_ENCOUNTER_OBJECTIVE_UPDATE", 1)
            assert.same({ "INSTANCE_ENCOUNTER_ADD_TIMER 0.000 5" }, Module:GetLines())
        end)

        it("does not stack listeners across pulls", function()
            EndEncounter()
            Timer.now = 50
            StartEncounter()
            GameEvents.Fire("ENCOUNTER_TIMELINE_EVENT_REMOVED", 9)
            assert.same({ "ENCOUNTER_TIMELINE_EVENT_REMOVED 0.000 9" }, Module:GetLines())
        end)

        it("saves encounter identity, ISO start time, and duration once the encounter ends", function()
            ns.Api.Client.calendarTime = {
                year = 2026,
                month = 1,
                monthDay = 2,
                hour = 8,
                minute = 3,
                second = 4,
            }
            Timer.now = 100
            Encounter.FireStart(3134, "Coiled Altar", 16, 20)
            GameEvents.Fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
            local saved = Module:GetSavedLogs()
            assert.equals(1, #saved)
            local id = saved[1].id
            assert.same({
                id = id,
                encounterID = 3134,
                encounterName = "Coiled Altar",
                startedAt = "2026-01-02T08:03:04",
            }, saved[1])
            assert.equals("INSTANCE_ENCOUNTER_ENGAGE_UNIT 0.000", Module:GetLogText(id))

            Timer.now = 372.5
            EndEncounter()
            assert.equals(272.5, Module:GetSavedLogs()[1].duration)
        end)

        it("leaves the encounter name unset when the game hides it", function()
            Encounter.FireStart(7, Secret(), 16, 20)
            assert.is_nil(Module:GetSavedLogs()[1].encounterName)
            assert.equals(7, Module:GetSavedLogs()[1].encounterID)
        end)

        it("stamps the duration when disabled mid-encounter", function()
            Timer.now = 25
            Module:SetEnabled(false)
            assert.equals(15, Module:GetSavedLogs()[1].duration)
        end)

        it("notifies when a log starts and when it finishes", function()
            local seen = 0
            function Module:OnSavedLogChanged()
                seen = seen + 1
            end
            Encounter.FireStart(2, "Boss", 16, 20)
            assert.equals(1, seen)
            EndEncounter()
            assert.equals(2, seen)
            EndEncounter()
            assert.equals(2, seen)
        end)
    end)

    describe("with several logs kept", function()
        local function Pull(encounterID, marker)
            Encounter.FireStart(encounterID, "Boss " .. encounterID, 16, 20)
            GameEvents.Fire("ENCOUNTER_STATE_CHANGED", marker)
            Timer.now = Timer.now + 30
            Encounter.FireEnd(encounterID, "Boss " .. encounterID, 16, 20, 1)
        end

        local function SavedIDs()
            local ids = {}
            for i, saved in ipairs(Module:GetSavedLogs()) do
                ids[i] = saved.encounterID
            end
            return ids
        end

        before_each(function()
            Module:SetEnabled(true)
            Module:SetMaxLogs(3)
        end)

        it("lists logs newest first, each with its own lines", function()
            Pull(1, "a")
            Pull(2, "b")
            assert.same({ 2, 1 }, SavedIDs())
            local saved = Module:GetSavedLogs()
            assert.equals("ENCOUNTER_STATE_CHANGED 0.000 b", Module:GetLogText(saved[1].id))
            assert.equals("ENCOUNTER_STATE_CHANGED 0.000 a", Module:GetLogText(saved[2].id))
        end)

        it("drops the oldest log when a new encounter starts with the list full", function()
            Pull(1, "a")
            local oldestID = Module:GetSavedLogs()[1].id
            Pull(2, "b")
            Pull(3, "c")
            Pull(4, "d")
            assert.same({ 4, 3, 2 }, SavedIDs())
            assert.is_nil(Module:GetLogText(oldestID))
        end)

        it("drops the oldest logs right away when the limit is lowered", function()
            Pull(1, "a")
            Pull(2, "b")
            Pull(3, "c")
            local seen = 0
            function Module:OnSavedLogChanged()
                seen = seen + 1
            end
            Module:SetMaxLogs(1)
            assert.same({ 3 }, SavedIDs())
            assert.equals(1, seen)
            Module:SetMaxLogs(5)
            assert.same({ 3 }, SavedIDs())
            assert.equals(1, seen)
        end)

        it("keeps the limit within 1 to 20 whole logs", function()
            Module:SetMaxLogs(0)
            assert.equals(1, Module:GetMaxLogs())
            Module:SetMaxLogs(99)
            assert.equals(20, Module:GetMaxLogs())
            Module:SetMaxLogs(4.4)
            assert.equals(4, Module:GetMaxLogs())
        end)
    end)
end)
