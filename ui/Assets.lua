local _, ns = ...

local Assets = {}
ns.Assets = Assets

local MEDIA_PATH = "Interface\\AddOns\\" .. ns.ADDON_NAME .. "\\media\\"

Assets.LOGO = MEDIA_PATH .. "icons\\logo"
Assets.MINI_LOGO = MEDIA_PATH .. "icons\\mini_logo"

-- Bundled typefaces for SetFont; include the file extension.
Assets.FontFiles = {
    EXPRESSWAY = MEDIA_PATH .. "fonts\\Expressway.ttf",
}

-- Custom font files load on first SetFont; text painted before that finishes stays blank
-- until the string changes again. STANDARD_TEXT_FONT is already loaded.
local fontFilesWarmed = false

---Loads every bundled font file so later FontStrings can paint immediately.
function Assets.PrewarmFontFiles()
    if fontFilesWarmed then
        return
    end
    if type(UIParent) ~= "table" and type(UIParent) ~= "userdata" then
        return
    end
    if not UIParent.CreateFontString then
        return
    end
    local warm = UIParent:CreateFontString(nil, "BACKGROUND")
    if not warm or not warm.SetFont then
        return
    end
    fontFilesWarmed = true
    if warm.SetPoint then
        warm:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 100, -100)
    end
    if warm.SetAlpha then
        warm:SetAlpha(0)
    end
    for _, path in pairs(Assets.FontFiles) do
        warm:SetFont(path, 12, "")
        if warm.SetText then
            warm:SetText("0123456789")
        end
    end
end

Assets.PrewarmFontFiles()

Assets.Textures = {
    -- A plain white square; tinted with SetVertexColor or used as a backdrop for flat fills.
    WHITE = "Interface\\Buttons\\WHITE8x8",
    -- Soft vertical flare used as a progress-bar playhead glow (tinted, ADD blend).
    CASTING_SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark",
    -- Built-in status-bar fills (also listed in STATUS_BAR_TEXTURES for pickers).
    STATUS_BAR = "Interface\\TargetingFrame\\UI-StatusBar",
    RAID_BAR = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    -- Mask texture that clips a texture to a circle.
    CIRCLE_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
    -- Rounded-square HUD chip (media/icons/interrupt_badge_ice_blue.tga).
    ROUNDED_SQUARE = MEDIA_PATH .. "icons\\interrupt_badge_ice_blue",
    -- White 64x64 rounded squares; tinted with SetVertexColor (border black, fill scheme).
    INTERRUPT_INDICATOR_BADGE_BORDER = MEDIA_PATH .. "icons\\interrupt_indicator_badge_border",
    INTERRUPT_INDICATOR_BADGE_FILL = MEDIA_PATH .. "icons\\interrupt_indicator_badge_fill",
    -- White-on-alpha handwritten checkmark (128x128); tint with SetVertexColor.
    CHECKMARK = MEDIA_PATH .. "icons\\checkmark",
    -- Faceted 64x32 downward dart for interrupt-chain playheads; tint with SetVertexColor.
    ARROW_DOWN = MEDIA_PATH .. "icons\\arrow_down",
    -- White-on-alpha double chevrons for the Ulatek wave-order pad; tint with SetVertexColor.
    ARROW_DOUBLE_CHEVRON_LEFT = MEDIA_PATH .. "icons\\arrow_double_chevron_left",
    ARROW_DOUBLE_CHEVRON_RIGHT = MEDIA_PATH .. "icons\\arrow_double_chevron_right",
    -- White-on-alpha 8-dot dashed circle for the Ulatek boss-rise pad; tint with SetVertexColor.
    DASHED_CIRCLE_8_DOT = MEDIA_PATH .. "icons\\dashed_circle_8_dot",
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
    -- SecureActionButton runs the edge-marker callout macro.
    SECURE_ACTION_BUTTON = "SecureActionButtonTemplate,SecureHandlerBaseTemplate",
}

Assets.Glyphs = {
    CLOSE = "×",
    -- Em dash, so the stepper's minus reads at the same weight as +.
    DECREASE = "–",
    INCREASE = "+",
    -- Panel title-bar collapse / expand (same ASCII glyphs as the steppers).
    COLLAPSE = "―",
    EXPAND = "＋",
    -- Table header sort direction (AddonCheck results and similar).
    SORT_ASC = "▲",
    SORT_DESC = "▼",
}

