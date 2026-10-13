local _, ns = ...

local Assets = {}
ns.Assets = Assets

local MEDIA_PATH = "Interface\\AddOns\\" .. ns.ADDON_NAME .. "\\media\\"

Assets.LOGO = MEDIA_PATH .. "icons\\logo"
Assets.MINI_LOGO = MEDIA_PATH .. "icons\\mini_logo"

Assets.Textures = {
    -- A plain white square; tinted with SetVertexColor or used as a backdrop for flat fills.
    WHITE = "Interface\\Buttons\\WHITE8x8",
    -- Built-in status-bar fills (also listed in STATUS_BAR_TEXTURES for pickers).
    STATUS_BAR = "Interface\\TargetingFrame\\UI-StatusBar",
    RAID_BAR = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    -- Mask texture that clips a texture to a circle.
    CIRCLE_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
    MINIMAP_HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
    MINIMAP_BACKGROUND = "Interface\\Minimap\\UI-Minimap-Background",
    MINIMAP_BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder",
}

---@class StatusBarTextureDef
---@field id string  Stable SavedVariables key; keep stable when renaming display labels.
---@field path string

---Built-in progress-bar fills. Append entries here to extend pickers; LSM statusbars are merged at runtime.
Assets.STATUS_BAR_TEXTURES = {
    { id = "flat", path = Assets.Textures.WHITE },
    { id = "default", path = Assets.Textures.STATUS_BAR },
    { id = "raid", path = Assets.Textures.RAID_BAR },
}

---SavedVariables default; matches the flat WHITE8x8 bar shipped with Aura Tracker.
Assets.STATUS_BAR_TEXTURE_DEFAULT = "flat"

Assets.Templates = {
    BACKDROP = "BackdropTemplate",
    SCROLL_BAR = "MinimalScrollBar",
    -- SecureHandlerBaseTemplate allows WrapScript for one-shot clicks during combat lockdown.
    SECURE_ACTION_BUTTON = "SecureActionButtonTemplate,SecureHandlerBaseTemplate",
}

Assets.Glyphs = {
    CLOSE = "×",
    -- ASCII, since not every locale font has the Unicode minus sign.
    DECREASE = "-",
    INCREASE = "+",
    -- Panel title-bar collapse / expand (same ASCII glyphs as the steppers).
    COLLAPSE = "―",
    EXPAND = "＋",
}

Assets.Colors = {
    BG = { r = 0.071, g = 0.075, b = 0.090, a = 0.95 },
    -- For windows left open over the game world, which should stay visible through them.
    BG_TRANSLUCENT = { r = 0.071, g = 0.075, b = 0.090, a = 0.6 },
    -- Slightly more see-through than BG_TRANSLUCENT; for warning overlays.
    BG_WARNING = { r = 0.071, g = 0.075, b = 0.090, a = 0.8 },
    SURFACE = { r = 0.102, g = 0.110, b = 0.133, a = 1 },
    SURFACE_RAISED = { r = 0.137, g = 0.149, b = 0.180, a = 1 },
    BORDER = { r = 0.180, g = 0.196, b = 0.231, a = 1 },
    -- Softer edge for compact floating overlays.
    BORDER_SUBTLE = { r = 0.55, g = 0.58, b = 0.65, a = 0.55 },
    -- Amber edge for warning overlays.
    BORDER_WARNING = { r = 0.90, g = 0.70, b = 0.25, a = 0.75 },
    HOVER = { r = 1, g = 1, b = 1, a = 0.06 },
    TEXT = { r = 0.902, g = 0.910, b = 0.922 },
    TEXT_MUTED = { r = 0.545, g = 0.565, b = 0.604 },
    -- Light gold for prominent readouts (e.g. combat timers).
    TEXT_GOLD = { r = 0.93, g = 0.82, b = 0.48 },
    TEXT_ON_ACCENT = { r = 0.071, g = 0.075, b = 0.090 },
    ACCENT = { r = 0.310, g = 0.765, b = 0.710, a = 1 },
    SUCCESS = { r = 0.35, g = 0.80, b = 0.40 },
    WARNING = { r = 0.945, g = 0.643, b = 0.267, a = 1 },
    ERROR = { r = 0.898, g = 0.282, b = 0.302 },
    DIVIDER = { r = 0.180, g = 0.196, b = 0.231, a = 1 },
    -- Subtle outline / label for layout edit mode previews.
    LAYOUT_EDIT_OUTLINE = { r = 0.310, g = 0.765, b = 0.710, a = 0.55 },
    LAYOUT_EDIT_LABEL = { r = 0.310, g = 0.765, b = 0.710, a = 0.9 },
    -- Full-screen veil behind editable elements (one static texture; no per-frame work).
    LAYOUT_EDIT_DIMMER = { r = 0, g = 0, b = 0, a = 0.55 },
}

