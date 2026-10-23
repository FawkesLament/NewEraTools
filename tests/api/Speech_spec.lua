-- Production api/Speech.lua. Feature specs keep tests/helpers/fakes/Speech.lua.

describe("Speech", function()
    local savedVoice, savedSettings, savedEnum, savedGetLocale, savedRaidTargets, savedIsSecret

    before_each(function()
        savedVoice, savedSettings, savedEnum, savedGetLocale = C_VoiceChat, C_TTSSettings, Enum, GetLocale
        savedIsSecret = issecretvalue
        savedRaidTargets = {}
        for index = 1, 8 do
            local key = "RAID_TARGET_" .. index
            savedRaidTargets[key] = _G[key]
        end
    end)

    after_each(function()
        C_VoiceChat, C_TTSSettings, Enum, GetLocale = savedVoice, savedSettings, savedEnum, savedGetLocale
        issecretvalue = savedIsSecret
        for key, value in pairs(savedRaidTargets) do
            _G[key] = value
        end
    end)

    local function Load()
        local ns = { Api = {} }
        assert(loadfile("api/Speech.lua"))("NewEraTools", ns)
        return ns.Api.Speech
    end

    ---@param voices { voiceID: number, name: string }[]|nil
    ---@param locale string
    local function CaptureSpeak(voices, locale)
        local calls = {}
        GetLocale = function()
            return locale
        end
        C_VoiceChat = {
            SpeakText = function(...)
                calls[#calls + 1] = { ... }
            end,
            GetTtsVoices = function()
                return voices
            end,
        }
        C_TTSSettings = {
            GetVoiceOptionID = function()
                return 7
            end,
            GetSpeechRate = function()
                return 2
            end,
            GetSpeechVolume = function()
                return 80
            end,
        }
        Enum = nil
        return calls
    end

    it("uses the selected voice on a non-Chinese client", function()
        local calls = CaptureSpeak({
            { voiceID = 7, name = "Microsoft Zira Desktop - English (United States)" },
            { voiceID = 3, name = "Microsoft Huihui Desktop - Chinese (Simplified, PRC)" },
        }, "enUS")
        Load().Say("准备打断")
        assert.same({ { 7, "准备打断", 2, 80 } }, calls)
    end)

    it("uses a Chinese voice when the Chinese client selected an English voice", function()
        local calls = CaptureSpeak({
            { voiceID = 7, name = "Microsoft Zira Desktop - English (United States)" },
            { voiceID = 3, name = "Microsoft Huihui Desktop - Chinese (Simplified, PRC)" },
        }, "zhCN")
        Load().Say("Soak now")
        assert.same({ { 3, "Soak now", 2, 80 } }, calls)
    end)

    it("keeps the selected voice when it already reads Chinese", function()
        local calls = CaptureSpeak({
            { voiceID = 7, name = "Microsoft Yaoyao Desktop - 中文(简体，中国)" },
            { voiceID = 3, name = "Microsoft Huihui Desktop - Chinese (Simplified, PRC)" },
        }, "zhTW")
        Load().Say("准备打断")
        assert.same({ { 7, "准备打断", 2, 80 } }, calls)
    end)

    it("uses Chinese voice id 0 when that is the installed Chinese voice", function()
        local calls = CaptureSpeak({
            { voiceID = 0, name = "Microsoft Huihui Desktop - Chinese (Simplified)" },
            { voiceID = 1, name = "Microsoft Zira Desktop - English (United States)" },
            { voiceID = 2, name = "Microsoft David Desktop - English (United States)" },
        }, "zhCN")
        C_TTSSettings.GetVoiceOptionID = function()
            return 1
        end
        Load().Say("准备打断")
        assert.same({ { 0, "准备打断", 2, 80 } }, calls)
    end)

    it("uses the selected voice when listing voices fails", function()
        local calls = CaptureSpeak(nil, "zhCN")
        C_VoiceChat.GetTtsVoices = function()
            error("voices unavailable")
        end
        Load().Say("准备打断")
        assert.same({ { 7, "准备打断", 2, 80 } }, calls)
    end)

    it("keeps the selected voice when no Chinese voice is installed", function()
        local calls = CaptureSpeak({
            { voiceID = 7, name = "Microsoft Zira Desktop - English (United States)" },
        }, "zhCN")
        Load().Say("准备打断")
        assert.same({ { 7, "准备打断", 2, 80 } }, calls)
    end)

    it("does nothing when the client has no text-to-speech API", function()
        GetLocale = function()
            return "zhCN"
        end
        C_VoiceChat = nil
        C_TTSSettings = nil
        Enum = nil
        Load().Say("准备打断")
    end)

    it("speaks raid target tags as the localized marker name", function()
        _G.RAID_TARGET_1 = "星形"
        _G.RAID_TARGET_3 = "菱形"
        local calls = CaptureSpeak({
            { voiceID = 0, name = "Microsoft Huihui Desktop - Chinese (Simplified)" },
        }, "zhCN")
        Load().Say("去 {rt1} 放球")
        Load().Say("去 |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_3:0|t 放球")
        assert.same({
            { 0, "去 星形 放球", 2, 80 },
            { 0, "去 菱形 放球", 2, 80 },
        }, calls)
    end)

    it("does not speak a secret value", function()
        local secret = {}
        issecretvalue = function(value)
            return value == secret
        end
        local calls = CaptureSpeak({
            { voiceID = 7, name = "Microsoft Zira Desktop - English (United States)" },
        }, "enUS")
        Load().Say(secret)
        assert.same({}, calls)
        assert.is_false(Load().IsPlainText(secret))
    end)

    it("ignores an empty phrase", function()
        local calls = 0
        C_VoiceChat = {
            SpeakText = function()
                calls = calls + 1
            end,
        }
        Load().Say("")
        assert.equals(0, calls)
    end)
end)
