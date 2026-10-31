local _, ns = ...
local L = ns.L

-- Shared HUD for CalloutManager. Position lives on CalloutAnchor; lifecycle lives on the manager.

local Callout = ns.Modules.New("Callout")
ns.Callout = Callout

Callout.LAYOUT_ID = "Callout:1"

---@class CalloutScopePreview
---@field text any|fun(): any
---@field duration number|nil
---@field tick (fun(): (any, number)|nil)|nil
---@field onEnd fun()|nil

---@type table<string, CalloutScopePreview>
local scopePreviews = {}

---@class CalloutScopePreviewOptions
---@field tick (fun(): (any, number)|nil)|nil  Samples (text, remaining) each frame while this scope is edited.
---@field onEnd fun()|nil  Runs when this scope's callout preview stops.

---Preview shown while this layout scope is active. Common scope uses the default preview.
---@param scopeId string
---@param text any|fun(): any
---@param duration number|nil
---@param options CalloutScopePreviewOptions|nil
function Callout.SetScopePreview(scopeId, text, duration, options)
    assert(type(scopeId) == "string" and scopeId ~= "", "Callout.SetScopePreview requires scopeId")
    assert(text ~= nil, "Callout.SetScopePreview requires text")
    if duration ~= nil then
        assert(type(duration) == "number", "Callout.SetScopePreview duration must be a number")
    end
    options = options or {}
    if options.tick ~= nil then
        assert(type(options.tick) == "function", "Callout.SetScopePreview tick must be a function")
    end
    if options.onEnd ~= nil then
        assert(type(options.onEnd) == "function", "Callout.SetScopePreview onEnd must be a function")
    end
    scopePreviews[scopeId] = {
        text = text,
        duration = duration,
        tick = options.tick,
        onEnd = options.onEnd,
    }
end

local function Current()
    return ns.CalloutManager.GetCurrent()
end

local function ActivePreview()
    local scopeId = ns.LayoutEditor.GetActiveScopeId()
    return scopeId and scopePreviews[scopeId] or nil
end

---@type CalloutScopePreview|nil
local sessionPreview

local binding = ns.CalloutMessage.Bind({
    layoutId = Callout.LAYOUT_ID,
    name = ns.ADDON_NAME .. "Callout",
    label = L.CALLOUT_TITLE,
    global = true,
    isEnabled = function()
        return true
    end,
    getText = function()
        local current = Current()
        if not current then
            return nil
        end
        if current.wrap then
            return current.wrap:format(current.text)
        end
        return current.text
    end,
    getExpiresAt = function()
        local current = Current()
        return current and current.expiresAt
    end,
    getAppendTimer = function()
        local current = Current()
        return current and current.appendTimer
    end,
    getPosition = function()
        return ns.CalloutAnchor.GetPosition()
    end,
    setPosition = function(position)
        ns.CalloutAnchor.SetPosition(position)
    end,
    getDefaultPosition = function()
        return ns.CalloutAnchor.DefaultPosition()
    end,
    previewText = function()
        local preview = ActivePreview()
        local text = preview and preview.text or L.CALLOUT_PREVIEW
        if type(text) == "function" then
            return text()
        end
        return text
    end,
    previewDuration = function()
        local preview = ActivePreview()
        return preview and preview.duration
    end,
    hasPreviewTick = function()
        local preview = ActivePreview()
        return preview ~= nil and preview.tick ~= nil
    end,
    previewTick = function()
        local preview = ActivePreview()
        if not preview or not preview.tick then
            return nil
        end
        return preview.tick()
    end,
    onEditBegin = function()
        sessionPreview = ActivePreview()
    end,
    onEditEnd = function()
        local preview = sessionPreview
        sessionPreview = nil
        if preview and preview.onEnd then
            preview.onEnd()
        end
    end,
})

function Callout.Ensure()
    return binding.Ensure()
end

function Callout:OnEnable()
    ns.CalloutManager.OnChanged(function()
        binding.Update()
    end)
    binding.Ensure()
    binding.Update()
end
