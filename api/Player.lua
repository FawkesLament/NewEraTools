local _, ns = ...
local Unit = ns.Api.Unit

local Player = {}
ns.Api.Player = Player

---@alias PlayerRole "TANK"|"HEALER"|"DAMAGER"

---@class PlayerSpecialization
---@field id integer  Stable specialization ID (not a slot index).
---@field name string
---@field role PlayerRole

---@class PlayerActivationContext
---@field classFile string|nil  e.g. "WARRIOR".
---@field specializationId integer|nil
---@field role PlayerRole|nil

local SpecInfo = C_SpecializationInfo
local GetSpecialization = (SpecInfo and SpecInfo.GetSpecialization) or GetSpecialization
local GetSpecializationInfo = (SpecInfo and SpecInfo.GetSpecializationInfo) or GetSpecializationInfo
local GetNumSpecializations = (SpecInfo and SpecInfo.GetNumSpecializations) or GetNumSpecializations
local GetSpecializationInfoByID = (SpecInfo and SpecInfo.GetSpecializationInfoByID) or GetSpecializationInfoByID

local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }

local CHANGE_EVENTS = {
    "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_TALENT_GROUP_CHANGED",
}

---@param role any
---@return PlayerRole|nil
local function NormalizeRole(role)
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
        return role
    end
    return nil
end

---@param id any
---@return integer|nil
local function NormalizeSpecializationId(id)
    if type(id) ~= "number" then
        return nil
    end
    local specId = math.floor(id)
    if specId < 1 or specId ~= id then
        return nil
    end
    return specId
end

---Player "Name-Realm", suitable for comparing with addon-message senders.
---@return string|nil
function Player.GetFullName()
    local name = UnitName("player")
    if not name or name == "" then
        return nil
    end
    return Unit.GetFullName(name)
end

---Player GUID when available; nil when the client has not resolved it.
---@return string|nil
function Player.GetGUID()
    return Unit.GetGUID("player")
end

---Player class file name, e.g. "DRUID".
---@return string|nil
function Player.GetClassFile()
    return Unit.GetClassFile("player")
end

---Localized class name for a class file, e.g. "Druid".
---@param classFile string|nil
---@return string|nil
function Player.GetClassName(classFile)
    if type(classFile) ~= "string" or classFile == "" then
        return nil
    end
    if LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile] then
        return LOCALIZED_CLASS_NAMES_MALE[classFile]
    end
    local localized, file = UnitClass("player")
    if file == classFile and type(localized) == "string" and localized ~= "" then
        return localized
    end
    return nil
end

---Localized specialization name for a stable specialization ID.
---@param specializationId integer|nil
---@return string|nil
function Player.GetSpecializationName(specializationId)
    local specId = NormalizeSpecializationId(specializationId)
    if not specId then
        return nil
    end
    for _, spec in ipairs(Player.ListSpecializations()) do
        if spec.id == specId then
            return spec.name
        end
    end
    if not GetSpecializationInfoByID then
        return nil
    end
    local _, name = GetSpecializationInfoByID(specId)
    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

---Texture file ID or path for a specialization, or nil when the client has none.
---@param specializationId integer|nil
---@return number|string|nil
function Player.GetSpecializationIcon(specializationId)
    local specId = NormalizeSpecializationId(specializationId)
    if not specId or not GetSpecializationInfoByID then
        return nil
    end
    local _, _, _, icon = GetSpecializationInfoByID(specId)
    if type(icon) == "number" or (type(icon) == "string" and icon ~= "") then
        return icon
    end
    return nil
end

---Stable ID of the player's current specialization, or nil when unavailable.
---@return integer|nil
function Player.GetSpecializationId()
    if not GetSpecialization or not GetSpecializationInfo then
        return nil
    end
    local index = GetSpecialization()
    if type(index) ~= "number" or index < 1 then
        return nil
    end
    local id = GetSpecializationInfo(index)
    return NormalizeSpecializationId(id)
end

---Combat role of the player's current specialization (not the LFG group role).
---@return PlayerRole|nil
function Player.GetRole()
    if not GetSpecialization or not GetSpecializationInfo then
        return nil
    end
    local index = GetSpecialization()
    if type(index) ~= "number" or index < 1 then
        return nil
    end
    local _, _, _, _, role = GetSpecializationInfo(index)
    return NormalizeRole(role)
end

---Specializations available to the player's current class.
---@return PlayerSpecialization[]
function Player.ListSpecializations()
    local list = {}
    if not GetNumSpecializations or not GetSpecializationInfo then
        return list
    end
    local count = GetNumSpecializations()
    if type(count) ~= "number" or count < 1 then
        return list
    end
    for index = 1, count do
        local id, name, _, _, role = GetSpecializationInfo(index)
        local specId = NormalizeSpecializationId(id)
        local normalizedRole = NormalizeRole(role)
        if specId and type(name) == "string" and name ~= "" and normalizedRole then
            list[#list + 1] = {
                id = specId,
                name = name,
                role = normalizedRole,
            }
        end
    end
    return list
end

---Distinct combat roles the player's class can fill, in tank → healer → damager order.
---@return PlayerRole[]
function Player.ListRoles()
    local seen = {}
    local roles = {}
    for _, spec in ipairs(Player.ListSpecializations()) do
        if not seen[spec.role] then
            seen[spec.role] = true
            roles[#roles + 1] = spec.role
        end
    end
    table.sort(roles, function(a, b)
        return (ROLE_ORDER[a] or 99) < (ROLE_ORDER[b] or 99)
    end)
    return roles
end

---Snapshot used for activation-scope matching.
---@return PlayerActivationContext
function Player.GetActivationContext()
    return {
        classFile = Player.GetClassFile(),
        specializationId = Player.GetSpecializationId(),
        role = Player.GetRole(),
    }
end

---Calls `callback` when the player's specialization (and thus role) may have changed.
---@param callback fun()
function Player.OnChanged(callback)
    for _, event in ipairs(CHANGE_EVENTS) do
        ns.Api.GameEvents.Listen(event, function(unitOrCurr)
            if event == "PLAYER_SPECIALIZATION_CHANGED" and unitOrCurr ~= nil and unitOrCurr ~= "player" then
                return
            end
            callback()
        end)
    end
end
