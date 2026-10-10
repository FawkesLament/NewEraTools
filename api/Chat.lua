local _, ns = ...

local Chat = {}
ns.Api.Chat = Chat

---Sends `message` to a chat channel. `target` is the player name for "WHISPER" or the channel number for "CHANNEL".
---@type fun(message: string, chatType: ChatType, languageID: number|nil, target: string|number|nil)
Chat.Send = C_ChatInfo.SendChatMessage
