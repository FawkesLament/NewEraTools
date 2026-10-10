local _, ns = ...
local Unit = ns.Api.Unit

local AddonMessage = {}
ns.Api.AddonMessage = AddonMessage

-- Older clients return a boolean; newer ones return an Enum.SendAddonMessageResult code.
local SEND_SUCCESS = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success

local callbacks = {}
local listening = false

local function OnAddonMessage(prefix, message, channel, sender)
    local callback = callbacks[prefix]
    if callback then
        callback(message, channel, Unit.GetFullName(sender))
    end
end

---Sends a hidden message that only addons listening for `prefix` receive.
---@param prefix string  At most 16 characters.
---@param message string  At most 255 characters.
---@param chatType ChatType  e.g. "RAID".
---@return boolean  Whether the game accepted it; it refuses when throttled or when addon messages are restricted.
function AddonMessage.Send(prefix, message, chatType)
    local result = C_ChatInfo.SendAddonMessage(prefix, message, chatType)
    return result == true or (SEND_SUCCESS ~= nil and result == SEND_SUCCESS)
end

---Calls `callback` for every addon message sent with `prefix`, including the player's own.
---@param prefix string  At most 16 characters; one listener per prefix.
---@param callback fun(message: string, channel: ChatType, sender: string)  `sender` is "Name-Realm".
function AddonMessage.Listen(prefix, callback)
    assert(not callbacks[prefix], "Already listening for addon prefix: " .. prefix)
    callbacks[prefix] = callback
    C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    if not listening then
        listening = true
        ns.Api.GameEvents.Listen("CHAT_MSG_ADDON", OnAddonMessage)
    end
end
