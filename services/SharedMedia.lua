local _, ns = ...

local FONT_DEFAULT = "default"
-- Keep in sync with Assets.STATUS_BAR_TEXTURE_DEFAULT (`ui/` loads after this file).
local STATUS_BAR_TEXTURE_DEFAULT = "flat"
local LSM_FONT = "font"
local LSM_STATUSBAR = "statusbar"

local SharedMedia = {
    FONT_DEFAULT = FONT_DEFAULT,
    STATUS_BAR_TEXTURE_DEFAULT = STATUS_BAR_TEXTURE_DEFAULT,
}
ns.SharedMedia = SharedMedia

local fontListeners = {}
local statusBarListeners = {}
local mediaListening = false

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

---@param fontId any
---@return string|nil
local function LsmFontPath(fontId)
    if type(fontId) ~= "string" then
        return nil
    end
    local lsm = GetLSM()
    if not lsm then
        return nil
    end
    return lsm:Fetch(LSM_FONT, fontId, true)
end

---@param fontId any
---@return boolean
function SharedMedia.IsKnownFont(fontId)
    return fontId == FONT_DEFAULT or LsmFontPath(fontId) ~= nil
end

---File path for an LSM font handle, or nil for the built-in default id.
---@param fontId string
---@return string|nil
function SharedMedia.ResolveFontPath(fontId)
    if fontId == FONT_DEFAULT then
        return nil
    end
    return LsmFontPath(fontId)
end

---`default` first, then LSM `font` handles.
---@return string[]
function SharedMedia.ListFontIds()
    local ids = { FONT_DEFAULT }
    local seenIds = { [FONT_DEFAULT] = true }
    local lsm = GetLSM()
    if not lsm then
        return ids
    end
    local list = lsm:List(LSM_FONT)
    if type(list) ~= "table" then
        return ids
    end
    for _, name in ipairs(list) do
        if not seenIds[name] then
            local path = lsm:Fetch(LSM_FONT, name, true)
            if type(path) == "string" and path ~= "" then
                ids[#ids + 1] = name
                seenIds[name] = true
            end
        end
    end
    return ids
end

---@param path string
---@return string
local function NormalizePath(path)
    return path:lower():gsub("/", "\\")
end

---@param textureId any
---@return string|nil
local function BuiltInStatusBarPath(textureId)
    if type(textureId) ~= "string" then
        return nil
    end
    for _, entry in ipairs(ns.Assets.STATUS_BAR_TEXTURES) do
        if entry.id == textureId then
            return entry.path
        end
    end
    return nil
end

---@param textureId any
---@return string|nil
local function LsmStatusBarPath(textureId)
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
function SharedMedia.IsKnownStatusBarTexture(textureId)
    return BuiltInStatusBarPath(textureId) ~= nil or LsmStatusBarPath(textureId) ~= nil
end

---@param textureId string
---@return string
function SharedMedia.ResolveStatusBarTexturePath(textureId)
    return BuiltInStatusBarPath(textureId) or LsmStatusBarPath(textureId) or ns.Assets.Textures.WHITE
end

---Built-in ids first, then LSM `statusbar` handles. Skips LSM entries that duplicate a built-in id or path.
---@return string[]
function SharedMedia.ListStatusBarTextureIds()
    local ids = {}
    local seenIds = {}
    local seenPaths = {}
    for _, entry in ipairs(ns.Assets.STATUS_BAR_TEXTURES) do
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

local function NotifyFontListeners()
    for i = 1, #fontListeners do
        fontListeners[i]()
    end
end

local function NotifyStatusBarListeners()
    for i = 1, #statusBarListeners do
        statusBarListeners[i]()
    end
end

local function EnsureRegisteredCallback()
    if mediaListening then
        return
    end
    local lsm = GetLSM()
    if not lsm or not lsm.RegisterCallback then
        return
    end
    mediaListening = true
    lsm.RegisterCallback(SharedMedia, "LibSharedMedia_Registered", function(_, mediaType)
        if mediaType == LSM_FONT then
            NotifyFontListeners()
        elseif mediaType == LSM_STATUSBAR then
            NotifyStatusBarListeners()
        end
    end)
end

---Runs `handler` when LibSharedMedia registers a font. No-op until LSM is present.
---@param handler fun()
function SharedMedia.OnFontsRegistered(handler)
    assert(type(handler) == "function", "SharedMedia.OnFontsRegistered requires a function")
    fontListeners[#fontListeners + 1] = handler
    EnsureRegisteredCallback()
end

---Runs `handler` when LibSharedMedia registers a status bar. No-op until LSM is present.
---@param handler fun()
function SharedMedia.OnStatusBarsRegistered(handler)
    assert(type(handler) == "function", "SharedMedia.OnStatusBarsRegistered requires a function")
    statusBarListeners[#statusBarListeners + 1] = handler
    EnsureRegisteredCallback()
end
