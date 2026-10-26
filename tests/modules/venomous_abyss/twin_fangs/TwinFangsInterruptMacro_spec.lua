local Loader = require("helpers.loader")

describe("TwinFangs interrupt macros", function()
    local ns, TwinFangs, Schema, Spell, Player, Group, L

    local function Body(spell, reportLine)
        return table.concat({ "#showtooltip", "/cast " .. spell, reportLine }, "\n")
    end

    local function AssignPrimary(channel)
        local chain = TwinFangs.db.interruptReminder.chain
        chain.front_left.group = 1
        chain.front_left.players = { { name = Player.GetFullName() } }
        chain.front_left.channel = channel or Schema.CHANNEL_PARTY
        chain.front_left.backup = { name = "夜雨-TestRealm" }
    end

    local function AssignBackupOnly()
        local chain = TwinFangs.db.interruptReminder.chain
        chain.front_right.group = 2
        chain.front_right.players = { { name = "Other-TestRealm" } }
        chain.front_right.backup = { name = Player.GetFullName() }
        chain.front_right.channel = Schema.CHANNEL_YELL
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        TwinFangs = ns.Modules.Get("TwinFangs")
        Schema = ns.Modules.Internals("TwinFangs").Schema
        Spell = ns.Api.Spell
        Player = ns.Api.Player
        Group = ns.Api.Group
        L = ns.L
        Spell.SetInterruptNameForTests("反制")
        Group.inRaid = true
    end)

    describe("generation", function()
        it("uses Spell.GetInterruptName and a party report by default", function()
            AssignPrimary()
            assert.equals("反制", Spell.GetInterruptName())
            assert.equals(Body("反制", "/p 已打断"), TwinFangs:GetInterruptMacroBody())
        end)

        it("does not append a backup whisper", function()
            AssignPrimary(Schema.CHANNEL_SAY)
            local body = TwinFangs:GetInterruptMacroBody()
            assert.equals(Body("反制", "/s 已打断"), body)
            assert.is_nil(body:find("/w ", 1, true))
        end)

        it("uses a placeholder when the interrupt spell is missing", function()
            AssignPrimary()
            Spell.SetInterruptNameForTests(nil)
            assert.equals(
                Body(L.TWIN_FANGS_INTERRUPT_MACRO_SPELL_PLACEHOLDER, "/p 已打断"),
                TwinFangs:GetInterruptMacroBody()
            )
        end)

        it("does not invent a body for an unassigned player", function()
            local body, reason = TwinFangs:GetInterruptMacroBody()
            assert.is_nil(body)
            assert.equals("unassigned", reason)
        end)

        it("does not invent a body when the player is only a backup", function()
            AssignBackupOnly()
            local body, reason = TwinFangs:GetInterruptMacroBody()
            assert.is_nil(body)
            assert.equals("unassigned", reason)
        end)

        it("emits one communication command for each supported channel", function()
            local expected = {
                [Schema.CHANNEL_PARTY] = "/p 已打断",
                [Schema.CHANNEL_SAY] = "/s 已打断",
                [Schema.CHANNEL_YELL] = "/y 已打断",
                [Schema.CHANNEL_EMOTE] = "/e 已打断",
                [Schema.CHANNEL_NOD] = "/nod",
                [Schema.CHANNEL_MARKER] = "/tm [@player] 8",
            }
            for channel, line in pairs(expected) do
                AssignPrimary(channel)
                assert.equals(Body("反制", line), TwinFangs:GetInterruptMacroBody())
            end
        end)

        it("regenerates the body after the primary zone channel changes", function()
            AssignPrimary(Schema.CHANNEL_PARTY)
            assert.equals(Body("反制", "/p 已打断"), TwinFangs:GetInterruptMacroBody())
            TwinFangs.db.interruptReminder.chain.front_left.channel = Schema.CHANNEL_YELL
            assert.equals(Body("反制", "/y 已打断"), TwinFangs:GetInterruptMacroBody())
        end)
    end)
end)