-- Shared game textures used by floating overlays.
Assets.Icons = {
    WARNING = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
    -- Standard placeholder when a spell ID has no resolvable icon.
    QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark",
    -- Minimap player arrow (points up); rotate with SetRotation for path tips.
    PATH_ARROW = "Interface\\Minimap\\MinimapArrow",
}

local FONT_PREFIX = ns.ADDON_NAME .. "Font"

-- Names of font objects created by ns.Widgets on first use.
Assets.Fonts = {
    TITLE = FONT_PREFIX .. "Title",
    HEADER = FONT_PREFIX .. "Header",
    NAV_GROUP = FONT_PREFIX .. "NavGroup",
    BODY = FONT_PREFIX .. "Body",
    -- Slightly larger with an outline; for short emphasized spans (e.g. marker names).
    EMPHASIS = FONT_PREFIX .. "Emphasis",
    -- Large outlined readout for floating overlays (e.g. timers).
    DISPLAY = FONT_PREFIX .. "Display",
    -- Very large outlined callout text over the game world (e.g. Sszorak raid markers).
    CALLOUT = FONT_PREFIX .. "Callout",
    MUTED = FONT_PREFIX .. "Muted",
    SMALL_MUTED = FONT_PREFIX .. "SmallMuted",
    -- One step below SMALL_MUTED; for quiet footnotes on overlays.
    TINY_MUTED = FONT_PREFIX .. "TinyMuted",
    ON_ACCENT = FONT_PREFIX .. "OnAccent",
    -- Larger on-accent face for the layout-edit Done control.
    LAYOUT_EDIT_DONE = FONT_PREFIX .. "LayoutEditDone",
    LINK = FONT_PREFIX .. "Link",
    -- Same size as LINK; bright red for destructive text actions.
    LINK_DANGER = FONT_PREFIX .. "LinkDanger",
    GLYPH = FONT_PREFIX .. "Glyph",
}

-- Sizes only: the face is always the game's locale font, since Latin-only faces lack CJK glyphs.
Assets.FontStyles = {
    [Assets.Fonts.TITLE] = { size = 14, color = Assets.Colors.TEXT },
    [Assets.Fonts.HEADER] = { size = 13, color = Assets.Colors.TEXT_MUTED },
    [Assets.Fonts.NAV_GROUP] = { size = 12, color = Assets.Colors.ACCENT },
    [Assets.Fonts.BODY] = { size = 12, color = Assets.Colors.TEXT },
    [Assets.Fonts.EMPHASIS] = { size = 14, color = Assets.Colors.TEXT, flags = "OUTLINE" },
    [Assets.Fonts.DISPLAY] = { size = 32, color = Assets.Colors.TEXT_GOLD, flags = "OUTLINE" },
    -- Amber + thick outline, ARHei for CJK raid-warning style callouts.
    [Assets.Fonts.CALLOUT] = {
        path = "Fonts\\ARHei.ttf",
        size = 56,
        color = Assets.Colors.WARNING,
        flags = "THICKOUTLINE",
    },
    [Assets.Fonts.MUTED] = { size = 12, color = Assets.Colors.TEXT_MUTED },
    [Assets.Fonts.SMALL_MUTED] = { size = 11, color = Assets.Colors.TEXT_MUTED },
    [Assets.Fonts.TINY_MUTED] = { size = 10, color = Assets.Colors.TEXT_MUTED },
    [Assets.Fonts.ON_ACCENT] = { size = 12, color = Assets.Colors.TEXT_ON_ACCENT },
    [Assets.Fonts.LAYOUT_EDIT_DONE] = { size = 16, color = Assets.Colors.TEXT_ON_ACCENT },
    [Assets.Fonts.LINK] = { size = 12, color = Assets.Colors.ACCENT },
    [Assets.Fonts.LINK_DANGER] = { size = 12, color = Assets.Colors.ERROR },
    [Assets.Fonts.GLYPH] = { size = 18, color = Assets.Colors.TEXT_MUTED },
}

