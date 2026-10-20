local _, ns = ...

local Speech = {}
ns.Api.Speech = Speech

-- Enum.VoiceTtsDestination.LocalPlayback. Used when the enum is missing.
local LOCAL_PLAYBACK = 1

---Speaks `text` on the local text-to-speech voice. No-op when the client has no TTS API.
---@param text string
function Speech.Say(text)
    if type(text) ~= "string" or text == "" then
        return
    end
    if not C_VoiceChat or type(C_VoiceChat.SpeakText) ~= "function" then
        return
    end
    local voiceID = 0
    local rate = 0
    local volume = 100
    if C_TTSSettings then
        if type(C_TTSSettings.GetVoiceOptionID) == "function" then
            voiceID = C_TTSSettings.GetVoiceOptionID(0) or 0
        end
        if type(C_TTSSettings.GetSpeechRate) == "function" then
            rate = C_TTSSettings.GetSpeechRate() or 0
        end
        if type(C_TTSSettings.GetSpeechVolume) == "function" then
            volume = C_TTSSettings.GetSpeechVolume() or 100
        end
    end
    local destination = LOCAL_PLAYBACK
    if Enum and Enum.VoiceTtsDestination and Enum.VoiceTtsDestination.LocalPlayback then
        destination = Enum.VoiceTtsDestination.LocalPlayback
    end
    C_VoiceChat.SpeakText(voiceID, text, destination, rate, volume)
end
