std = "lua51"
max_line_length = 120

globals = { "NewEraToolsDB" }

-- Frame and widget API: allowed in ui/ and modules/**/*UI.lua.
local WIDGET_API = {
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
    "C_ChatInfo",
    "C_ClassColor",
    "C_Timer",
    "Enum",
    "GetLocale",
    "GetNormalizedRealmName",
    "GetNumGroupMembers",
    "GetRaidRosterInfo",
    "IsInRaid",
    "LE_PARTY_CATEGORY_HOME",
    "LE_PARTY_CATEGORY_INSTANCE",
    "RAID_CLASS_COLORS",
    "SendChatMessage",
    "UnitClass",
    "UnitClassBase",
    "UnitGroupRolesAssigned",
    "UnitIsGroupAssistant",
    "UnitIsGroupLeader",
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
files["modules/**/*UI.lua"] = { read_globals = WIDGET_API }
files["tests"] = { std = "+busted" }
files["tests/ui"] = { std = "+busted", globals = { "CreateFrame" } }
files["tests/run.lua"] = { globals = { "assert", "describe", "it", "before_each", "after_each" } }
