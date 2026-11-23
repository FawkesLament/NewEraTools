---Layout-editable compact interrupt-chain HUD with an optional side-by-side backup card.
local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local Spacing = Assets.Spacing

local InterruptRotationTracker = {}
ns.InterruptRotationTracker = InterruptRotationTracker

---@class InterruptRotationTrackerBindOptions
---@field layoutId string
---@field label string
---@field name string
---@field backupName string
---@field isEnabled fun(): boolean
---@field getPosition fun(): LayoutPosition
---@field setPosition fun(position: LayoutPosition)
---@field getDefaultPosition fun(): LayoutPosition
---@field previewState InterruptChainHUDState|fun(): InterruptChainHUDState
---@field getState fun(): InterruptChainHUDState|nil
---@field getBackupState fun(): InterruptChainHUDState|nil
---@field global boolean|nil
---@field parent Frame|nil
---@field width number|nil
---@field onEditBegin fun()|nil
---@field onEditEnd fun()|nil
---@field theme InterruptChainHUDTheme|nil
---@field accentColor { r: number, g: number, b: number }|nil

---@class InterruptRotationTrackerBinding
---@field LAYOUT_ID string
---@field Create fun(): InterruptChainHUD
---@field Ensure fun(): InterruptChainHUD
---@field Update fun()
---@field EnsureBackup fun(): InterruptChainHUD

---@param theme string|nil
---@return { r: number, g: number, b: number }
function InterruptRotationTracker.ThemeColor(theme)
    return ns.InterruptChainHUD.ThemeColor(theme)
end

---@return string|nil
---@return string|nil
local function PreviewAssignee()
    local Player = ns.Api and ns.Api.Player
    if not Player then
        return nil, nil
    end
    local fullName = Player.GetFullName and Player.GetFullName()
    local name
    if type(fullName) == "string" and fullName ~= "" then
        name = fullName:match("^([^-]+)") or fullName
    end
    local classFile = Player.GetClassFile and Player.GetClassFile()
    if type(classFile) ~= "string" or classFile == "" then
        classFile = nil
    end
    return name, classFile
end

---Common-UI Edit Mode sample: six nodes, one done, one current, you as assignee.
---@return InterruptChainHUDState
function InterruptRotationTracker.PreviewState()
    local name, classFile = PreviewAssignee()
    return {
        total = 6,
        completed = 1,
        myIndices = { 4 },
        label = L.INTERRUPT_CHAIN_HUD_PREVIEW_LABEL,
        currentAssignee = name,
        currentAssigneeClass = classFile,
    }
end

---@return number
local function MainPanelScale()
    local mainPanel = ns.MainPanel
    if mainPanel and mainPanel.GetScale then
        return mainPanel.GetScale()
    end
    return 1
end

---@param frame Frame
local function ApplyScale(frame)
    local scale = MainPanelScale()
    if frame.GetScale then
        local oldScale = frame:GetScale() or 1
        if math.abs(oldScale - scale) < 0.001 then
            return
        end
    end
    frame:SetScale(scale)
end

---@param frame Frame
---@param getPosition (fun(): LayoutPosition|nil)|nil
local function ListenForScale(frame, getPosition)
    local mainPanel = ns.MainPanel
    if not mainPanel or not mainPanel.OnScaleChanged then
        return
    end
    mainPanel.OnScaleChanged(function(scale)
        frame:SetScale(scale)
        if getPosition then
            local position = getPosition()
            if position then
                ns.LayoutEditor.ApplyPosition(frame, position)
            end
        end
    end)
end

