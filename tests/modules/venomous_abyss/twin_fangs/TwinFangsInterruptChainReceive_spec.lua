local Loader = require("helpers.loader")

describe("TwinFangs interrupt chain receive", function()
    local ns, Chain, Group, AddonMessage, MessageProtocol, MessageProtocolComm, printed
    local LEADER = "Leader-TestRealm"
    local EXAMPLE = "1|1:15324:52:s|2:31425::p|3:12345:61:y|4:25134::p"
    local LEGACY_EXAMPLE = "1|1:15324:52|2:31425:|3:12345:61|4:25134:"

    local function Member(guid, subgroup, index)
        return {
            name = guid,
            fullName = guid .. "-TestRealm",
            guid = guid,
            index = index,
            subgroup = subgroup,
            classFile = "MAGE",
            role = "DAMAGER",
        }
    end

    local function ExampleRoster()
        return {
            Member("LF1", 1, 1),
            Member("LF2", 1, 2),
            Member("LF3", 1, 3),
            Member("LF4", 1, 4),
            Member("LF5", 1, 5),
            Member("RF1", 2, 6),
            Member("RF2", 2, 7),
            Member("RF3", 2, 8),
            Member("RF4", 2, 9),
            Member("RF5", 2, 10),
            Member("LB1", 3, 11),
            Member("LB2", 3, 12),
            Member("LB3", 3, 13),
            Member("LB4", 3, 14),
            Member("LB5", 3, 15),
            Member("RB1", 4, 16),
            Member("RB2", 4, 17),
            Member("RB3", 4, 18),
            Member("RB4", 4, 19),
            Member("RB5", 4, 20),
            Member("B61", 6, 21),
            Member("B51", 5, 22),
            Member("B52", 5, 23),
        }
    end

    local function Snapshot(chain)
        local copy = {}
        for _, regionId in ipairs(Chain.REGION_IDS) do
            copy[regionId] = Chain.GetRegion({ regions = chain, roster = {} }, regionId)
        end
        return copy
    end

    local function StartModule()
        ns.Modules.Start(ns.Database.Load(nil))
        return ns.Modules.Get("TwinFangs")
    end

    local function Deliver(payload, opts)
        opts = opts or {}
        local messageType = opts.type or MessageProtocol.TYPE_EVENT
        local wire = assert(MessageProtocol.Encode(messageType, Chain.SYNC_TOPIC, opts.correlationId or "-", payload))
        AddonMessage.Deliver(MessageProtocolComm.PREFIX.CONTROL, wire, opts.channel or "RAID", opts.sender or LEADER)
    end

    before_each(function()
        ns = Loader.Load()
        Chain = ns.Modules.Internals("TwinFangs").InterruptChain
        Group = ns.Api.Group
        AddonMessage = ns.Api.AddonMessage
        MessageProtocol = ns.MessageProtocol
        MessageProtocolComm = ns.Api.MessageProtocolComm
        printed = {}
        ns.Util.Print = function(message)
            printed[#printed + 1] = message
        end
        Group.raidChatType = "RAID"
        Group.raidLeaderFullName = LEADER
        Group.members = ExampleRoster()
        MessageProtocolComm.Enable()
    end)

    describe("decoding", function()
        it("resolves subgroup slots in interrupt order, including backups and empty fields", function()
            local regions = assert(Chain.DecodePublication(EXAMPLE, ExampleRoster()))
            assert.equals(1, regions.front_left.group)
            assert.same({
                "LF1-TestRealm",
                "LF5-TestRealm",
                "LF3-TestRealm",
                "LF2-TestRealm",
                "LF4-TestRealm",
            }, {
                regions.front_left.players[1].name,
                regions.front_left.players[2].name,
                regions.front_left.players[3].name,
                regions.front_left.players[4].name,
                regions.front_left.players[5].name,
            })
            assert.equals("B52-TestRealm", regions.front_left.backup.name)
            assert.equals("say", regions.front_left.channel)
            assert.equals("party", regions.front_right.channel)
            assert.is_nil(regions.front_left.players[2].guid)
            assert.is_nil(regions.front_right.backup)
            assert.equals("B61-TestRealm", regions.back_left.backup.name)
            assert.equals("yell", regions.back_left.channel)
            assert.same({
                "RB2-TestRealm",
                "RB5-TestRealm",
                "RB1-TestRealm",
                "RB3-TestRealm",
                "RB4-TestRealm",
            }, {
                regions.back_right.players[1].name,
                regions.back_right.players[2].name,
                regions.back_right.players[3].name,
                regions.back_right.players[4].name,
                regions.back_right.players[5].name,
            })
        end)

        it("decodes consecutive repeated subgroup positions into expanded names", function()
            local payload = "1|1:12223:52:s|2:31425::p|3:12345:61:y|4:25134::p"
            local regions = assert(Chain.DecodePublication(payload, ExampleRoster()))
            assert.same({
                "LF1-TestRealm",
                "LF2-TestRealm",
                "LF2-TestRealm",
                "LF2-TestRealm",
                "LF3-TestRealm",
            }, {
                regions.front_left.players[1].name,
                regions.front_left.players[2].name,
                regions.front_left.players[3].name,
                regions.front_left.players[4].name,
                regions.front_left.players[5].name,
            })
            assert.equals(5, #regions.front_left.players)
            local resolved = assert(Chain.ResolvePublication(payload, ExampleRoster()))
            assert.equals(3, #Chain.Blocks(resolved.front_left.players))
            assert.equals(3, Chain.Blocks(resolved.front_left.players)[2].count)
        end)

        it("rejects four consecutive repeats and nonconsecutive position repeats", function()
            assert.is_nil(Chain.DecodePublication("1|1:1111:|::|::|::", ExampleRoster()))
            assert.equals("invalid_position", select(2, Chain.DecodePublication("1|1:1111:|::|::|::", ExampleRoster())))
            assert.is_nil(Chain.DecodePublication("1|1:121:|::|::|::", ExampleRoster()))
            assert.equals("duplicate_position", select(2, Chain.DecodePublication("1|1:121:|::|::|::", ExampleRoster())))
        end)

        it("decodes a maximum-length 15-turn region", function()
            local payload = "1|1:111222333444555::p|:::p|:::p|:::p"
            local regions = assert(Chain.DecodePublication(payload, ExampleRoster()))
            assert.equals(15, #regions.front_left.players)
            assert.equals("LF1-TestRealm", regions.front_left.players[3].name)
            assert.equals("LF5-TestRealm", regions.front_left.players[15].name)
        end)

        it("supports empty chains and missing backups", function()
            local regions = assert(Chain.DecodePublication("1|::|::|4::|::", { Member("solo", 4, 1) }))
            assert.is_nil(regions.front_left.group)
            assert.equals(0, #regions.front_left.players)
            assert.is_nil(regions.front_left.backup)
            assert.equals(4, regions.back_left.group)
            assert.equals(0, #regions.back_left.players)
        end)

        it("rejects malformed payloads and unsupported versions", function()
            assert.is_nil(Chain.DecodePublication("garbage", ExampleRoster()))
            assert.is_nil(select(1, Chain.DecodePublication("2|::|::|::|::", ExampleRoster())))
            assert.equals("unsupported_version", select(2, Chain.DecodePublication("2|::|::|::|::", ExampleRoster())))
            assert.is_nil(Chain.DecodePublication("1|::|::|::", ExampleRoster()))
            assert.is_nil(Chain.DecodePublication("1|1:6:|::|::|::", ExampleRoster()))
            assert.is_nil(Chain.DecodePublication("1|1:121:|::|::|::", ExampleRoster()))
        end)

        it("rejects a missing or unused subgroup position", function()
            local roster = { Member("A", 3, 1), Member("B", 3, 2) }
            local regions, reason, detail = Chain.DecodePublication("1|::|::|3:4:|::", roster)
            assert.is_nil(regions)
            assert.equals("player_missing", reason)
            assert.equals(3, detail.group)
            assert.equals(4, detail.position)
        end)

        it("rejects same-group and shared backups after resolution", function()
            assert.is_nil(Chain.ResolvePublication("1|1:1:12|::|::|::", ExampleRoster()))
            assert.is_nil(Chain.ResolvePublication("1|1:1:51|2:1:51|::|::", ExampleRoster()))
        end)

        it("decodes a legacy party-plus-backup payload and rejects it on resolve", function()
            local regions = assert(Chain.DecodePublication(LEGACY_EXAMPLE, ExampleRoster()))
            assert.equals("party", regions.front_left.channel)
            assert.equals("B52-TestRealm", regions.front_left.backup.name)
            assert.equals("party", regions.back_left.channel)
            assert.equals("B61-TestRealm", regions.back_left.backup.name)
            local resolved, reason = Chain.ResolvePublication(LEGACY_EXAMPLE, ExampleRoster())
            assert.is_nil(resolved)
            assert.equals("backup_channel", reason)
        end)

        it("decodes every channel code and defaults a missing code to party", function()
            local Schema = ns.Modules.Internals("TwinFangs").Schema
            local payload = "1|1:15324:52:s|2:31425::y|3:12345:61:e|4:25134::n"
            local regions = assert(Chain.DecodePublication(payload, ExampleRoster()))
            assert.equals(Schema.CHANNEL_SAY, regions.front_left.channel)
            assert.equals(Schema.CHANNEL_YELL, regions.front_right.channel)
            assert.equals(Schema.CHANNEL_EMOTE, regions.back_left.channel)
            assert.equals(Schema.CHANNEL_NOD, regions.back_right.channel)
            regions = assert(Chain.DecodePublication("1|1:1::m|::|::|::", ExampleRoster()))
            assert.equals(Schema.CHANNEL_MARKER, regions.front_left.channel)
            assert.equals(Schema.CHANNEL_PARTY, regions.front_right.channel)
            regions = assert(Chain.DecodePublication("1|1:1::r|::|::|::", ExampleRoster()))
            assert.equals(Schema.CHANNEL_RAID, regions.front_left.channel)
            regions = assert(Chain.DecodePublication("1|:::p|:::p|4:::p|:::p", { Member("solo", 4, 1) }))
            assert.equals(Schema.CHANNEL_PARTY, regions.back_left.channel)
        end)

        it("rejects an unknown channel code and exclusive-channel conflicts", function()
            assert.is_nil(Chain.DecodePublication("1|1:1::x|::|::|::", ExampleRoster()))
            assert.equals("invalid_channel", select(2, Chain.DecodePublication("1|1:1::x|::|::|::", ExampleRoster())))
            assert.is_nil(Chain.ResolvePublication("1|1:1::n|2:1::n|::|::", ExampleRoster()))
            assert.equals("channel_conflict", select(2, Chain.ResolvePublication("1|1:1::n|2:1::n|::|::", ExampleRoster())))
            assert.equals("channel_conflict", select(2, Chain.ResolvePublication("1|1:1::r|2:1::r|::|::", ExampleRoster())))
        end)
    end)

    describe("reception", function()
        local module

        before_each(function()
            module = StartModule()
            Chain.Listen()
        end)

        it("accepts an authorized raid-leader event and replaces all four regions", function()
            module.db.interruptReminder.chain.front_left.group = 8
            module.db.interruptReminder.chain.front_left.players = { { guid = "OLD", name = "Old-TestRealm" } }
            local refreshed = 0
            module.OnInterruptChainChanged = function()
                refreshed = refreshed + 1
            end
            Deliver(EXAMPLE)
            local chain = module.db.interruptReminder.chain
            assert.equals(1, chain.front_left.group)
            assert.equals("LF1-TestRealm", chain.front_left.players[1].name)
            assert.equals("LF5-TestRealm", chain.front_left.players[2].name)
            assert.equals("B52-TestRealm", chain.front_left.backup.name)
            assert.equals(2, chain.front_right.group)
            assert.is_nil(chain.front_right.backup)
            assert.equals("LB1-TestRealm", chain.back_left.players[1].name)
            assert.equals("RB2-TestRealm", chain.back_right.players[1].name)
            assert.equals(1, refreshed)
            assert.equals(string.format(ns.L.TWIN_FANGS_INTERRUPT_SYNC_RECEIVED, ns.L.TWIN_FANGS_TITLE), printed[1])
            assert.equals(1, #printed)
            assert.equals(0, #AddonMessage.sent)
        end)

        it("ignores unauthorized senders, own echoes, other types, and other channels", function()
            local before = Snapshot(module.db.interruptReminder.chain)
            Deliver(EXAMPLE, { sender = "Stranger-TestRealm" })
            Deliver(EXAMPLE, { sender = ns.Api.Player.GetFullName() })
            Group.raidLeaderFullName = ns.Api.Player.GetFullName()
            Deliver(EXAMPLE, { sender = ns.Api.Player.GetFullName() })
            Group.raidLeaderFullName = LEADER
            Deliver(EXAMPLE, { type = MessageProtocol.TYPE_REQUEST, correlationId = "c1" })
            Deliver(EXAMPLE, { channel = "PARTY" })
            assert.same(before, Snapshot(module.db.interruptReminder.chain))
            assert.equals(0, #printed)
            assert.equals(0, #AddonMessage.sent)
        end)

        it("does not register the handler twice", function()
            Chain.Listen()
            Chain.Listen()
            Deliver(EXAMPLE)
            assert.equals(1, #printed)
        end)

        it("replaces the chain with consecutive repeats and keeps the prior chain on invalid repeats", function()
            Deliver("1|1:12223:52:s|2:31425::p|3:12345:61:y|4:25134::p")
            local chain = module.db.interruptReminder.chain
            assert.equals("LF2-TestRealm", chain.front_left.players[2].name)
            assert.equals("LF2-TestRealm", chain.front_left.players[4].name)
            assert.equals(5, #chain.front_left.players)
            local before = Snapshot(chain)
            printed = {}
            Deliver("1|1:121:52:s|2:31425::p|3:12345:61:y|4:25134::p")
            assert.same(before, Snapshot(module.db.interruptReminder.chain))
            assert.equals(1, #printed)
            Deliver("1|1:1111:52:s|2:31425::p|3:12345:61:y|4:25134::p")
            assert.same(before, Snapshot(module.db.interruptReminder.chain))
            assert.equals(2, #printed)
        end)

        it("leaves previous assignments unchanged when decoding or validation fails", function()
            Deliver(EXAMPLE)
            local before = Snapshot(module.db.interruptReminder.chain)
            printed = {}
            Deliver("garbage")
            Deliver("2|::|::|::|::")
            Deliver("1|::|::|8:1:|::")
            assert.same(before, Snapshot(module.db.interruptReminder.chain))
            assert.equals(3, #printed)
            assert.equals(
                string.format(
                    ns.L.TWIN_FANGS_INTERRUPT_SYNC_RECEIVE_FAILED,
                    ns.L.TWIN_FANGS_TITLE,
                    string.format(ns.L.TWIN_FANGS_INTERRUPT_SYNC_RECEIVE_MISSING, 8, 1)
                ),
                printed[3]
            )
        end)

        it("keeps synchronized assignments after the live roster changes", function()
            Deliver(EXAMPLE)
            Group.members = { Member("unrelated", 8, 1) }
            local chain = module.db.interruptReminder.chain
            assert.equals("LF1-TestRealm", chain.front_left.players[1].name)
            local view = Chain.GetMemberView(chain, "LF5")
            assert.equals(Chain.FRONT_LEFT, view.primary.regionId)
            assert.equals("LF5-TestRealm", view.primary.players[2].name)
        end)

        it("exposes the same persisted chain to member and editor reads", function()
            Deliver(EXAMPLE)
            local chain = module.db.interruptReminder.chain
            local view = Chain.GetMemberView(chain, "B52")
            assert.is_nil(view.primary)
            assert.equals(Chain.FRONT_LEFT, view.backups[1].regionId)
            local state = Chain.NewState(chain)
            assert.equals("LF1-TestRealm", state.regions.front_left.players[1].name)
            assert.equals(state.regions, chain)
        end)

        it("applies a channeled snapshot atomically and leaves state unchanged on conflict", function()
            local Schema = ns.Modules.Internals("TwinFangs").Schema
            Deliver("1|1:15324:52:s|2:31425::y|3:12345:61:e|4:25134::n")
            local chain = module.db.interruptReminder.chain
            assert.equals(Schema.CHANNEL_SAY, chain.front_left.channel)
            assert.equals(Schema.CHANNEL_YELL, chain.front_right.channel)
            assert.equals(Schema.CHANNEL_EMOTE, chain.back_left.channel)
            assert.equals(Schema.CHANNEL_NOD, chain.back_right.channel)
            local before = Snapshot(chain)
            printed = {}
            Deliver("1|1:15324:52:n|2:31425::n|3:12345:61:p|4:25134::p")
            assert.same(before, Snapshot(module.db.interruptReminder.chain))
            assert.equals(1, #printed)
            Deliver("1|1:15324:52:z|2:31425::p|3:12345:61:p|4:25134::p")
            assert.same(before, Snapshot(module.db.interruptReminder.chain))
            assert.equals(2, #printed)
            Deliver(LEGACY_EXAMPLE)
            assert.same(before, Snapshot(module.db.interruptReminder.chain))
            assert.equals(3, #printed)
        end)

        it("survives a simulated reload", function()
            Deliver(EXAMPLE)
            local savedChain = Snapshot(module.db.interruptReminder.chain)
            local reloaded = Loader.Load()
            reloaded.Modules.Start(reloaded.Database.Load({
                modules = {
                    TwinFangs = {
                        interruptReminder = {
                            chain = savedChain,
                        },
                    },
                },
            }))
            local loaded = reloaded.Modules.Get("TwinFangs").db.interruptReminder.chain
            assert.equals("LF5-TestRealm", loaded.front_left.players[2].name)
            assert.equals("B52-TestRealm", loaded.front_left.backup.name)
            assert.equals("say", loaded.front_left.channel)
            local ReloadedChain = reloaded.Modules.Internals("TwinFangs").InterruptChain
            assert.equals(ReloadedChain.FRONT_LEFT, ReloadedChain.GetMemberView(loaded, "LF1").primary.regionId)
        end)

        it("keeps synchronized channels after a simulated reload", function()
            local Schema = ns.Modules.Internals("TwinFangs").Schema
            Deliver("1|1:15324:52:s|2:31425::y|3:12345:61:e|4:25134::n")
            local savedChain = Snapshot(module.db.interruptReminder.chain)
            local reloaded = Loader.Load()
            reloaded.Modules.Start(reloaded.Database.Load({
                modules = {
                    TwinFangs = {
                        interruptReminder = {
                            chain = savedChain,
                        },
                    },
                },
            }))
            local loaded = reloaded.Modules.Get("TwinFangs").db.interruptReminder.chain
            assert.equals(Schema.CHANNEL_SAY, loaded.front_left.channel)
            assert.equals(Schema.CHANNEL_YELL, loaded.front_right.channel)
            assert.equals(Schema.CHANNEL_EMOTE, loaded.back_left.channel)
            assert.equals(Schema.CHANNEL_NOD, loaded.back_right.channel)
            local ReloadedChain = reloaded.Modules.Internals("TwinFangs").InterruptChain
            assert.equals(ReloadedChain.FRONT_LEFT, ReloadedChain.GetMemberView(loaded, "LF1").primary.regionId)
        end)

        it("treats an unused saved chain as having no received assignments", function()
            assert.is_false(Chain.HasAssignments(module.db.interruptReminder.chain))
            assert.is_nil(Chain.GetMemberView(module.db.interruptReminder.chain, "LF1").primary)
            Deliver(EXAMPLE)
            assert.is_true(Chain.HasAssignments(module.db.interruptReminder.chain))
            assert.is_nil(Chain.GetMemberView(module.db.interruptReminder.chain, "nobody").primary)
            assert.equals(
                Chain.FRONT_LEFT,
                Chain.GetMemberView(module.db.interruptReminder.chain, "LF1").primary.regionId
            )
        end)
    end)
end)
