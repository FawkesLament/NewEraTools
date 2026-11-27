local _, ns = ...
local Internals = ns.Modules.Internals("AuraTracker")
local SharedMedia = ns.SharedMedia

local Media = {
    DEFAULT_TEXTURE = SharedMedia.STATUS_BAR_TEXTURE_DEFAULT,
    DEFAULT_TIME_FONT = SharedMedia.FONT_DEFAULT,
}
Internals.Media = Media

---@param textureId any
---@return boolean
function Media.IsKnownTexture(textureId)
    return SharedMedia.IsKnownStatusBarTexture(textureId)
end

---@param textureId string
---@return string
function Media.ResolveTexturePath(textureId)
    return SharedMedia.ResolveStatusBarTexturePath(textureId)
end

---Built-in ids first, then LSM `statusbar` handles. Skips LSM entries that duplicate a built-in id or path.
---@return string[]
function Media.ListTextureIds()
    return SharedMedia.ListStatusBarTextureIds()
end
