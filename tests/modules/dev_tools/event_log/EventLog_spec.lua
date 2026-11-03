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

    it("starts off with an empty log", function()
        assert.is_false(Module:IsEnabled())
        assert.same({}, Module:GetLines())
        assert.equals("", Module:GetLogText())
        assert.is_nil(Module:GetSavedLog())
    end)

    it("does not record while disabled", function()
        StartEncounter()
        GameEvents.Fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        assert.same({}, Module:GetLines())
        assert.is_nil(Module:GetSavedLog())
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

        it("clears previous lines when a new encounter starts", function()
            GameEvents.Fire("ENCOUNTER_WARNING", { text = "first" })
            Timer.now = 40
            StartEncounter()
            GameEvents.Fire("ENCOUNTER_STATE_CHANGED", 2)
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

        it("saves encounter ID and wall-clock start time", function()
            ns.Api.Client.calendarTime = {
                year = 2026,
                month = 11,
                monthDay = 2,
                hour = 18,
                minute = 53,
                second = 4,
            }
            Encounter.FireStart(3134, "Boss", 16, 20)
            GameEvents.Fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
            assert.same({
                encounterID = 3134,
                startedAt = "26-11-02-18:53:04",
            }, Module:GetSavedLog())
            assert.equals("INSTANCE_ENCOUNTER_ENGAGE_UNIT 0.000", Module:GetLogText())
            EndEncounter()
            assert.same({
                encounterID = 3134,
                startedAt = "26-11-02-18:53:04",
            }, Module:GetSavedLog())
        end)

        it("notifies when a new log is saved", function()
            local seen = 0
            function Module:OnSavedLogChanged()
                seen = seen + 1
            end
            Encounter.FireStart(2, "Boss", 16, 20)
            assert.equals(1, seen)
        end)
    end)
end)
