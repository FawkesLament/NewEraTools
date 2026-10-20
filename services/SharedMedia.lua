local _, ns = ...

local FONT_DEFAULT = "default"
local LSM_FONT = "font"

local SharedMedia = {
    FONT_DEFAULT = FONT_DEFAULT,
}
ns.SharedMedia = SharedMedia

local fontListeners = {}
local fontsListening = false

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

local function NotifyFontListeners()
    for i = 1, #fontListeners do
        fontListeners[i]()
    end
end

local function EnsureFontCallback()
    if fontsListening then
        return
    end
    local lsm = GetLSM()
    if not lsm or not lsm.RegisterCallback then
        return
    end
    fontsListening = true
    lsm.RegisterCallback(SharedMedia, "LibSharedMedia_Registered", function(_, mediaType)
        if mediaType == LSM_FONT then
            NotifyFontListeners()
        end
    end)
end

---Runs `handler` when LibSharedMedia registers a font. No-op until LSM is present.
---@param handler fun()
function SharedMedia.OnFontsRegistered(handler)
    assert(type(handler) == "function", "SharedMedia.OnFontsRegistered requires a function")
    fontListeners[#fontListeners + 1] = handler
    EnsureFontCallback()
end
