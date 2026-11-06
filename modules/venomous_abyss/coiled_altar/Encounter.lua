local _, ns = ...
local Internals = ns.Modules.Internals("CoiledAltar")
local Encounter = ns.Api.Encounter

local CoiledAltar = ns.Modules.Get("CoiledAltar")

-- The Coiled Altar in The Venomous Abyss.
local ENCOUNTER_ID = 3429

CoiledAltar.ENCOUNTER_ID = ENCOUNTER_ID

---Refreshes interrupt presentation: Callout, nameplate indicators, then encounter HUD consumers.
function Internals.NotifyEncounterState()
    Internals.SyncInterruptCallout()
    Internals.SyncNameplateIndicators()
    if CoiledAltar.OnInterruptStateChanged then
        CoiledAltar:OnInterruptStateChanged()
    end
end

---Starts watching this boss fight. Called from OnEnable.
function CoiledAltar:ListenForEncounter()
    Encounter.WhileIn(ENCOUNTER_ID, function(difficultyID, scope)
        -- Runs last on dispose so combat subscriptions are gone and InterruptStates.Get() is nil.
        scope:Add(function()
            Internals.NotifyEncounterState()
        end)
        Internals.PhaseDetector.Start(scope)
        Internals.StartGhostChase(scope, difficultyID)
        if CoiledAltar:HasInterruptAssignments() then
            Internals.InterruptStates.Start(scope, Internals.NotifyEncounterState)
        end
    end)
end
