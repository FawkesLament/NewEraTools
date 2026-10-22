-- Fixed raid roster for Twin Fangs interrupt-chain editor specs.

local Loader = require("helpers.loader")

local Helper = {}

---Loads presentation labels skipped by the addon test loader.
---@param ns table
---@return table
function Helper.LoadLabels(ns)
    assert(loadfile("modules/venomous_abyss/twin_fangs/ui/interrupt_chain/Labels.lua"))(Loader.ADDON_NAME, ns)
    return ns.Modules.Internals("TwinFangs").InterruptChainLabels
end

Helper.REALM = "MockRealm"

---@param name string
---@param subgroup number
---@param classFile string
---@param role string
---@param index number
---@return table
local function MockMember(name, subgroup, classFile, role, index)
    return {
        name = name,
        fullName = name .. "-" .. Helper.REALM,
        guid = "Player-MOCK-" .. name,
        index = index,
        subgroup = subgroup,
        classFile = classFile,
        role = role,
    }
end

---@return table[]
function Helper.MockRoster()
    return {
        MockMember("清风", 1, "MAGE", "DAMAGER", 1),
        MockMember("夜雨", 1, "ROGUE", "DAMAGER", 2),
        MockMember("石川", 1, "WARRIOR", "DAMAGER", 3),
        MockMember("流火", 2, "SHAMAN", "DAMAGER", 4),
        MockMember("霜华", 2, "HUNTER", "DAMAGER", 5),
        MockMember("远山", 2, "DEMONHUNTER", "DAMAGER", 6),
        MockMember("南枝", 3, "PRIEST", "DAMAGER", 7),
        MockMember("白露", 3, "MONK", "DAMAGER", 8),
        MockMember("青禾", 3, "WARLOCK", "DAMAGER", 9),
        MockMember("朔风", 4, "PALADIN", "DAMAGER", 10),
        MockMember("凌川", 4, "DEATHKNIGHT", "DAMAGER", 11),
        MockMember("暮雪", 4, "EVOKER", "DAMAGER", 12),
        MockMember("余烬", 5, "DRUID", "DAMAGER", 13),
        MockMember("栖梧", 5, "MAGE", "DAMAGER", 14),
    }
end

return Helper
