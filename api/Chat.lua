local _, ns = ...

local Chat = {}
ns.Api.Chat = Chat

---Sends `message` to a chat channel. `target` is the player name for "WHISPER" or the channel number for "CHANNEL".
---@type fun(message: string, chatType: ChatType, languageID: number|nil, target: string|number|nil)
Chat.Send = C_ChatInfo.SendChatMessage

---Turns chat icon tags (`{rt1}`, `{star}`, …) into FontString texture escapes. Accepts secret values.
---@type fun(input: string, noIconReplacement: boolean|nil, noGroupReplacement: boolean|nil): string
Chat.ReplaceIconAndGroupExpressions = C_ChatInfo.ReplaceIconAndGroupExpressions

---Calls `callback` with the raid leader message text (may be a secret value during encounters).
---@param callback fun(message: string)
---@return fun()  Unsubscribe.
function Chat.OnRaidLeaderMessage(callback)
    return ns.Api.GameEvents.Listen("CHAT_MSG_RAID_LEADER", function(message)
        callback(message)
    end)
end

---Calls `callback` with the raid warning message text (may be a secret value during encounters).
---@param callback fun(message: string)
---@return fun()  Unsubscribe.
function Chat.OnRaidWarningMessage(callback)
    return ns.Api.GameEvents.Listen("CHAT_MSG_RAID_WARNING", function(message)
        callback(message)
    end)
end