---Layout-editable primary chain HUD with an optional side-by-side backup card.
---Backup shares the primary's saved point when the primary is hidden.
---@param config InterruptRotationTrackerBindOptions
---@return InterruptRotationTrackerBinding
function InterruptRotationTracker.Bind(config)
    assert(type(config) == "table", "InterruptRotationTracker.Bind requires options")
    assert(type(config.layoutId) == "string", "InterruptRotationTracker.Bind requires layoutId")
    assert(type(config.label) == "string", "InterruptRotationTracker.Bind requires label")
    assert(type(config.name) == "string", "InterruptRotationTracker.Bind requires name")
    assert(type(config.isEnabled) == "function", "InterruptRotationTracker.Bind requires isEnabled")
    assert(type(config.getPosition) == "function", "InterruptRotationTracker.Bind requires getPosition")
    assert(type(config.setPosition) == "function", "InterruptRotationTracker.Bind requires setPosition")
    assert(type(config.getDefaultPosition) == "function", "InterruptRotationTracker.Bind requires getDefaultPosition")
    assert(config.previewState ~= nil, "InterruptRotationTracker.Bind requires previewState")
    assert(type(config.getBackupState) == "function", "InterruptRotationTracker.Bind requires getBackupState")
    assert(type(config.backupName) == "string", "InterruptRotationTracker.Bind requires backupName")

    local LayoutEditor = ns.LayoutEditor
    local window
    ---@type InterruptChainHUD|nil
    local backupWindow
    local registered = false
    local layoutEditing = false

    ---@class InterruptRotationTrackerBinding
    local binding = {
        LAYOUT_ID = config.layoutId,
    }

    local function PreviewState()
        local editor = ns.LayoutEditor
        if
            config.global
            and editor
            and editor.GetActiveScopeId
            and editor.GetActiveScopeId() == editor.COMMON_SCOPE_ID
        then
            return InterruptRotationTracker.PreviewState()
        end
        local state = config.previewState
        if type(state) == "function" then
            return state()
        end
        return state
    end

    local function Register(frame)
        if registered then
            return
        end
        registered = true
        LayoutEditor.Register({
            id = config.layoutId,
            label = config.label,
            frame = frame,
            global = config.global == true,
            isEnabled = config.isEnabled,
            getPosition = config.getPosition,
            setPosition = config.setPosition,
            getDefaultPosition = config.getDefaultPosition,
            onEditBegin = function()
                layoutEditing = true
                if backupWindow then
                    backupWindow:Hide()
                end
                if config.onEditBegin then
                    config.onEditBegin()
                end
                local hud = binding.Ensure()
                hud:SetState(PreviewState())
                hud:Show()
                hud:Raise()
            end,
            onEditEnd = function()
                layoutEditing = false
                if config.onEditEnd then
                    config.onEditEnd()
                end
                binding.Update()
            end,
        })
    end

    function binding.Create()
        local frame = ns.InterruptChainHUD.Create({
            name = config.name,
            parent = config.parent,
            width = config.width,
            theme = config.theme,
            accentColor = config.accentColor,
        })
        LayoutEditor.ApplyPosition(frame, config.getPosition())
        ListenForScale(frame, config.getPosition)
        Register(frame)
        return frame
    end

    function binding.Ensure()
        window = window or binding.Create()
        return window
    end

    local function EnsureBackup()
        if backupWindow then
            return backupWindow
        end
        backupWindow = ns.InterruptChainHUD.Create({
            name = config.backupName,
            parent = config.parent,
            width = config.width,
            theme = config.theme,
            accentColor = config.accentColor,
        })
        ListenForScale(backupWindow, function()
            if window and window:IsShown() then
                return nil
            end
            return config.getPosition()
        end)
        return backupWindow
    end

    ---@param primary InterruptChainHUD
    local function SyncBackup(primary)
        local state = config.getBackupState()
        if not state then
            if backupWindow then
                backupWindow:Hide()
            end
            return
        end
        local backup = EnsureBackup()
        ApplyScale(backup)
        backup:SetState(state)
        backup:Show()
        backup:ClearAllPoints()
        if primary:IsShown() then
            backup:SetPoint("LEFT", primary, "RIGHT", Spacing.SMALL, 0)
        else
            LayoutEditor.ApplyPosition(backup, config.getPosition())
        end
    end

    function binding.Update()
        if layoutEditing then
            return
        end
        window = window or binding.Create()
        ApplyScale(window)
        LayoutEditor.ApplyPosition(window, config.getPosition())
        local state = config.getState and config.getState() or nil
        if state == nil then
            if window:IsShown() then
                window:Hide()
            end
        else
            window:SetState(state)
            if not window:IsShown() then
                window:Show()
            end
        end
        SyncBackup(window)
    end

    function binding.EnsureBackup()
        return EnsureBackup()
    end

    return binding
end
