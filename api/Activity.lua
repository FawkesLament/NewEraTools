local _, ns = ...

local Activity = {}
ns.Api.Activity = Activity

local PlayerInfo = C_PlayerInfo
local PetBattles = C_PetBattles

-- Unit events are filtered to "player" in OnContextChanged.
local CONTEXT_EVENTS = {
    "PLAYER_IS_GLIDING_CHANGED",
    "PLAYER_MOUNT_DISPLAY_CHANGED",
    "UNIT_EXITED_VEHICLE",
    "UNIT_POWER_BAR_HIDE",
    "PET_BATTLE_OPENING_START",
    "PET_BATTLE_CLOSE",
    "CINEMATIC_START",
    "CINEMATIC_STOP",
}

local UNIT_CONTEXT_EVENTS = {
    UNIT_EXITED_VEHICLE = true,
    UNIT_POWER_BAR_HIDE = true,
}

---Whether the player is actively Skyriding / Dynamic Flight gliding.
---Uses only `isGliding` from `C_PlayerInfo.GetGlidingInfo` (not `canGlide`): `canGlide`
---stays true while still on a Skyriding mount after landing, which would never restore bars.
---@return boolean
function Activity.IsSkyriding()
    if not PlayerInfo or not PlayerInfo.GetGlidingInfo then
        return false
    end
    local isGliding = PlayerInfo.GetGlidingInfo()
    return isGliding == true
end

---Whether a pet battle is in progress (`C_PetBattles.IsInBattle`).
---True from PET_BATTLE_OPENING_START until after PET_BATTLE_OVER (PET_BATTLE_CLOSE may fire twice).
---@return boolean
function Activity.IsInPetBattle()
    return PetBattles ~= nil and PetBattles.IsInBattle ~= nil and PetBattles.IsInBattle() == true
end

---Whether a supported in-game cinematic or cutscene is playing.
---Covers simple camera cinematics (`InCinematic`) and NPC/scenescript cutscenes
---(`IsInCinematicScene`). Pre-rendered MovieFrame movies (`PLAY_MOVIE`) are not
---reported by these APIs and are intentionally not detected.
---@return boolean
function Activity.IsInCinematic()
    if InCinematic and InCinematic() == true then
        return true
    end
    if IsInCinematicScene and IsInCinematicScene() == true then
        return true
    end
    return false
end

---Calls `callback` when skyriding, pet-battle, or cinematic context may have changed.
---@param callback fun()
function Activity.OnContextChanged(callback)
    for _, event in ipairs(CONTEXT_EVENTS) do
        ns.Api.GameEvents.Listen(event, function(unitOrArg)
            if UNIT_CONTEXT_EVENTS[event] and unitOrArg ~= nil and unitOrArg ~= "player" then
                return
            end
            callback()
        end)
    end
end
