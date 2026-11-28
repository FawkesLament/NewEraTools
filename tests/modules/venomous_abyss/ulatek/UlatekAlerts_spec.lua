local Loader = require("helpers.loader")

describe("Ulatek alerts", function()
    local ns, Module, Encounter, Timer, CalloutManager, Instance, L

    local HEROIC_WAVES = { 48, 100, 416.7, 471.7, 521.7, 566.7 }
    local MYTHIC_WAVES = { 56, 113, 426.7, 481.6, 531.7, 575.7 }
    local MYTHIC_EGG = { 29, 113 }
    local MYTHIC_WRETCH = { 38.4, 70.5, 107.8, 140.3 }
    local WAVES_LEAD = 5
    local EGG_LEAD = 8
    local WRETCH_LEAD = 8

    local function StartEncounter(difficultyID)
        Encounter.FireStart(Module.ENCOUNTER_ID, "Ulatek", difficultyID, 20)
    end

    local function EndEncounter(difficultyID)
        Encounter.FireEnd(Module.ENCOUNTER_ID, "Ulatek", difficultyID, 20, 1)
    end

    local function AdvanceTo(absoluteTime)
        Timer.Advance(absoluteTime - Timer.GetTime())
    end

    local function EnableAll()
        Module:SetCausticWavesReminderEnabled(true)
        Module:SetEggDeadlineReminderEnabled(true)
        Module:SetWretchAoeReminderEnabled(true)
    end

    ---@return table<string, { text: any, expiresAt: number, source: string, appendTimer: boolean }>
    local function ActiveByText()
        local byText = {}
        local active = CalloutManager.GetActive()
        for index = 1, #active do
            local message = active[index]
            if message.source == "Ulatek" then
                byText[message.text] = message
            end
        end
        return byText
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        Module = ns.Modules.Get("Ulatek")
        Encounter = ns.Api.Encounter
        Timer = ns.Api.Timer
        CalloutManager = ns.CalloutManager
        Instance = ns.Api.Instance
        L = ns.L
        Module:ListenForEncounter()
    end)

    it("ignores encounters other than 3492", function()
        EnableAll()
        Encounter.FireStart(1, "Other", Instance.DIFFICULTY_MYTHIC_RAID, 20)
        Timer.Advance(MYTHIC_EGG[1])
        assert.is_nil(CalloutManager.GetDisplayed())
    end)

    it("ignores difficulties below Heroic", function()
        EnableAll()
        StartEncounter(14)
        Timer.Advance(HEROIC_WAVES[1])
        assert.is_nil(CalloutManager.GetDisplayed())
        EndEncounter(14)
        StartEncounter(17)
        Timer.Advance(HEROIC_WAVES[1])
        assert.is_nil(CalloutManager.GetDisplayed())
    end)

    describe("Heroic", function()
        local function StartHeroic()
            StartEncounter(Instance.DIFFICULTY_HEROIC_RAID)
        end

        it("shows Caustic Waves 5s before the first hit", function()
            Module:SetCausticWavesReminderEnabled(true)
            StartHeroic()
            local pullStart = Timer.GetTime()
            local hitAt = pullStart + HEROIC_WAVES[1]
            AdvanceTo(hitAt - WAVES_LEAD - 0.01)
            assert.is_nil(CalloutManager.GetDisplayed())
            Timer.Advance(0.01)
            assert.equals(L.ULATEK_CAUSTIC_WAVES_CALLOUT, CalloutManager.GetDisplayed())
            assert.equals("Ulatek", CalloutManager.GetCurrent().source)
            assert.equals(hitAt, CalloutManager.GetExpiresAt())
            assert.is_true(CalloutManager.GetAppendTimer())
            AdvanceTo(hitAt)
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("shows later Caustic Waves hits from pull start", function()
            Module:SetCausticWavesReminderEnabled(true)
            StartHeroic()
            local pullStart = Timer.GetTime()
            local hitAt = pullStart + HEROIC_WAVES[2]
            AdvanceTo(hitAt - WAVES_LEAD)
            assert.equals(L.ULATEK_CAUSTIC_WAVES_CALLOUT, CalloutManager.GetDisplayed())
            assert.equals(hitAt, CalloutManager.GetExpiresAt())
        end)

        it("does not alert Egg Deadline or Wretch AoE", function()
            EnableAll()
            StartHeroic()
            local pullStart = Timer.GetTime()
            AdvanceTo(pullStart + MYTHIC_EGG[1])
            assert.is_nil(ActiveByText()[L.ULATEK_EGG_DEADLINE_CALLOUT])
            AdvanceTo(pullStart + MYTHIC_WRETCH[1])
            assert.is_nil(ActiveByText()[L.ULATEK_WRETCH_AOE_CALLOUT])
        end)

        it("does not show a disabled Caustic Waves alert", function()
            EnableAll()
            Module:SetCausticWavesReminderEnabled(false)
            StartHeroic()
            Timer.Advance(HEROIC_WAVES[1])
            assert.is_nil(CalloutManager.GetDisplayed())
        end)
    end)

    describe("Mythic", function()
        local function StartMythic()
            StartEncounter(Instance.DIFFICULTY_MYTHIC_RAID)
        end

        it("shows Egg Deadline 8s before the first hit", function()
            Module:SetEggDeadlineReminderEnabled(true)
            StartMythic()
            local pullStart = Timer.GetTime()
            local hitAt = pullStart + MYTHIC_EGG[1]
            AdvanceTo(hitAt - EGG_LEAD - 0.01)
            assert.is_nil(CalloutManager.GetDisplayed())
            Timer.Advance(0.01)
            assert.equals(L.ULATEK_EGG_DEADLINE_CALLOUT, CalloutManager.GetDisplayed())
            assert.equals(hitAt, CalloutManager.GetExpiresAt())
            assert.is_true(CalloutManager.GetAppendTimer())
        end)

        it("shows Wretch AoE 8s before the first hit", function()
            Module:SetWretchAoeReminderEnabled(true)
            StartMythic()
            local pullStart = Timer.GetTime()
            local hitAt = pullStart + MYTHIC_WRETCH[1]
            AdvanceTo(hitAt - WRETCH_LEAD)
            assert.equals(L.ULATEK_WRETCH_AOE_CALLOUT, CalloutManager.GetDisplayed())
            assert.equals(hitAt, CalloutManager.GetExpiresAt())
        end)

        it("shows Caustic Waves 5s before the first hit", function()
            Module:SetCausticWavesReminderEnabled(true)
            StartMythic()
            local pullStart = Timer.GetTime()
            local hitAt = pullStart + MYTHIC_WAVES[1]
            AdvanceTo(hitAt - WAVES_LEAD)
            assert.equals(L.ULATEK_CAUSTIC_WAVES_CALLOUT, CalloutManager.GetDisplayed())
            assert.equals(hitAt, CalloutManager.GetExpiresAt())
        end)

        it("stacks Egg Deadline and Caustic Waves when they share a hit time", function()
            EnableAll()
            StartMythic()
            local pullStart = Timer.GetTime()
            local hitAt = pullStart + 113
            AdvanceTo(hitAt - WAVES_LEAD)
            local active = ActiveByText()
            assert.equals(hitAt, active[L.ULATEK_EGG_DEADLINE_CALLOUT].expiresAt)
            assert.equals(hitAt, active[L.ULATEK_CAUSTIC_WAVES_CALLOUT].expiresAt)
            assert.is_true(active[L.ULATEK_EGG_DEADLINE_CALLOUT].appendTimer)
            assert.is_true(active[L.ULATEK_CAUSTIC_WAVES_CALLOUT].appendTimer)
        end)

        it("hides the presented alert when that checkbox is turned off", function()
            Module:SetEggDeadlineReminderEnabled(true)
            StartMythic()
            AdvanceTo(Timer.GetTime() + MYTHIC_EGG[1] - EGG_LEAD)
            assert.equals(L.ULATEK_EGG_DEADLINE_CALLOUT, CalloutManager.GetDisplayed())
            Module:SetEggDeadlineReminderEnabled(false)
            assert.is_nil(CalloutManager.GetDisplayed())
        end)

        it("cancels pending alerts when the encounter ends", function()
            Module:SetCausticWavesReminderEnabled(true)
            StartMythic()
            EndEncounter(Instance.DIFFICULTY_MYTHIC_RAID)
            Timer.Advance(MYTHIC_WAVES[1])
            assert.is_nil(CalloutManager.GetDisplayed())
        end)
    end)
end)
