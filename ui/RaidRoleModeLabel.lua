local _, ns = ...
local L = ns.L
local Assets = ns.Assets
local Widgets = ns.Widgets

local Colors = Assets.Colors
local Fonts = Assets.Fonts

---Muted "Currently in Member/Commander mode" line used by encounter settings panels.
local RaidRoleModeLabel = {}
ns.RaidRoleModeLabel = RaidRoleModeLabel

RaidRoleModeLabel.HEIGHT = 16

---Wraps `text` in the accent color escape so it stands out inside a muted FontString.
---@param text string
---@return string
local function AccentText(text)
    local r, g, b = Widgets.UnpackColor(Colors.ACCENT)
    return string.format(
        "|cff%02x%02x%02x%s|r",
        math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5),
        text
    )
end

---@param isCommander boolean
---@return string
function RaidRoleModeLabel.Format(isCommander)
    local roleName = isCommander and L.RAID_ROLE_COMMANDER or L.RAID_ROLE_MEMBER
    return string.format(L.RAID_ROLE_MODE, AccentText(roleName))
end

---@param label FontString
function RaidRoleModeLabel.Update(label)
    label:SetText(RaidRoleModeLabel.Format(ns.RaidRole.IsCommander()))
end

---Creates a left-aligned mode label. Optional `tooltip` is shown on hover.
---@param parent Frame
---@param tooltip string|nil
---@return FontString
function RaidRoleModeLabel.Create(parent, tooltip)
    local label = Widgets.CreateLabel(parent, Fonts.SMALL_MUTED)
    label:SetJustifyH("LEFT")
    label:SetPoint("LEFT", parent, "LEFT")
    if tooltip then
        local hit = CreateFrame("Frame", nil, parent)
        hit:SetPoint("TOPLEFT", label, "TOPLEFT")
        hit:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT")
        hit:EnableMouse(true)
        Widgets.AttachTooltip(hit, "ANCHOR_TOP", function(tip)
            tip:SetText(tooltip)
        end)
    end
    RaidRoleModeLabel.Update(label)
    return label
end
