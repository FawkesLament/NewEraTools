-- Production api/Speech.lua. Feature specs keep tests/helpers/fakes/Speech.lua.

describe("Speech", function()
    local savedVoice, savedSettings, savedEnum

    before_each(function()
        savedVoice, savedSettings, savedEnum = C_VoiceChat, C_TTSSettings, Enum
    end)

    after_each(function()
        C_VoiceChat, C_TTSSettings, Enum = savedVoice, savedSettings, savedEnum
    end)

    local function Load()
        local ns = { Api = {} }
        assert(loadfile("api/Speech.lua"))("NewEraTools", ns)
        return ns.Api.Speech
    end

    it("speaks on the player's local text-to-speech voice", function()
        local calls = {}
        C_VoiceChat = {
            SpeakText = function(...)
                calls[#calls + 1] = { ... }
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
        Enum = { VoiceTtsDestination = { LocalPlayback = 1 } }

        Load().Say("准备打断")
        assert.same({ { 7, "准备打断", 1, 2, 80 } }, calls)
    end)

    it("does nothing when the client has no text-to-speech API", function()
        C_VoiceChat = nil
        C_TTSSettings = nil
        Enum = nil
        Load().Say("准备打断")
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
