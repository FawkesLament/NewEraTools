---Twin Fangs venom-stack roster: LazyEncounterUI wrapper around the shared DebuffMonitor HUD.
local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")
local L = ns.L
local Combat = ns.Api.Combat
local Instance = ns.Api.Instance

local TwinFangs = ns.Modules.Get("TwinFangs")
local Schema = Internals.Schema
local VenomRoster = Internals.VenomRoster

local LAYOUT_ID = "TwinFangs:venomRoster"
local SLOT_KEY = "venom"

local VenomRosterUI = {
    LAYOUT_ID = LAYOUT_ID,
}
Internals.VenomRosterUI = VenomRosterUI

---@type DebuffMonitor|nil
local instance
---@type LazyEncounterUI
local helper
local layoutRegistered = false
local layoutEditing = false
local slashPreviewing = false
local rosterListening = false
local zoneListening = false
local ApplyPreview, ShowRoot, ClearBoundRoster

---@return DebuffMonitorAppearance
local function Appearance()
    local barColor = TwinFangs:GetVenomRosterBarColor()
    return {
        rowHeight = TwinFangs:GetVenomRosterRowHeight(),
        rowGap = TwinFangs:GetVenomRosterRowGap(),
        columnGap = TwinFangs:GetVenomRosterColumnGap(),
        nameColumnWidth = TwinFangs:GetVenomRosterNameColumnWidth(),
        nameFontSize = TwinFangs:GetVenomRosterNameFontSize(),
        valueFontSize = TwinFangs:GetVenomRosterStackFontSize(),
        barTexture = TwinFangs:GetVenomRosterBarTexturePath(),
        barColor = { r = barColor.r, g = barColor.g, b = barColor.b },
        spark = true,
        backgroundOpacity = TwinFangs:GetVenomRosterBackgroundOpacity(),
        barOpacity = TwinFangs:GetVenomRosterBarOpacity(),
        maxStacks = 10,
    }
end

local function Register(frame)
    if layoutRegistered then
        return
    end
    layoutRegistered = true
    ns.LayoutEditor.Register({
        id = LAYOUT_ID,
        label = L.TWIN_FANGS_VENOM_ROSTER,
        frame = frame,
        global = false,
        isEnabled = function()
            return TwinFangs:IsVenomRosterEnabled()
        end,
        getPosition = function()
            return TwinFangs:GetVenomRosterPosition()
        end,
        setPosition = function(position)
            TwinFangs:SetVenomRosterPosition(position)
        end,
        getDefaultPosition = function()
            return Schema.DefaultVenomRosterPosition()
        end,
        onEditBegin = function()
            layoutEditing = true
            VenomRosterUI.Ensure()
            ApplyPreview(VenomRoster.DEFAULT_PREVIEW_SPEC)
            ShowRoot()
        end,
        onEditEnd = function()
            layoutEditing = false
            ClearBoundRoster()
            VenomRosterUI.Update()
        end,
    })
end

local function CreateInstance()
    instance = ns.DebuffMonitor.Create({
        name = ns.ADDON_NAME .. "TwinFangsVenomRoster",
        layoutMode = ns.DebuffMonitor.LAYOUT_ROSTER,
        displayMode = ns.DebuffMonitor.DISPLAY_STACKS,
        slotKey = SLOT_KEY,
        groupBy = "subgroup",
        maxGroups = VenomRoster.MAX_GROUPS,
        maxGroupSize = VenomRoster.MAX_GROUP_SIZE,
        omitEmptyGroups = true,
        showGroupHeaders = false,
        showTitle = false,
        spark = true,
        maxStacks = 10,
        getAppearance = Appearance,
        getPosition = function()
            return TwinFangs:GetVenomRosterPosition()
        end,
    })
    Register(instance.root)
    return instance
end

function ShowRoot()
    if not instance then
        return
    end
    instance.root:Show()
    instance.root:Raise()
end

local function HideRoot()
    if instance then
        instance.root:Hide()
    end
end

function ClearBoundRoster()
    if not instance then
        return
    end
    instance:Apply({}, { live = false })
end

function ApplyPreview(spec)
    local members = VenomRoster.BuildPreviewMembers(VenomRoster.CoercePreviewSpec(spec))
    local rosterInstance = VenomRosterUI.Ensure()
    rosterInstance:Apply(members, {
        live = false,
        values = VenomRoster.PreviewStacksByIndex(members),
    })
end

---@param enableAuras boolean|nil
local function ApplyLiveRoster(enableAuras)
    local rosterInstance = VenomRosterUI.Ensure()
    rosterInstance:Apply(VenomRoster.CollectLiveMembers(), {
        live = true,
        enableAuras = enableAuras ~= false,
    })
end

local function FlushPendingAuras()
    if layoutEditing or slashPreviewing then
        return
    end
    if helper:IsActive() then
        ApplyLiveRoster(true)
        return
    end
    if instance and TwinFangs:IsVenomRosterEnabled() and VenomRoster.IsInPitOfFangs() then
        ApplyLiveRoster(false)
        HideRoot()
    end
end

local function ListenForLiveRoster()
    if rosterListening then
        return
    end
    rosterListening = true
    ns.Api.Group.OnRosterChanged(function()
        if helper:IsActive() and not layoutEditing and not slashPreviewing then
            VenomRosterUI.Update()
        end
    end)
    Combat.OnLeave(FlushPendingAuras)
end

helper = ns.LazyEncounterUI.Create({
    create = CreateInstance,
    activate = function(rosterInstance)
        ListenForLiveRoster()
        if layoutEditing then
            return
        end
        ApplyLiveRoster(true)
        rosterInstance.root:Show()
        rosterInstance.root:Raise()
    end,
    deactivate = function(rosterInstance)
        rosterInstance:DisableAllAuras()
        rosterInstance.root:Hide()
    end,
})

