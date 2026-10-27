std = "lua51"
max_line_length = 120

globals = { "NewEraToolsDB", "NewEraToolsAPI" }

-- Frame and widget API: allowed in ui/, modules/**/ui/, and modules/**/*UI.lua.
local WIDGET_API = {
    "ColorPickerFrame",
    "CreateFont",
    "CreateFrame",
    "GameTooltip",
    "GetCursorPosition",
    "Minimap",
    "ScrollUtil",
    "STANDARD_TEXT_FONT",
    "UIParent",
    "UISpecialFrames",
}

-- Game state and actions: allowed only in api/.
local GAME_API = {
    "AuraContainerSortDirection",
    "AuraContainerSortMethod",
    "C_AddOns",
    "C_ChallengeMode",
    "C_ChatInfo",
    "C_ClassColor",
    "C_EncounterTimeline",
    "C_InstanceEncounter",
    "C_NamePlate",
    "C_PartyInfo",
    "C_PetBattles",
    "C_PlayerInfo",
    "C_SpecializationInfo",
    "C_Spell",
    "C_TTSSettings",
    "C_VoiceChat",
    "C_SpellBook",
    "C_Secrets",
    "C_StringUtil",
    "C_Timer",
    "InCinematic",
    "IsInCinematicScene",
    "GetNumSpecializations",
    "GetSpecialization",
    "GetSpecializationInfo",
    "GetSpecializationInfoByID",
    "GetSpellInfo",
    "LOCALIZED_CLASS_NAMES_MALE",
    "EJ_GetCurrentTier",
    "EJ_GetInstanceByIndex",
    "EJ_GetNumTiers",
    "EJ_SelectTier",
    "Enum",
    "GetInstanceInfo",
    "GetSubZoneText",
    "GetLocale",
    "GetNormalizedRealmName",
    "GetNumGroupMembers",
    "GetRaidRosterInfo",
    "GetTime",
    "InCombatLockdown",
    "IsInRaid",
    "LE_PARTY_CATEGORY_HOME",
    "LE_PARTY_CATEGORY_INSTANCE",
    "LoggingCombat",
    "RAID_CLASS_COLORS",
    "CreateMacro",
    "EditMacro",
    "GetFileIDFromPath",
    "GetMacroIndexByName",
    "GetMacroInfo",
    "GetNumMacros",
    "UPDATE_MACROS",
    "MAX_ACCOUNT_MACROS",
    "MAX_CHARACTER_MACROS",
    "GetRaidTargetIndex",
    "SendChatMessage",
    "UnitAffectingCombat",
    "UnitCanAssist",
    "UnitCanAttack",
    "UnitClass",
    "UnitClassBase",
    "UnitExists",
    "UnitGroupRolesAssigned",
    "UnitGUID",
    "UnitIsBossMob",
    "UnitIsGroupAssistant",
    "UnitIsGroupLeader",
    "UnitName",
    "WorldFrame",
    "issecret",
    "issecretvalue",
    "issecure",
}

local function Concat(...)
    local result = {}
    for _, list in ipairs({ ... }) do
        for _, name in ipairs(list) do
            table.insert(result, name)
        end
    end
    return result
end

files["api"] = { read_globals = Concat(GAME_API, WIDGET_API), globals = { "_G", "SlashCmdList" } }
files["ui"] = { read_globals = WIDGET_API }
files["modules/**/*UI.lua"] = { read_globals = Concat(WIDGET_API, { "LibStub" }) }
files["modules/**/ui/**/*.lua"] = { read_globals = Concat(WIDGET_API, { "LibStub" }) }
files["services/SharedMedia.lua"] = { read_globals = { "LibStub" } }
files["modules/combat/aura_tracker/Media.lua"] = { read_globals = { "LibStub" } }
files["modules/combat/aura_tracker/Profile.lua"] = { read_globals = { "debugprofilestop" } }
files["tests"] = { std = "+busted" }
files["tests/ui"] = { std = "+busted", globals = { "CreateFrame" } }
files["tests/run.lua"] = { globals = { "assert", "describe", "it", "before_each", "after_each" } }
