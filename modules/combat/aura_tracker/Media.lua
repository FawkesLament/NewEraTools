local _, ns = ...
local Internals = ns.Modules.Internals("AuraTracker")
local Assets = ns.Assets

local DEFAULT_TEXTURE = Assets.STATUS_BAR_TEXTURE_DEFAULT
local LSM_STATUSBAR = "statusbar"

local Media = {
    DEFAULT_TEXTURE = DEFAULT_TEXTURE,
    DEFAULT_TIME_FONT = ns.SharedMedia.FONT_DEFAULT,
}
Internals.Media = Media

---Optional LibSharedMedia-3.0; nil when the library is not loaded.
---@return table|nil
local function GetLSM()
    if LibStub == nil then
        return nil
    end
    local ok, lsm = pcall(LibStub, "LibSharedMedia-3.0", true)
    if ok then
        return lsm
    end
    return nil
end

---@param path string
---@return string
local function NormalizePath(path)
    return path:lower():gsub("/", "\\")
end

---@param textureId any
---@return string|nil
local function BuiltInTexturePath(textureId)
    if type(textureId) ~= "string" then
        return nil
    end
    for _, entry in ipairs(Assets.STATUS_BAR_TEXTURES) do
        if entry.id == textureId then
            return entry.path
        end
    end
    return nil
end

---@param textureId any
---@return string|nil
local function LsmTexturePath(textureId)
    if type(textureId) ~= "string" then
        return nil
    end
    local lsm = GetLSM()
    if not lsm then
        return nil
    end
    -- noDefault: do not substitute LSM's built-in "Blizzard" handle for unknown keys.
    return lsm:Fetch(LSM_STATUSBAR, textureId, true)
end

---@param textureId any
---@return boolean
function Media.IsKnownTexture(textureId)
    return BuiltInTexturePath(textureId) ~= nil or LsmTexturePath(textureId) ~= nil
end

---@param textureId string
---@return string
function Media.ResolveTexturePath(textureId)
    return BuiltInTexturePath(textureId) or LsmTexturePath(textureId) or Assets.Textures.WHITE
end

---Built-in ids first, then LSM `statusbar` handles. Skips LSM entries that duplicate a built-in id or path.
---@return string[]
function Media.ListTextureIds()
    local ids = {}
    local seenIds = {}
    local seenPaths = {}
    for _, entry in ipairs(Assets.STATUS_BAR_TEXTURES) do
        ids[#ids + 1] = entry.id
        seenIds[entry.id] = true
        seenPaths[NormalizePath(entry.path)] = true
    end

    local lsm = GetLSM()
    if not lsm then
        return ids
    end
    local list = lsm:List(LSM_STATUSBAR)
    if type(list) ~= "table" then
        return ids
    end
    for _, name in ipairs(list) do
        if not seenIds[name] then
            local path = lsm:Fetch(LSM_STATUSBAR, name, true)
            if type(path) == "string" and path ~= "" and not seenPaths[NormalizePath(path)] then
                ids[#ids + 1] = name
                seenIds[name] = true
                seenPaths[NormalizePath(path)] = true
            end
        end
    end
    return ids
end
