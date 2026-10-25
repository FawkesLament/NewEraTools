local Loader = require("helpers.loader")

describe("TwinFangs interrupt macros", function()
    local ns, TwinFangs, Spell, Player, Group, L

    local function Body(spell, whisper)
        local lines = { "#showtooltip", "/cast " .. spell, "/p 已打断" }
        if whisper then
            lines[#lines + 1] = "/w " .. whisper .. " 你是替补"
        end
        return table.concat(lines, "\n")
    end

    local function AssignPrimary(backup)
        local chain = TwinFangs.db.interruptReminder.chain
        chain.front_left.group = 1
        chain.front_left.players = { { name = Player.GetFullName() } }
        chain.front_left.backup = backup and { name = backup } or nil
    end

    local function AssignBackupOnly()
        local chain = TwinFangs.db.interruptReminder.chain
        chain.front_right.group = 2
        chain.front_right.players = { { name = "Other-TestRealm" } }
        chain.front_right.backup = { name = Player.GetFullName() }
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        TwinFangs = ns.Modules.Get("TwinFangs")
        Spell = ns.Api.Spell
        Player = ns.Api.Player
        Group = ns.Api.Group
        L = ns.L
        Spell.SetInterruptNameForTests("反制")
        Group.inRaid = true
    end)

    describe("generation", function()
        it("uses Spell.GetInterruptName and omits backup when none is assigned", function()
            AssignPrimary()
            assert.equals("反制", Spell.GetInterruptName())
            assert.equals(Body("反制"), TwinFangs:GetInterruptMacroBody())
        end)

        it("appends a same-realm whisper using the short cached backup name", function()
            AssignPrimary("夜雨-TestRealm")
            assert.equals(Body("反制", "夜雨"), TwinFangs:GetInterruptMacroBody())
        end)

        it("keeps the realm suffix for a cross-realm backup", function()
            AssignPrimary("ExamplePlayer-OtherRealm")
            assert.equals(Body("反制", "ExamplePlayer-OtherRealm"), TwinFangs:GetInterruptMacroBody())
        end)

        it("uses a placeholder when the interrupt spell is missing", function()
            AssignPrimary()
            Spell.SetInterruptNameForTests(nil)
            assert.equals(Body(L.TWIN_FANGS_INTERRUPT_MACRO_SPELL_PLACEHOLDER), TwinFangs:GetInterruptMacroBody())
        end)

        it("omits the whisper when an assigned backup has no usable name", function()
            AssignPrimary()
            TwinFangs.db.interruptReminder.chain.front_left.backup = { name = "" }
            assert.equals(Body("反制"), TwinFangs:GetInterruptMacroBody())
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
    end)
end)
