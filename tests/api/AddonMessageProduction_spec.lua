-- Production api/AddonMessage.lua. Feature specs keep tests/helpers/fakes/AddonMessage.lua.
-- C_ChatInfo and Enum are stand-ins for the client. GameEvents and Unit are the shared fakes.

local function LoadProduction()
    local ns = { Api = {} }
    ns.Api.GameEvents = dofile("tests/helpers/fakes/GameEvents.lua")()
    ns.Api.Unit = dofile("tests/helpers/fakes/Unit.lua")()
    assert(loadfile("api/AddonMessage.lua"))("NewEraTools", ns)
    return ns
end

describe("AddonMessage production", function()
    local ns, AddonMessage, GameEvents, Unit, chat
    local savedChatInfo, savedEnum

    local function InstallClient()
        chat = {
            registerResult = true,
            sendResult = true,
            registered = {},
            sent = {},
        }
        C_ChatInfo = {
            RegisterAddonMessagePrefix = function(prefix)
                table.insert(chat.registered, prefix)
                local result = chat.registerResult
                if type(result) == "function" then
                    return result(prefix)
                end
                return result
            end,
            SendAddonMessage = function(prefix, message, chatType, target)
                table.insert(chat.sent, {
                    prefix = prefix,
                    message = message,
                    chatType = chatType,
                    target = target,
                })
                local result = chat.sendResult
                if type(result) == "function" then
                    return result()
                end
                return result
            end,
        }
        Enum = {
            SendAddonMessageResult = {
                Success = 0,
                AddonMessageThrottle = 3,
                AddOnMessageLockdown = 4,
            },
        }
    end

    before_each(function()
        savedChatInfo = C_ChatInfo
        savedEnum = Enum
        InstallClient()
        ns = LoadProduction()
        AddonMessage = ns.Api.AddonMessage
        GameEvents = ns.Api.GameEvents
        Unit = ns.Api.Unit
        Unit.realm = "ProbeRealm"
    end)

    after_each(function()
        C_ChatInfo = savedChatInfo
        Enum = savedEnum
    end)

    it("normalizes senders from CHAT_MSG_ADDON and subscribes once", function()
        local got = {}
        local function Record(prefix)
            return function(message, channel, sender)
                table.insert(got, {
                    prefix = prefix,
                    message = message,
                    channel = channel,
                    sender = sender,
                })
            end
        end

        assert.is_true(AddonMessage.Listen("Alpha", Record("Alpha")))
        assert.is_true(AddonMessage.Listen("Beta", Record("Beta")))
        assert.equals(1, #GameEvents.handlers.CHAT_MSG_ADDON)

        GameEvents.Fire("CHAT_MSG_ADDON", "Alpha", "hello", "RAID", "Bob")
        GameEvents.Fire("CHAT_MSG_ADDON", "Alpha", "hello", "WHISPER", "Bob-Other")
        GameEvents.Fire("CHAT_MSG_ADDON", "Beta", "x", "RAID", "Ann")
        GameEvents.Fire("CHAT_MSG_ADDON", "Other", "nope", "RAID", "Zoe")

        assert.same({
            { prefix = "Alpha", message = "hello", channel = "RAID", sender = "Bob-ProbeRealm" },
            { prefix = "Alpha", message = "hello", channel = "WHISPER", sender = "Bob-Other" },
            { prefix = "Beta", message = "x", channel = "RAID", sender = "Ann-ProbeRealm" },
        }, got)
    end)

    it("treats false prefix registration as failure and nil as success", function()
        chat.registerResult = false
        local ok, reason = AddonMessage.Listen("P", function() end)
        assert.is_false(ok)
        assert.equals("RegisterFailed", reason)
        assert.is_nil(GameEvents.handlers.CHAT_MSG_ADDON)

        chat.registerResult = nil
        ok, reason = AddonMessage.Listen("P", function() end)
        assert.is_true(ok)
        assert.is_nil(reason)
        assert.equals(1, #GameEvents.handlers.CHAT_MSG_ADDON)

        chat.registerResult = true
        assert.is_true(AddonMessage.Listen("Q", function() end))
        assert.equals(1, #GameEvents.handlers.CHAT_MSG_ADDON)
        -- A false result is still a client call. The callback is what must stay unbound.
        assert.same({ "P", "P", "Q" }, chat.registered)
    end)

    it("classifies boolean, enum, and unknown SendAddonMessage results", function()
        local function Send(result)
            chat.sendResult = result
            return AddonMessage.Send("NET_RT", "hi", "RAID")
        end

        local ok, reason = Send(true)
        assert.is_true(ok)
        assert.is_nil(reason)

        ok, reason = Send(false)
        assert.is_false(ok)
        assert.equals("rejected", reason)

        ok, reason = Send(Enum.SendAddonMessageResult.Success)
        assert.is_true(ok)
        assert.is_nil(reason)

        ok, reason = Send(Enum.SendAddonMessageResult.AddonMessageThrottle)
        assert.is_false(ok)
        assert.equals("AddonMessageThrottle", reason)

        ok, reason = Send(Enum.SendAddonMessageResult.AddOnMessageLockdown)
        assert.is_false(ok)
        assert.equals("AddOnMessageLockdown", reason)

        ok, reason = Send(99)
        assert.is_false(ok)
        assert.equals("GeneralError", reason)

        ok, reason = Send(nil)
        assert.is_false(ok)
        assert.equals("GeneralError", reason)

        chat.sendResult = function()
            return "legacy", Enum.SendAddonMessageResult.Success
        end
        ok, reason = AddonMessage.Send("NET_RT", "hi", "RAID")
        assert.is_true(ok)
        assert.is_nil(reason)
    end)

    it("accepts a 16-character prefix and a 255-byte body", function()
        local prefix16 = string.rep("p", 16)
        local body255 = string.rep("x", 255)

        local ok, reason = AddonMessage.Send(prefix16, "x", "RAID", "someone")
        assert.is_true(ok)
        assert.is_nil(reason)
        assert.equals(prefix16, chat.sent[1].prefix)
        assert.equals("someone", chat.sent[1].target)

        ok, reason = AddonMessage.Send(string.rep("p", 17), "x", "RAID")
        assert.is_false(ok)
        assert.equals("InvalidPrefix", reason)

        ok, reason = AddonMessage.Send("", "x", "RAID")
        assert.is_false(ok)
        assert.equals("InvalidPrefix", reason)

        ok, reason = AddonMessage.Send("ok", body255, "RAID")
        assert.is_true(ok)
        assert.is_nil(reason)
        assert.equals(body255, chat.sent[2].message)

        ok, reason = AddonMessage.Send("ok", string.rep("x", 256), "RAID")
        assert.is_false(ok)
        assert.equals("InvalidMessage", reason)

        ok, reason = AddonMessage.Send("ok", "a\0b", "RAID")
        assert.is_false(ok)
        assert.equals("InvalidMessage", reason)

        assert.equals(2, #chat.sent)
    end)

    it("Unlisten stops delivery and a later Listen uses the same event", function()
        local got = {}
        local function OnMessage(_, _, sender)
            table.insert(got, sender)
        end

        assert.is_true(AddonMessage.Listen("P", OnMessage))
        GameEvents.Fire("CHAT_MSG_ADDON", "P", "a", "RAID", "Bob")
        AddonMessage.Unlisten("P")
        GameEvents.Fire("CHAT_MSG_ADDON", "P", "b", "RAID", "Bob")
        assert.same({ "Bob-ProbeRealm" }, got)
        assert.equals(1, #GameEvents.handlers.CHAT_MSG_ADDON)

        assert.is_true(AddonMessage.Listen("P", OnMessage))
        assert.equals(1, #GameEvents.handlers.CHAT_MSG_ADDON)
        GameEvents.Fire("CHAT_MSG_ADDON", "P", "c", "RAID", "Cara-Realm")
        assert.same({ "Bob-ProbeRealm", "Cara-Realm" }, got)
    end)

    it("rolls back ListenProtocol when a later prefix is refused", function()
        local calls = 0
        chat.registerResult = function(prefix)
            if prefix == AddonMessage.PREFIX.CONTROL then
                return false
            end
            return nil
        end

        local ok, reason, failedPrefix = AddonMessage.ListenProtocol(function()
            calls = calls + 1
        end)
        assert.is_false(ok)
        assert.equals("RegisterFailed", reason)
        assert.equals(AddonMessage.PREFIX.CONTROL, failedPrefix)
        GameEvents.Fire("CHAT_MSG_ADDON", AddonMessage.PREFIX.REALTIME, "x", "RAID", "Bob")
        assert.equals(0, calls)

        chat.registerResult = true
        assert.is_true(AddonMessage.ListenProtocol(function()
            calls = calls + 1
        end))
        assert.equals(1, #GameEvents.handlers.CHAT_MSG_ADDON)
        GameEvents.Fire("CHAT_MSG_ADDON", AddonMessage.PREFIX.REALTIME, "x", "RAID", "Bob")
        GameEvents.Fire("CHAT_MSG_ADDON", AddonMessage.PREFIX.CONTROL, "y", "RAID", "Ann")
        assert.equals(2, calls)
    end)

    it("keeps listener state inside the load that registered it", function()
        local hits = 0
        assert.is_true(AddonMessage.Listen("P", function()
            hits = hits + 1
        end))

        local other = LoadProduction()
        other.Api.GameEvents.Fire("CHAT_MSG_ADDON", "P", "x", "RAID", "Bob")
        assert.equals(0, hits)

        GameEvents.Fire("CHAT_MSG_ADDON", "P", "x", "RAID", "Bob")
        assert.equals(1, hits)
        assert.is_nil(other.Api.GameEvents.handlers.CHAT_MSG_ADDON)
    end)
end)
