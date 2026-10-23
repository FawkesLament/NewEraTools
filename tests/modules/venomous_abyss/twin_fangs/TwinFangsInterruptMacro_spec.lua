local Loader = require("helpers.loader")

describe("TwinFangs interrupt macros", function()
    local ns, TwinFangs, Macro, Spell, Combat, Player, Group, Colors, L

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
        Macro = ns.Api.Macro
        Spell = ns.Api.Spell
        Combat = ns.Api.Combat
        Player = ns.Api.Player
        Group = ns.Api.Group
        Colors = ns.Assets.Colors
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

        it("fails when the interrupt spell is missing", function()
            AssignPrimary()
            Spell.SetInterruptNameForTests(nil)
            local body, reason = TwinFangs:GetInterruptMacroBody()
            assert.is_nil(body)
            assert.equals("no_spell", reason)
        end)

        it("fails when an assigned backup has no usable name", function()
            AssignPrimary()
            TwinFangs.db.interruptReminder.chain.front_left.backup = { name = "" }
            local body, reason = TwinFangs:GetInterruptMacroBody()
            assert.is_nil(body)
            assert.equals("no_backup", reason)
        end)

        it("rejects a body that exceeds the macro length limit", function()
            AssignPrimary("Backup-OtherRealm")
            Spell.SetInterruptNameForTests(string.rep("断", 90))
            local body, reason = TwinFangs:GetInterruptMacroBody()
            assert.is_nil(body)
            assert.equals("too_long", reason)
        end)

        it("does not invent a body for an unassigned player", function()
            local body, reason = TwinFangs:GetInterruptMacroBody()
            assert.is_nil(body)
            assert.equals("unassigned", reason)
        end)

        it("stays within the 16-character macro name limit", function()
            assert.equals("NETTwinFangInt", TwinFangs:GetInterruptMacroName())
            assert.is_true(#TwinFangs:GetInterruptMacroName() <= 16)
        end)
    end)

    describe("creation and updates", function()
        it("creates a character-specific macro from the button", function()
            AssignPrimary()
            local ok, reason = TwinFangs:CreateInterruptMacro()
            assert.is_true(ok)
            assert.is_nil(reason)
            assert.equals(1, Macro.createCount)
            local _, characterCount = Macro.GetNum()
            assert.equals(1, characterCount)
            local stored = Macro.Get(TwinFangs:GetInterruptMacroName())
            assert.equals(Body("反制"), stored.body)
            assert.is_true(TwinFangs:HasInterruptMacro())
        end)

        it("does not create a missing macro during automatic maintenance", function()
            AssignPrimary()
            assert.is_false(TwinFangs:MaintainInterruptMacro())
            assert.equals(0, Macro.createCount)
            assert.is_false(TwinFangs:HasInterruptMacro())
        end)

        it("updates an existing macro when the expected body changes", function()
            AssignPrimary()
            TwinFangs:CreateInterruptMacro()
            AssignPrimary("Night-OtherRealm")
            local edits = Macro.editCount
            assert.is_true(TwinFangs:MaintainInterruptMacro())
            assert.equals(edits + 1, Macro.editCount)
            assert.equals(1, Macro.createCount)
            assert.equals(Body("反制", "Night-OtherRealm"), Macro.Get(TwinFangs:GetInterruptMacroName()).body)
        end)

        it("does not edit when the existing body is already correct", function()
            AssignPrimary()
            TwinFangs:CreateInterruptMacro()
            local edits = Macro.editCount
            assert.is_false(TwinFangs:MaintainInterruptMacro())
            assert.equals(edits, Macro.editCount)
        end)

        it("repairs a manually edited macro from the regenerate button", function()
            AssignPrimary()
            TwinFangs:CreateInterruptMacro()
            local index = Macro.GetIndexByName(TwinFangs:GetInterruptMacroName())
            Macro.Edit(index, nil, nil, "/say edited")
            local edits = Macro.editCount
            local ok = TwinFangs:CreateInterruptMacro()
            assert.is_true(ok)
            assert.equals(edits + 1, Macro.editCount)
            assert.equals(1, Macro.createCount)
            assert.equals(Body("反制"), Macro.Get(TwinFangs:GetInterruptMacroName()).body)
        end)

        it("does not recreate a deleted macro automatically", function()
            AssignPrimary()
            TwinFangs:CreateInterruptMacro()
            local index = Macro.GetIndexByName(TwinFangs:GetInterruptMacroName())
            Macro.slots[index] = nil
            TwinFangs:MaintainInterruptMacro()
            assert.equals(1, Macro.createCount)
            assert.is_false(TwinFangs:HasInterruptMacro())
        end)

        it("does not create a second macro when one already exists", function()
            AssignPrimary()
            TwinFangs:CreateInterruptMacro()
            TwinFangs:CreateInterruptMacro()
            assert.equals(1, Macro.createCount)
            local _, characterCount = Macro.GetNum()
            assert.equals(1, characterCount)
        end)

        it("edits the existing character slot in place", function()
            AssignPrimary()
            local index = TwinFangs:CreateInterruptMacro() and Macro.GetIndexByName(TwinFangs:GetInterruptMacroName())
            AssignPrimary("Night-OtherRealm")
            TwinFangs:MaintainInterruptMacro()
            assert.equals(index, Macro.GetIndexByName(TwinFangs:GetInterruptMacroName()))
            assert.equals(Body("反制", "Night-OtherRealm"), Macro.slots[index].body)
        end)

        it("never modifies unrelated macros", function()
            Macro.Create("UserMacro", 1, "/say mine")
            Macro.Create("OtherChar", 1, "/say other", true)
            AssignPrimary()
            TwinFangs:CreateInterruptMacro()
            AssignPrimary("Night-OtherRealm")
            TwinFangs:MaintainInterruptMacro()
            assert.equals("/say mine", Macro.Get("UserMacro").body)
            assert.equals("/say other", Macro.Get("OtherChar").body)
        end)

        it("does not adopt an account-wide macro that only shares the name", function()
            Macro.Create(TwinFangs:GetInterruptMacroName(), 1, "/say account")
            AssignPrimary()
            local ok, reason = TwinFangs:CreateInterruptMacro()
            assert.is_false(ok)
            assert.equals("failed", reason)
            assert.equals("/say account", Macro.Get(TwinFangs:GetInterruptMacroName()).body)
            assert.equals(0, select(2, Macro.GetNum()))
        end)

        it("does not create or update macros for an unassigned player", function()
            local ok, reason = TwinFangs:CreateInterruptMacro()
            assert.is_false(ok)
            assert.equals("unassigned", reason)
            assert.equals(0, Macro.createCount)
        end)

        it("does not create a macro when the player is only a backup", function()
            AssignBackupOnly()
            local ok, reason = TwinFangs:CreateInterruptMacro()
            assert.is_false(ok)
            assert.equals("unassigned", reason)
            TwinFangs:MaintainInterruptMacro()
            assert.equals(0, Macro.createCount)
        end)

        it("leaves an existing macro untouched after the player loses a primary role", function()
            AssignPrimary("Night-OtherRealm")
            TwinFangs:CreateInterruptMacro()
            TwinFangs.db.interruptReminder.chain.front_left.players = {}
            TwinFangs.db.interruptReminder.chain.front_left.backup = nil
            local edits = Macro.editCount
            TwinFangs:MaintainInterruptMacro()
            assert.equals(edits, Macro.editCount)
            assert.equals(Body("反制", "Night-OtherRealm"), Macro.Get(TwinFangs:GetInterruptMacroName()).body)
        end)
    end)

    describe("lifecycle", function()
        it("maintains the macro after an accepted team publication", function()
            Player.fullName = "LF1-TestRealm"
            AssignPrimary()
            TwinFangs:CreateInterruptMacro()
            Group.raidChatType = "RAID"
            Group.raidLeaderFullName = "Leader-TestRealm"
            Group.members = {
                {
                    name = "LF1",
                    fullName = "LF1-TestRealm",
                    guid = "LF1",
                    index = 1,
                    subgroup = 1,
                    classFile = "MAGE",
                    role = "DAMAGER",
                },
                {
                    name = "B52",
                    fullName = "B52-TestRealm",
                    guid = "B52",
                    index = 2,
                    subgroup = 5,
                    classFile = "MAGE",
                    role = "DAMAGER",
                },
            }
            ns.Modules.Internals("TwinFangs").InterruptChain.Listen()
            local payload = "1|1:1:51|::|::|::"
            local wire = assert(
                ns.MessageProtocol.Encode(
                    ns.MessageProtocol.TYPE_EVENT,
                    ns.Modules.Internals("TwinFangs").InterruptChain.SYNC_TOPIC,
                    "-",
                    payload
                )
            )
            ns.Util.Print = function() end
            ns.Api.MessageProtocolComm.Enable()
            ns.Api.AddonMessage.Deliver(ns.Api.MessageProtocolComm.PREFIX.CONTROL, wire, "RAID", "Leader-TestRealm")
            assert.equals(Body("反制", "B52"), Macro.Get(TwinFangs:GetInterruptMacroName()).body)
        end)

        it("maintains the macro after a local raid-leader assignment edit", function()
            AssignPrimary()
            TwinFangs:CreateInterruptMacro()
            AssignPrimary("Night-OtherRealm")
            TwinFangs:MaintainInterruptMacro()
            assert.equals(Body("反制", "Night-OtherRealm"), Macro.Get(TwinFangs:GetInterruptMacroName()).body)
        end)

        it("checks an existing macro on login without creating a missing one", function()
            AssignPrimary()
            TwinFangs:ListenForInterruptMacro()
            assert.equals(0, Macro.createCount)
            TwinFangs:CreateInterruptMacro()
            Spell.SetInterruptNameForTests("法术反制")
            local edits = Macro.editCount
            TwinFangs:ListenForInterruptMacro()
            assert.equals(edits + 1, Macro.editCount)
            assert.equals(1, Macro.createCount)
            assert.equals(Body("法术反制"), Macro.Get(TwinFangs:GetInterruptMacroName()).body)
        end)

        it("maintains the macro when the interrupt spell changes with spec", function()
            AssignPrimary()
            TwinFangs:CreateInterruptMacro()
            TwinFangs:ListenForInterruptMacro()
            Spell.SetInterruptNameForTests("迎头痛击")
            Player.FireChanged()
            assert.equals(Body("迎头痛击"), Macro.Get(TwinFangs:GetInterruptMacroName()).body)
        end)

        it("defers combat-time updates and applies the latest body after combat", function()
            AssignPrimary()
            TwinFangs:CreateInterruptMacro()
            Combat.FireEnter()
            AssignPrimary("First-OtherRealm")
            TwinFangs:MaintainInterruptMacro()
            AssignPrimary("Second-OtherRealm")
            TwinFangs:MaintainInterruptMacro()
            assert.equals(Body("反制"), Macro.Get(TwinFangs:GetInterruptMacroName()).body)
            assert.equals(1, #Combat.leaveCallbacks)
            Combat.FireLeave()
            assert.equals(Body("反制", "Second-OtherRealm"), Macro.Get(TwinFangs:GetInterruptMacroName()).body)
            assert.equals(0, #Combat.leaveCallbacks)
        end)

        it("does not create a missing macro after a combat-time assignment change", function()
            AssignPrimary()
            Combat.FireEnter()
            TwinFangs:MaintainInterruptMacro()
            Combat.FireLeave()
            assert.equals(0, Macro.createCount)
        end)

        it("warns instead of writing when the player clicks during combat", function()
            AssignPrimary()
            Combat.FireEnter()
            local ok, reason = TwinFangs:CreateInterruptMacro()
            assert.is_false(ok)
            assert.equals("combat", reason)
            assert.equals(0, Macro.createCount)
            local status = TwinFangs:GetInterruptMacroStatus()
            assert.equals(L.TWIN_FANGS_INTERRUPT_MACRO_IN_COMBAT, status.message)
            assert.equals(Colors.WARNING, status.color)
        end)
    end)

    describe("status", function()
        local function Status()
            return TwinFangs:GetInterruptMacroStatus()
        end

        it("hides the action when the player is not in a raid", function()
            AssignPrimary()
            Group.inRaid = false
            local status = Status()
            assert.is_false(status.shown)
            assert.equals("not_in_raid", status.reason)
        end)

        it("hides the action when the player has no primary assignment", function()
            local status = Status()
            assert.is_false(status.shown)
            assert.equals("unassigned", status.reason)
        end)

        it("shows create + warning when the macro is missing", function()
            AssignPrimary()
            local status = Status()
            assert.is_true(status.shown)
            assert.equals(L.TWIN_FANGS_INTERRUPT_MACRO_CREATE, status.buttonText)
            assert.equals(L.TWIN_FANGS_INTERRUPT_MACRO_NEEDED, status.message)
            assert.equals(Colors.WARNING, status.color)
        end)

        it("shows regenerate + success when the existing macro matches", function()
            AssignPrimary()
            TwinFangs:CreateInterruptMacro()
            local status = Status()
            assert.equals(L.TWIN_FANGS_INTERRUPT_MACRO_REGENERATE, status.buttonText)
            assert.equals(L.TWIN_FANGS_INTERRUPT_MACRO_READY, status.message)
            assert.equals(Colors.SUCCESS, status.color)
        end)

        it("reports character-slot exhaustion", function()
            AssignPrimary()
            Macro.FillCharacterSlotsForTests()
            local status = Status()
            assert.equals(L.TWIN_FANGS_INTERRUPT_MACRO_NO_SLOTS, status.message)
            assert.equals(Colors.ERROR, status.color)
            local ok, reason = TwinFangs:CreateInterruptMacro()
            assert.is_false(ok)
            assert.equals("no_slots", reason)
            assert.equals(L.TWIN_FANGS_INTERRUPT_MACRO_NO_SLOTS, Status().message)
        end)

        it("reports a missing interrupt spell", function()
            AssignPrimary()
            Spell.SetInterruptNameForTests(nil)
            local status = Status()
            assert.equals(L.TWIN_FANGS_INTERRUPT_MACRO_NO_SPELL, status.message)
            assert.equals(Colors.ERROR, status.color)
        end)

        it("reports a missing backup name", function()
            AssignPrimary()
            TwinFangs.db.interruptReminder.chain.front_left.backup = { name = "" }
            local status = Status()
            assert.equals(L.TWIN_FANGS_INTERRUPT_MACRO_NO_BACKUP, status.message)
            assert.equals(Colors.ERROR, status.color)
        end)

        it("reports a deferred combat update", function()
            AssignPrimary()
            TwinFangs:CreateInterruptMacro()
            Combat.FireEnter()
            AssignPrimary("Night-OtherRealm")
            TwinFangs:MaintainInterruptMacro()
            local status = Status()
            assert.equals(L.TWIN_FANGS_INTERRUPT_MACRO_PENDING, status.message)
            assert.equals(Colors.WARNING, status.color)
        end)

        it("reports a write failure", function()
            AssignPrimary()
            Macro.failNextCreate = true
            local ok, reason = TwinFangs:CreateInterruptMacro()
            assert.is_false(ok)
            assert.equals("failed", reason)
            local status = Status()
            assert.equals(L.TWIN_FANGS_INTERRUPT_MACRO_FAILED, status.message)
            assert.equals(Colors.ERROR, status.color)
        end)

        it("refreshes status after create, update, and failure", function()
            local seen = {}
            TwinFangs.OnInterruptMacroChanged = function()
                seen[#seen + 1] = TwinFangs:GetInterruptMacroStatus().reason
            end
            AssignPrimary()
            TwinFangs:CreateInterruptMacro()
            assert.equals("ready", seen[#seen])
            AssignPrimary("Night-OtherRealm")
            TwinFangs:MaintainInterruptMacro()
            assert.equals("ready", seen[#seen])
            Spell.SetInterruptNameForTests(nil)
            TwinFangs:CreateInterruptMacro()
            assert.equals("no_spell", seen[#seen])
        end)

        it("refreshes status when the game reports a macro change", function()
            AssignPrimary()
            TwinFangs:CreateInterruptMacro()
            TwinFangs:ListenForInterruptMacro()
            local seen = {}
            TwinFangs.OnInterruptMacroChanged = function()
                seen[#seen + 1] = TwinFangs:GetInterruptMacroStatus()
            end
            local index = Macro.GetIndexByName(TwinFangs:GetInterruptMacroName())
            Macro.slots[index] = nil
            Macro.FireChanged()
            assert.equals(1, Macro.createCount)
            assert.equals("needed", seen[#seen].reason)
            assert.equals(L.TWIN_FANGS_INTERRUPT_MACRO_NEEDED, seen[#seen].message)
            assert.equals(Colors.WARNING, seen[#seen].color)
            assert.equals(L.TWIN_FANGS_INTERRUPT_MACRO_CREATE, seen[#seen].buttonText)
        end)
    end)
end)
