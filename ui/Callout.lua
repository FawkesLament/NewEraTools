local _, ns = ...
local L = ns.L

-- Shared HUD for CalloutManager. Position lives on CalloutAnchor; lifecycle lives on the manager.

local Callout = ns.Modules.New("Callout")
ns.Callout = Callout

Callout.LAYOUT_ID = "Callout:1"

---@type table<string, { text: any|fun(): any, duration: number|nil }>
local scopePreviews = {}

---Preview shown while this layout scope is active. Common scope uses the default preview.
---@param scopeId string
---@param text any|fun(): any
---@param duration number|nil
function Callout.SetScopePreview(scopeId, text, duration)
    assert(type(scopeId) == "string" and scopeId ~= "", "Callout.SetScopePreview requires scopeId")
    assert(text ~= nil, "Callout.SetScopePreview requires text")
    if duration ~= nil then
        assert(type(duration) == "number", "Callout.SetScopePreview duration must be a number")
    end
    scopePreviews[scopeId] = { text = text, duration = duration }
end

local function Current()
    return ns.CalloutManager.GetCurrent()
end

local function ActivePreview()
    local scopeId = ns.LayoutEditor.GetActiveScopeId()
    return scopeId and scopePreviews[scopeId] or nil
end

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
