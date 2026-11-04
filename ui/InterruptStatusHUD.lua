local _, ns = ...
local Spacing = ns.Assets.Spacing

local InterruptStatusHUD = {}
ns.InterruptStatusHUD = InterruptStatusHUD

---@class InterruptStatusHUDBindOptions: StatusHUDBindOptions
---@field getBackupState fun(): StatusHUDState|nil
---@field backupName string
---@field backupTone string|nil

---@class InterruptStatusHUDBinding: StatusHUDBinding
---@field EnsureBackup fun(): StatusHUD

---Layout-editable primary StatusHUD with an optional stacked backup card.
---Backup shares the primary's saved point when the primary is hidden.
---@param config InterruptStatusHUDBindOptions
---@return InterruptStatusHUDBinding
function InterruptStatusHUD.Bind(config)
    assert(type(config) == "table", "InterruptStatusHUD.Bind requires options")
    assert(type(config.getBackupState) == "function", "InterruptStatusHUD.Bind requires getBackupState")
    assert(type(config.backupName) == "string", "InterruptStatusHUD.Bind requires backupName")

    local previewing = false
    ---@type StatusHUD|nil
    local backupWindow

    local function EnsureBackup()
        if backupWindow then
            return backupWindow
        end
        backupWindow = ns.StatusHUD.Create({
            name = config.backupName,
            parent = config.parent,
            width = config.width,
            tone = config.backupTone or ns.StatusHUD.TONE_STANDBY,
        })
        return backupWindow
    end

    ---@param primary StatusHUD
    local function SyncBackup(primary)
        local state = config.getBackupState()
        if not state then
            if backupWindow then
                backupWindow:Hide()
            end
            return
        end
        local backup = EnsureBackup()
        backup:SetState(state)
        backup:Show()
        backup:ClearAllPoints()
        if primary:IsShown() then
            backup:SetPoint("TOP", primary, "BOTTOM", 0, -Spacing.SMALL)
        else
            ns.LayoutEditor.ApplyPosition(backup, config.getPosition())
        end
    end

    local binding = ns.StatusHUD.Bind({
        layoutId = config.layoutId,
        label = config.label,
        name = config.name,
        isEnabled = config.isEnabled,
        getPosition = config.getPosition,
        setPosition = config.setPosition,
        getDefaultPosition = config.getDefaultPosition,
        previewState = config.previewState,
        getState = config.getState,
        global = config.global,
        parent = config.parent,
        width = config.width,
        tone = config.tone,
        onEditBegin = function()
            previewing = true
            if backupWindow then
                backupWindow:Hide()
            end
            if config.onEditBegin then
                config.onEditBegin()
            end
        end,
        onEditEnd = function()
            previewing = false
            if config.onEditEnd then
                config.onEditEnd()
            end
        end,
    })

    local boundUpdate = binding.Update
    function binding.Update()
        boundUpdate()
        if previewing then
            if backupWindow then
                backupWindow:Hide()
            end
            return
        end
        SyncBackup(binding.Ensure())
    end

    function binding.EnsureBackup()
        return EnsureBackup()
    end

    return binding --[[@as InterruptStatusHUDBinding]]
end