function VenomRosterUI.Ensure()
    helper:Prepare()
    instance:ApplyScale()
    return instance
end

function VenomRosterUI.RefreshAppearance()
    if not instance then
        return
    end
    instance:Refresh()
end

local updating = false

function VenomRosterUI.Update()
    if updating then
        return
    end
    updating = true
    local ok, err = pcall(function()
        if layoutEditing then
            return
        end
        if not TwinFangs:IsVenomRosterEnabled() then
            HideRoot()
            return
        end
        if slashPreviewing then
            ShowRoot()
            return
        end
        if helper:IsActive() then
            ApplyLiveRoster(true)
            ShowRoot()
            return
        end
        HideRoot()
    end)
    updating = false
    if not ok then
        error(err)
    end
end

---@param members TwinFangsVenomRosterMember[]|nil
---@param stacks table<number, number>|nil
function VenomRosterUI.Apply(members, stacks)
    local rosterInstance = VenomRosterUI.Ensure()
    rosterInstance:Apply(members, { live = false, values = stacks })
end

---Creates AuraContainers in Pit of Fangs when the feature is on. No-op after the first success.
function VenomRosterUI.PrepareIfNeeded()
    if helper:IsPrepared() then
        return
    end
    if not TwinFangs:IsVenomRosterEnabled() then
        return
    end
    if not VenomRoster.IsInPitOfFangs() then
        return
    end
    helper:Prepare()
    if not helper:IsActive() then
        ApplyLiveRoster(false)
        HideRoot()
    end
end

---Enables or disables live AuraContainer binding. Encounter lifecycle and `/netvenom live` call this.
---@param active boolean
function VenomRosterUI.SetLiveActive(active)
    ListenForLiveRoster()
    if active then
        if not TwinFangs:IsVenomRosterEnabled() then
            return
        end
        slashPreviewing = false
        helper:SetActive(true)
    else
        slashPreviewing = false
        helper:SetActive(false)
    end
    VenomRosterUI.Update()
end

---@return boolean
function VenomRosterUI.IsLiveActive()
    return helper:IsActive()
end

---@return boolean
function VenomRosterUI.IsPrepared()
    return helper:IsPrepared()
end

---Development-only preview. Isolated from live combat; Edit Mode reuses the same mock builders.
---@param spec number|string|table|nil
function VenomRosterUI.ShowPreview(spec)
    slashPreviewing = true
    ApplyPreview(spec)
    helper:Prepare()
    ShowRoot()
end

function VenomRosterUI.HidePreview()
    slashPreviewing = false
    if not layoutEditing and not helper:IsActive() then
        ClearBoundRoster()
    end
    VenomRosterUI.Update()
end

function TwinFangs:OnVenomRosterEnabledChanged()
    if not TwinFangs:IsVenomRosterEnabled() then
        slashPreviewing = false
        if helper:IsActive() then
            VenomRosterUI.SetLiveActive(false)
        elseif instance and not layoutEditing then
            instance:DisableAllAuras()
            HideRoot()
        end
        if not layoutEditing then
            ClearBoundRoster()
        end
    else
        VenomRosterUI.PrepareIfNeeded()
        if TwinFangs:IsInEncounter() then
            VenomRosterUI.SetLiveActive(true)
        end
    end
    if ns.LayoutEditor.IsEditing() then
        ns.LayoutEditor.Refresh()
    end
    VenomRosterUI.Update()
end

function TwinFangs:PrepareVenomRoster()
    VenomRosterUI.PrepareIfNeeded()
end

function TwinFangs:SetVenomRosterEncounterActive(active)
    VenomRosterUI.SetLiveActive(active)
end

function TwinFangs:OnVenomRosterAppearanceChanged()
    VenomRosterUI.RefreshAppearance()
end

---@param spec number|string|table|nil
function TwinFangs:PreviewVenomRoster(spec)
    if spec == "hide" or spec == "off" or spec == false then
        VenomRosterUI.SetLiveActive(false)
        VenomRosterUI.HidePreview()
        return
    end
    if spec == "live" then
        VenomRosterUI.SetLiveActive(true)
        return
    end
    VenomRosterUI.ShowPreview(spec)
end

local function ListenForPitOfFangs()
    if zoneListening then
        return
    end
    zoneListening = true
    local function EvaluatePrewarm()
        VenomRosterUI.PrepareIfNeeded()
    end
    Instance.OnEnteringWorld(EvaluatePrewarm)
    Instance.OnZoneChangedIndoors(EvaluatePrewarm)
    Instance.OnZoneChangedNewArea(EvaluatePrewarm)
end

local previousEnable = TwinFangs.OnEnable
function TwinFangs:OnEnable()
    if previousEnable then
        previousEnable(self)
    end
    ListenForLiveRoster()
    ListenForPitOfFangs()
    VenomRosterUI.PrepareIfNeeded()
    VenomRosterUI.Update()
    ns.Api.Slash.Register("NEWERATOOLSTWINFANGSVENOM", { "/netvenom" }, function(input)
        input = type(input) == "string" and input:match("^%s*(.-)%s*$") or ""
        if input == "" or input == "hide" or input == "off" then
            VenomRosterUI.SetLiveActive(false)
            VenomRosterUI.HidePreview()
            return
        end
        if input == "live" then
            VenomRosterUI.SetLiveActive(true)
            return
        end
        if input == "live off" then
            VenomRosterUI.SetLiveActive(false)
            return
        end
        local size = tonumber(input)
        VenomRosterUI.ShowPreview(size or input)
    end)
end
