local _, ns = ...

local Assets = {}
ns.Assets = Assets

local MEDIA_PATH = "Interface\\AddOns\\" .. ns.ADDON_NAME .. "\\media\\"

Assets.LOGO = MEDIA_PATH .. "icons\\logo"
Assets.MINI_LOGO = MEDIA_PATH .. "icons\\mini_logo"

Assets.Textures = {
    -- A plain white square; tinted with SetVertexColor or used as a backdrop for flat fills.
    WHITE = "Interface\\Buttons\\WHITE8x8",
    -- Mask texture that clips a texture to a circle.
    CIRCLE_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
    MINIMAP_HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
    MINIMAP_BACKGROUND = "Interface\\Minimap\\UI-Minimap-Background",
    MINIMAP_BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder",
}

Assets.Templates = {
    BACKDROP = "BackdropTemplate",
    SCROLL_BAR = "MinimalScrollBar",
}

Assets.Glyphs = {
    CLOSE = "×",
    -- ASCII, since not every locale font has the Unicode minus sign.
    DECREASE = "-",
    INCREASE = "+",
}

Assets.Colors = {
    BG = { r = 0.071, g = 0.075, b = 0.090, a = 0.95 },
    -- For windows left open over the game world, which should stay visible through them.
    BG_TRANSLUCENT = { r = 0.071, g = 0.075, b = 0.090, a = 0.6 },
    SURFACE = { r = 0.102, g = 0.110, b = 0.133, a = 1 },
    SURFACE_RAISED = { r = 0.137, g = 0.149, b = 0.180, a = 1 },
    BORDER = { r = 0.180, g = 0.196, b = 0.231, a = 1 },
    HOVER = { r = 1, g = 1, b = 1, a = 0.06 },
    TEXT = { r = 0.902, g = 0.910, b = 0.922 },
    TEXT_MUTED = { r = 0.545, g = 0.565, b = 0.604 },
    TEXT_ON_ACCENT = { r = 0.071, g = 0.075, b = 0.090 },
    ACCENT = { r = 0.310, g = 0.765, b = 0.710, a = 1 },
    WARNING = { r = 0.945, g = 0.643, b = 0.267, a = 1 },
    ERROR = { r = 0.898, g = 0.282, b = 0.302 },
    DIVIDER = { r = 0.180, g = 0.196, b = 0.231, a = 1 },
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
    MUTED = FONT_PREFIX .. "Muted",
    SMALL_MUTED = FONT_PREFIX .. "SmallMuted",
    ON_ACCENT = FONT_PREFIX .. "OnAccent",
    LINK = FONT_PREFIX .. "Link",
    GLYPH = FONT_PREFIX .. "Glyph",
}

-- Sizes only: the face is always the game's locale font, since Latin-only faces lack CJK glyphs.
Assets.FontStyles = {
    [Assets.Fonts.TITLE] = { size = 14, color = Assets.Colors.TEXT },
    [Assets.Fonts.HEADER] = { size = 13, color = Assets.Colors.TEXT_MUTED },
    [Assets.Fonts.NAV_GROUP] = { size = 12, color = Assets.Colors.ACCENT },
    [Assets.Fonts.BODY] = { size = 12, color = Assets.Colors.TEXT },
    [Assets.Fonts.EMPHASIS] = { size = 14, color = Assets.Colors.TEXT, flags = "OUTLINE" },
    [Assets.Fonts.MUTED] = { size = 12, color = Assets.Colors.TEXT_MUTED },
    [Assets.Fonts.SMALL_MUTED] = { size = 11, color = Assets.Colors.TEXT_MUTED },
    [Assets.Fonts.ON_ACCENT] = { size = 12, color = Assets.Colors.TEXT_ON_ACCENT },
    [Assets.Fonts.LINK] = { size = 12, color = Assets.Colors.ACCENT },
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
    CLOSE_BUTTON = 24,
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
    CONTROL_HEIGHT = 24,
    -- Rows holding buttons or inputs: a control fills its own height, so the row adds the
    -- vertical room that text gets for free, keeping gaps around controls as open as around text.
    CONTROL_ROW_HEIGHT = 32,
    INPUT_HEIGHT = 24,
    CHECKBOX = 14,
    -- Gap between the checkbox border and its checked fill.
    CHECKBOX_FILL_INSET = 3,
    ROLE_ICON = 14,
    BUTTON_MIN_WIDTH = 72,
    BUTTON_TEXT_PADDING = 24,
    SEGMENT_TEXT_PADDING = 20,
    -- Fits two digits so the stepper doesn't shift as the value changes.
    STEPPER_VALUE_WIDTH = 28,
    EXPAND_ARROW = 10,
    EXPAND_ARROW_THICKNESS = 2,
    INPUT_DIGIT_WIDTH = 8,
    INPUT_TEXT_PADDING = 16,
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