Assets.Spacing = {
    TINY = 2,
    SMALL = 4,
    MEDIUM = 8,
    LARGE = 12,
    XLARGE = 16,
}

Assets.Sizes = {
    BORDER = 1,
    HEADER_HEIGHT = 48,
    HEADER_LOGO = 32,
    CLOSE_BUTTON = 22,
    -- Compact title bar when a settings panel is collapsed (outer frame height).
    COLLAPSED_PANEL_HEIGHT = 40,
    -- Fits logo + title + Edit Layout + collapse/close without the scale chrome.
    COLLAPSED_PANEL_WIDTH = 300,
    SLIDER_WIDTH = 96,
    SLIDER_HEIGHT = 16,
    SLIDER_TRACK = 2,
    SLIDER_THUMB_WIDTH = 8,
    SLIDER_THUMB_HEIGHT = 14,
    -- Fits the widest value label ("150%") so the slider doesn't shift as the text changes.
    SLIDER_VALUE_WIDTH = 36,
    NAV_ROW_HEIGHT = 28,
    NAV_GROUP_HEIGHT = 24,
    NAV_ACCENT_WIDTH = 2,
    SCROLL_BAR_WIDTH = 8,
    CONTROL_HEIGHT = 22,
    -- Rows holding buttons or inputs: a control fills its own height, so the row adds the
    -- vertical room that text gets for free, keeping gaps around controls as open as around text.
    CONTROL_ROW_HEIGHT = 30,
    -- Subsection title + bottom divider inside a feature body (e.g. Widgets.LayoutSectionHeader).
    CONTENT_SECTION_HEADER = 22,
    INPUT_HEIGHT = 24,
    CHECKBOX = 12,
    -- Gap between the checkbox border and its checked fill.
    CHECKBOX_FILL_INSET = 2,
    ROLE_ICON = 14,
    BUTTON_MIN_WIDTH = 64,
    BUTTON_TEXT_PADDING = 20,
    -- Prominent Done control while repositioning floating UI.
    LAYOUT_EDIT_DONE_HEIGHT = 36,
    LAYOUT_EDIT_DONE_MIN_WIDTH = 120,
    LAYOUT_EDIT_DONE_TEXT_PADDING = 36,
    SEGMENT_TEXT_PADDING = 16,
    -- Fits two digits so the stepper doesn't shift as the value changes.
    STEPPER_VALUE_WIDTH = 28,
    EXPAND_ARROW = 10,
    EXPAND_ARROW_THICKNESS = 2,
    -- Drawn caret on dropdown triggers (same line technique as EXPAND_ARROW).
    DROPDOWN_CARET = 10,
    DROPDOWN_CARET_THICKNESS = 2,
    INPUT_DIGIT_WIDTH = 8,
    INPUT_TEXT_PADDING = 16,
    -- Square color swatch for ColorPickerFrame controls.
    COLOR_SWATCH = 22,
    DROPDOWN_MIN_WIDTH = 96,
    -- Left text inset plus room for the caret on the right.
    DROPDOWN_TEXT_PADDING = 28,
    -- Visible rows before the popup scrolls on its own (keeps LSM lists usable).
    DROPDOWN_MAX_VISIBLE = 8,
}

-- World markers share their icons with raid target icons.
Assets.WORLD_MARKER_ICONS = {
    STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
    CIRCLE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2",
    DIAMOND = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
    TRIANGLE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4",
    MOON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5",
    SQUARE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
    CROSS = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
    SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
}

Assets.ROLE_ATLASES = {
    TANK = "groupfinder-icon-role-large-tank",
    HEALER = "groupfinder-icon-role-large-heal",
    DAMAGER = "groupfinder-icon-role-large-dps",
}
