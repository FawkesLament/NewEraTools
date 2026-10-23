local _, ns = ...

local Speech = {}
ns.Api.Speech = Speech

---A secret value throws on comparison, including `value == ""`. Check this before any other use.
---@param value any
---@return boolean
local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

---False when `text` is missing, empty, or secret. Callers must check this before formatting or speaking.
---@param text any
---@return boolean
function Speech.IsPlainText(text)
    if IsSecret(text) then
        return false
    end
    return type(text) == "string" and text ~= ""
end

-- Chat tags and their raid-target index. Names come from RAID_TARGET_1..8.
local RAID_ICON_TAGS = {
    rt1 = 1,
    rticon1 = 1,
    star = 1,
    rt2 = 2,
    rticon2 = 2,
    circle = 2,
    coin = 2,
    rt3 = 3,
    rticon3 = 3,
    diamond = 3,
    rt4 = 4,
    rticon4 = 4,
    triangle = 4,
    rt5 = 5,
    rticon5 = 5,
    moon = 5,
    rt6 = 6,
    rticon6 = 6,
    square = 6,
    rt7 = 7,
    rticon7 = 7,
    cross = 7,
    x = 7,
    rt8 = 8,
    rticon8 = 8,
    skull = 8,
}

---@param index number
---@return string|nil
local function RaidTargetName(index)
    local name = _G["RAID_TARGET_" .. index]
    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

---Turns `{rt1}` / `{star}` and raid-target texture escapes into the localized marker name.
---@param text string
---@return string
local function ExpandRaidIcons(text)
    text = text:gsub("{([%w]+)}", function(tag)
        local index = RAID_ICON_TAGS[tag:lower()]
        if not index then
            return "{" .. tag .. "}"
        end
        return RaidTargetName(index) or ("{" .. tag .. "}")
    end)
    text = text:gsub("|T[^|]*UI%-RaidTargetingIcon_(%d+)[^|]*|t", function(index)
        return RaidTargetName(tonumber(index)) or ""
    end)
    return text
end

---@param name string|nil
---@return boolean
local function VoiceNameLooksChinese(name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    local lower = name:lower()
    if lower:find("chinese", 1, true) then
        return true
    end
    if
        lower:find("zh-cn", 1, true)
        or lower:find("zh_cn", 1, true)
        or lower:find("zh-tw", 1, true)
        or lower:find("zh_tw", 1, true)
        or lower:find("zh-hk", 1, true)
        or lower:find("zh_hk", 1, true)
    then
        return true
    end
    return name:find("中文", 1, true)
        or name:find("简体", 1, true)
        or name:find("繁体", 1, true)
        or name:find("繁體", 1, true)
end

---@return { voiceID: number, name: string }[]|nil
local function VoiceList()
    if not C_VoiceChat or type(C_VoiceChat.GetTtsVoices) ~= "function" then
        return nil
    end
    local voices = C_VoiceChat.GetTtsVoices()
    if type(voices) ~= "table" then
        return nil
    end
    -- Blizzard may return a map rather than a dense array.
    local list = {}
    for _, voice in pairs(voices) do
        if type(voice) == "table" and type(voice.voiceID) == "number" then
            list[#list + 1] = voice
        end
    end
    return list
end

---@param voices { voiceID: number, name: string }[]
---@param voiceID number
---@return { voiceID: number, name: string }|nil
local function FindVoice(voices, voiceID)
    for index = 1, #voices do
        local voice = voices[index]
        if voice and voice.voiceID == voiceID then
            return voice
        end
    end
    return nil
end

---@param voices { voiceID: number, name: string }[]
---@return number|nil
local function FirstChineseVoiceID(voices)
    for index = 1, #voices do
        local voice = voices[index]
        if voice and VoiceNameLooksChinese(voice.name) then
            return voice.voiceID
        end
    end
    return nil
end

---@return number
local function PreferredVoiceID()
    if C_TTSSettings and type(C_TTSSettings.GetVoiceOptionID) == "function" then
        return C_TTSSettings.GetVoiceOptionID(0) or 0
    end
    return 0
end

---@return boolean
local function ClientIsChinese()
    local locale = GetLocale()
    return locale == "zhCN" or locale == "zhTW"
end

---Uses the player's Standard voice, unless the client is Chinese and another installed voice can read it.
---Lookup is pcalled: a bad voice list must not skip SpeakText.
---@return number
local function ResolveVoiceID()
    local preferred = PreferredVoiceID()
    local ok, voiceID = pcall(function()
        if not ClientIsChinese() then
            return preferred
        end
        local voices = VoiceList()
        if not voices then
            return preferred
        end
        local selected = FindVoice(voices, preferred)
        if selected and VoiceNameLooksChinese(selected.name) then
            return preferred
        end
        return FirstChineseVoiceID(voices) or preferred
    end)
    if ok and type(voiceID) == "number" then
        return voiceID
    end
    return preferred
end

---@return number
---@return number
local function SpeechRateAndVolume()
    local rate = 0
    local volume = 100
    if C_TTSSettings then
        if type(C_TTSSettings.GetSpeechRate) == "function" then
            rate = C_TTSSettings.GetSpeechRate() or 0
        end
        if type(C_TTSSettings.GetSpeechVolume) == "function" then
            volume = C_TTSSettings.GetSpeechVolume() or 100
        end
    end
    return rate, volume
end

---Speaks `text` on a voice that can read it. No-op when the client has no TTS API.
---Patch 12.0 SpeakText is (voiceID, text, rate, volume[, overlap]); destination was removed.
---@param text string
function Speech.Say(text)
    if not Speech.IsPlainText(text) then
        return
    end
    if not C_VoiceChat or type(C_VoiceChat.SpeakText) ~= "function" then
        return
    end
    text = ExpandRaidIcons(text)
    if text == "" then
        return
    end
    local rate, volume = SpeechRateAndVolume()
    C_VoiceChat.SpeakText(ResolveVoiceID(), text, rate, volume)
end