---Copies RGB from `c` and returns a new table. Never mutates the source color.
---@param c { r: number, g: number, b: number }
---@param a number
---@return { r: number, g: number, b: number, a: number }
local function WithAlpha(c, a)
    return { r = c.r, g = c.g, b = c.b, a = a }
end

-- Shared RGB bases. Domain tokens copy or wrap these; do not mutate Palette entries.
local Palette = {
    OVERLAY_DARK = { r = 0.071, g = 0.075, b = 0.090, a = 1 },
    BORDER_BASE = { r = 0.180, g = 0.196, b = 0.231, a = 1 },
    -- Matte gold (#C9A65C); matches the NEW ERA logo and menu structure marks.
    GOLD = { r = 0.788, g = 0.651, b = 0.361, a = 1 },
    -- Restrained teal (#329490); menu interactive controls only.
    TEAL = { r = 0.196, g = 0.580, b = 0.565, a = 1 },
    -- Bright cyan kept for interrupt HUD / layout-edit / combat overlays.
    CYAN_BRIGHT = { r = 0.310, g = 0.765, b = 0.710, a = 1 },
    BLACK = { r = 0, g = 0, b = 0, a = 1 },
    WHITE = { r = 1, g = 1, b = 1, a = 1 },
}

Assets.Colors = {
    -- 1. Menu Window & Surfaces
    -- Main settings window only. Do not reuse on HUD / overlays (those keep BG / SURFACE).
    -- Title/sidebar paints are opaque so they do not composite over MENU_CONTENT.
    MENU_TITLE_BAR = { r = 0.055, g = 0.067, b = 0.086, a = 1 },
    MENU_SIDEBAR = { r = 0.075, g = 0.090, b = 0.118, a = 1 },
    -- Outer window fill and the right-hand content floor (only semi-transparent layer).
    MENU_CONTENT = { r = 0.094, g = 0.110, b = 0.141, a = 0.96 },
    -- 1px outer edge: brighter than MENU_TITLE_BAR, quieter than BORDER.
    MENU_WINDOW_BORDER = { r = 0.145, g = 0.160, b = 0.192, a = 0.85 },
    -- Title/sidebar/content seams; luminance does the real split.
    MENU_DIVIDER = WithAlpha(Palette.WHITE, 0.06),
    -- FeatureSection card: brighter than MENU_CONTENT, and brighter than SURFACE so nested
    -- info boxes (SURFACE) read as inset wells instead of blending into the card.
    FEATURE_CARD_BG = { r = 0.125, g = 0.149, b = 0.192, a = 1 },
    FEATURE_CARD_BORDER = { r = 0.220, g = 0.238, b = 0.280, a = 1 },
    FEATURE_CARD_BORDER_DISABLED = { r = 0.155, g = 0.168, b = 0.198, a = 0.85 },
    FEATURE_CARD_ACCENT = WithAlpha(Palette.GOLD, 1),
    FEATURE_CARD_ACCENT_DISABLED = { r = 0.275, g = 0.290, b = 0.325, a = 1 },
    SURFACE = { r = 0.102, g = 0.110, b = 0.133, a = 1 },
    SURFACE_RAISED = { r = 0.137, g = 0.149, b = 0.180, a = 1 },
    BORDER = WithAlpha(Palette.BORDER_BASE, 1),
    DIVIDER = WithAlpha(Palette.BORDER_BASE, 1),
    HOVER = WithAlpha(Palette.WHITE, 0.06),

    -- 2. Accents & Interactive Controls
    -- Bright cyan: interrupt HUD, layout-edit chrome, and combat overlays.
    ACCENT = WithAlpha(Palette.CYAN_BRIGHT, 1),
    MENU_ACCENT_GOLD = WithAlpha(Palette.GOLD, 1),
    -- Teal: settings-window toggles, sliders, checkboxes, buttons, and selected wells.
    MENU_ACCENT = WithAlpha(Palette.TEAL, 1),
    -- ToggleSwitch: on = accent track + near-white thumb; off = inset well + muted thumb.
    TOGGLE_THUMB_ON = { r = 0.98, g = 0.99, b = 1, a = 1 },
    TOGGLE_THUMB_OFF = { r = 0.42, g = 0.45, b = 0.50, a = 1 },
    TOGGLE_TRACK_OFF = { r = 0.055, g = 0.060, b = 0.078, a = 1 },
    TOGGLE_TRACK_OFF_BORDER = { r = 0.145, g = 0.155, b = 0.180, a = 1 },
    -- SegmentedControl selected: ~22% MENU_ACCENT mixed into SURFACE_RAISED.
    SEGMENT_SELECTED_FILL = { r = 0.150, g = 0.244, b = 0.265, a = 1 },
    -- SegmentedControl thumb: one step brighter than FEATURE_CARD_BG, no teal tint.
    SEGMENT_THUMB_BG = { r = 0.196, g = 0.227, b = 0.282, a = 1 },
    SEGMENT_THUMB_BORDER = { r = 0.290, g = 0.329, b = 0.396, a = 1 },
    TEXT_ON_ACCENT = { r = Palette.OVERLAY_DARK.r, g = Palette.OVERLAY_DARK.g, b = Palette.OVERLAY_DARK.b },

    -- 3. Typography
    TEXT = { r = 0.902, g = 0.910, b = 0.922 },
    -- Menu settings typography (L1–L4). HUD overlays keep TEXT / TEXT_MUTED.
    TEXT_PRIMARY = { r = 0.96, g = 0.97, b = 0.98 },
    TEXT_HEADING = { r = 0.88, g = 0.90, b = 0.94 },
    TEXT_BODY = { r = 0.68, g = 0.72, b = 0.78 },
    TEXT_HINT = { r = 0.48, g = 0.52, b = 0.58 },
    TEXT_MUTED = { r = 0.545, g = 0.565, b = 0.604 },
    -- Light gold for prominent readouts (e.g. combat timers).
    TEXT_GOLD = { r = 0.93, g = 0.82, b = 0.48 },

    -- 4. Semantic Status
    SUCCESS = { r = 0.35, g = 0.80, b = 0.40 },
    WARNING = { r = 0.945, g = 0.643, b = 0.267, a = 1 },
    ERROR = { r = 0.898, g = 0.282, b = 0.302 },
    -- Soft coral (#e8705e); warmer and less saturated than ERROR.
    DANGER = { r = 0.910, g = 0.439, b = 0.369, a = 1 },

    -- 5. Layout Edit Mode & World Overlays / HUD
    BG = WithAlpha(Palette.OVERLAY_DARK, 0.95),
    -- For windows left open over the game world, which should stay visible through them.
    BG_TRANSLUCENT = WithAlpha(Palette.OVERLAY_DARK, 0.6),
    -- Slightly more see-through than BG_TRANSLUCENT; for warning overlays.
    BG_WARNING = WithAlpha(Palette.OVERLAY_DARK, 0.8),
    -- No fill; for HUD overlays that should only show their own content.
    TRANSPARENT = WithAlpha(Palette.BLACK, 0),
    -- Softer edge for compact floating overlays.
    BORDER_SUBTLE = { r = 0.55, g = 0.58, b = 0.65, a = 0.55 },
    -- 1px white hairline for compact cards (toast edge / split).
    BORDER_FAINT = WithAlpha(Palette.WHITE, 0.08),
    -- Amber edge for warning overlays.
    BORDER_WARNING = { r = 0.90, g = 0.70, b = 0.25, a = 0.75 },
    -- Subtle outline / label for layout edit mode previews.
    LAYOUT_EDIT_OUTLINE = WithAlpha(Palette.CYAN_BRIGHT, 0.55),
    LAYOUT_EDIT_OUTLINE_SELECTED = WithAlpha(Palette.CYAN_BRIGHT, 1),
    LAYOUT_EDIT_LABEL = WithAlpha(Palette.CYAN_BRIGHT, 0.9),
    -- Full-screen veil behind editable elements (one static texture; no per-frame work).
    LAYOUT_EDIT_DIMMER = WithAlpha(Palette.BLACK, 0.55),
    -- Interrupt rotation tracker: assigned-slot edge and header/role accents.
    STATUS_HUD_EMPHASIS_BORDER = WithAlpha(Palette.CYAN_BRIGHT, 0.72),
    -- Top-row region (#E2E8F0) and assigned-slot accent #86D9FF.
    STATUS_HUD_REGION = { r = 0.886, g = 0.910, b = 0.941 },
    STATUS_HUD_EMPHASIS_ROLE = { r = 0.525, g = 0.851, b = 1 },
}

-- Shared game textures used by floating overlays.
Assets.Icons = {
    WARNING = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
    -- Blue information mark for neutral status lines.
    INFO = "Interface\\FriendsFrame\\InformationIcon",
    -- Standard placeholder when a spell ID has no resolvable icon.
    QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark",
    -- Minimap player arrow (points up); rotate with SetRotation for path tips.
    PATH_ARROW = "Interface\\Minimap\\MinimapArrow",
    -- Neutral clock (auction-house atlas). Not a warning mark.
    CLOCK = "auctionhouse-icon-clock",
    -- Raid ready-check marks (AddonCheck status column).
    READY_CHECK_READY = "Interface\\RaidFrame\\ReadyCheck-Ready",
    READY_CHECK_NOT_READY = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    READY_CHECK_WAITING = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}

local FONT_PREFIX = ns.ADDON_NAME .. "Font"

-- Names of font objects created by ns.Widgets on first use.
Assets.Fonts = {
    -- Menu / Settings UI
    TITLE = FONT_PREFIX .. "Title",
    HEADER = FONT_PREFIX .. "Header",
    NAV_GROUP = FONT_PREFIX .. "NavGroup",
    SUBTITLE = FONT_PREFIX .. "Subtitle",
    BODY = FONT_PREFIX .. "Body",
    MUTED = FONT_PREFIX .. "Muted",
    SMALL_MUTED = FONT_PREFIX .. "SmallMuted",
    ON_ACCENT = FONT_PREFIX .. "OnAccent",
    LINK = FONT_PREFIX .. "Link",
    -- Same size as LINK; bright red for destructive text actions.
    LINK_DANGER = FONT_PREFIX .. "LinkDanger",
    GLYPH = FONT_PREFIX .. "Glyph",
    -- Larger +/- on stepper buttons; body text stays at 12.
    STEPPER = FONT_PREFIX .. "Stepper",
    -- World Overlays & HUD
    -- Larger body face for copyable generated text (e.g. interrupt macros).
    PAYLOAD = FONT_PREFIX .. "Payload",
    -- Slightly larger with an outline; for short emphasized spans (e.g. marker names).
    EMPHASIS = FONT_PREFIX .. "Emphasis",
    -- Large outlined readout for floating overlays (e.g. timers).
    DISPLAY = FONT_PREFIX .. "Display",
    -- Very large outlined callout text over the game world (e.g. Sszorak raid markers).
    CALLOUT = FONT_PREFIX .. "Callout",
    -- Interrupt rotation tracker header: same ARHei face as CALLOUT, smaller size.
    STATUS_HUD_TITLE = FONT_PREFIX .. "StatusHudTitle",
    -- One step below SMALL_MUTED; for quiet footnotes on overlays.
    TINY_MUTED = FONT_PREFIX .. "TinyMuted",
    -- Larger on-accent face for the layout-edit Done control.
    LAYOUT_EDIT_DONE = FONT_PREFIX .. "LayoutEditDone",
    -- Outlined damage-number face (伤害数字 / DAMAGE_TEXT_FONT). Default for numeric overlays.
    OVERLAY_DIGIT = FONT_PREFIX .. "OverlayDigit",
}

-- Default face is the game's locale font (CJK-safe). Styles may set `path` for a fixed face.
Assets.FontStyles = {
    -- Menu / Settings UI
    [Assets.Fonts.TITLE] = { size = 16, color = Assets.Colors.TEXT_PRIMARY },
    [Assets.Fonts.HEADER] = { size = 16, color = Assets.Colors.TEXT_PRIMARY },
    [Assets.Fonts.NAV_GROUP] = { size = 12, color = Assets.Colors.TEXT_HINT },
    [Assets.Fonts.SUBTITLE] = { size = 13, color = Assets.Colors.TEXT_HEADING },
    [Assets.Fonts.BODY] = { size = 12, color = Assets.Colors.TEXT_BODY },
    [Assets.Fonts.MUTED] = { size = 12, color = Assets.Colors.TEXT_HINT },
    [Assets.Fonts.SMALL_MUTED] = { size = 11, color = Assets.Colors.TEXT_HINT },
    [Assets.Fonts.ON_ACCENT] = { size = 12, color = Assets.Colors.TEXT_ON_ACCENT },
    [Assets.Fonts.LINK] = { size = 12, color = Assets.Colors.MENU_ACCENT },
    [Assets.Fonts.LINK_DANGER] = { size = 12, color = Assets.Colors.ERROR },
    [Assets.Fonts.GLYPH] = { size = 18, color = Assets.Colors.TEXT_MUTED },
    [Assets.Fonts.STEPPER] = { size = 18, color = Assets.Colors.TEXT_HEADING },
    -- World Overlays & HUD
    [Assets.Fonts.EMPHASIS] = { size = 14, color = Assets.Colors.TEXT, flags = "OUTLINE" },
    [Assets.Fonts.DISPLAY] = { size = 32, color = Assets.Colors.TEXT_GOLD, flags = "OUTLINE" },
    -- Amber + thick outline, ARHei for CJK raid-warning style callouts.
    [Assets.Fonts.CALLOUT] = {
        path = "Fonts\\ARHei.ttf",
        size = 56,
        color = Assets.Colors.WARNING,
        flags = "THICKOUTLINE",
    },
    [Assets.Fonts.STATUS_HUD_TITLE] = {
        path = "Fonts\\ARHei.ttf",
        size = 14,
        color = Assets.Colors.STATUS_HUD_REGION,
        flags = "OUTLINE",
    },
    [Assets.Fonts.TINY_MUTED] = { size = 10, color = Assets.Colors.TEXT_MUTED },
    [Assets.Fonts.LAYOUT_EDIT_DONE] = { size = 16, color = Assets.Colors.TEXT_ON_ACCENT },
    [Assets.Fonts.OVERLAY_DIGIT] = {
        path = DAMAGE_TEXT_FONT,
        size = 22,
        color = Assets.Colors.TEXT_GOLD,
        flags = "OUTLINE",
    },
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
    -- Inset around title and close control on FloatingWindow headers.
    FLOATING_HEADER_PAD = 12,
    -- Compact title bar when a settings panel is collapsed (outer frame height).
    COLLAPSED_PANEL_HEIGHT = 40,
    -- Fits logo + title + Edit Layout (with its move icon) + collapse/close without the scale chrome.
    COLLAPSED_PANEL_WIDTH = 320,
    SLIDER_WIDTH = 96,
    SLIDER_HEIGHT = 16,
    SLIDER_TRACK = 2,
    SLIDER_THUMB_WIDTH = 8,
    SLIDER_THUMB_HEIGHT = 14,
    -- Fits the widest scale readout ("150%") so the header slider doesn't shift as it changes.
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
    -- Compact header On/Off switch; 2px shorter than CONTROL_HEIGHT so it sits centered in the row.
    TOGGLE_WIDTH = 40,
    TOGGLE_HEIGHT = 20,
    TOGGLE_THUMB_INSET = 2,
    ROLE_ICON = 14,
    BUTTON_MIN_WIDTH = 64,
    BUTTON_TEXT_PADDING = 20,
    -- Muted corner-bracket mark on buttons that enter layout editing.
    LAYOUT_EDIT_ICON = 12,
    LAYOUT_EDIT_ICON_THICKNESS = 1,
    -- Prominent Done control while repositioning floating UI.
    LAYOUT_EDIT_DONE_HEIGHT = 36,
    LAYOUT_EDIT_DONE_MIN_WIDTH = 120,
    LAYOUT_EDIT_DONE_TEXT_PADDING = 36,
    -- Compact coordinate inspector while repositioning floating UI.
    LAYOUT_INSPECTOR_WIDTH = 260,
    LAYOUT_INSPECTOR_OFFSET_DIGITS = 5,
    LAYOUT_EDIT_OUTLINE_EDGE = 1,
    LAYOUT_EDIT_OUTLINE_EDGE_SELECTED = 2,
    SEGMENT_TEXT_PADDING = 16,
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

-- Close control plus vertical padding on FloatingWindow headers.
Assets.Sizes.FLOATING_HEADER_HEIGHT = Assets.Sizes.CLOSE_BUTTON + 2 * Assets.Sizes.FLOATING_HEADER_PAD

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
