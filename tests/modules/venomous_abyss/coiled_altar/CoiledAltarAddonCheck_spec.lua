local Loader = require("helpers.loader")

describe("CoiledAltar AddonCheck", function()
    local ns
    local CoiledAltar
    local AddonCheck
    local Assignments
    local Player
    local Group
    local L

    local function InspectConfig()
        return AddonCheck.GetConfig(CoiledAltar.ADDON_CHECK_MODULE_ID)
    end

    local function Slot(chainId, index)
        return { chain = chainId, slot = index }
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        CoiledAltar = ns.Modules.Get("CoiledAltar")
        AddonCheck = ns.AddonCheck
        Assignments = ns.Modules.Internals("CoiledAltar").InterruptAssignments
        Player = ns.Api.Player
        Group = ns.Api.Group
        L = ns.L
    end)

    it("registers on module init without opening the settings UI", function()
        assert.is_true(AddonCheck.IsRegistered(CoiledAltar.ADDON_CHECK_MODULE_ID))
        assert.equals("CoiledAltar", CoiledAltar.ADDON_CHECK_MODULE_ID)
        assert.is_true(AddonCheck.IsRegistered("TwinFangs"))
    end)

    it("reports the same addon version as Twin Fangs AddonCheck", function()
        assert.equals(AddonCheck.GetVersion(), ns.Api.Client.GetAddonVersion())
        local tocVersion
        for line in io.lines("NewEraTools.toc") do
            tocVersion = line:gsub("\r$", ""):match("^## Version:%s*(%S+)")
            if tocVersion then
                break
            end
        end
        assert.equals(tocVersion, AddonCheck.GetVersion())
    end)

    describe("assignment snapshot", function()
        it("reports no assignments", function()
            local config = InspectConfig()
            assert.same({}, config.assignments)
            assert.is_nil(config.expectedSlots)
        end)

        it("reports one assignment", function()
            assert.is_true(CoiledAltar:AssignInterruptPlayer(Assignments.MELEE, 2, Player.GetFullName()))
            assert.same({ Slot(Assignments.MELEE, 2) }, InspectConfig().assignments)
        end)

        it("reports multiple assignments in the same chain", function()
            local name = Player.GetFullName()
            CoiledAltar:AssignInterruptPlayer(Assignments.MELEE, 1, name)
            CoiledAltar:AssignInterruptPlayer(Assignments.MELEE, 3, name)
            assert.same({ Slot(Assignments.MELEE, 1), Slot(Assignments.MELEE, 3) }, InspectConfig().assignments)
        end)

        it("reports assignments across both chains when they exist locally", function()
            local name = Player.GetFullName()
            CoiledAltar.db.assignments.MELEE[1] = { type = Assignments.TYPE_PLAYER, value = name }
            CoiledAltar.db.assignments.RANGED[5] = { type = Assignments.TYPE_PLAYER, value = name }
            assert.same({
                Slot(Assignments.MELEE, 1),
                Slot(Assignments.RANGED, 5),
            }, InspectConfig().assignments)
        end)

        it("ignores custom text slots", function()
            local name = Player.GetFullName()
            CoiledAltar:AssignInterruptPlayer(Assignments.MELEE, 1, name)
            CoiledAltar:AssignInterruptText(Assignments.MELEE, 2, "点名近战")
            CoiledAltar:AssignInterruptText(Assignments.RANGED, 1, "点名远程")
            assert.same({ Slot(Assignments.MELEE, 1) }, InspectConfig().assignments)
        end)

        it("resolves the local player by raid GUID, not the client full name", function()
            Player.fullName = "Player-TestRealm"
            Player.guid = "Player-1-GUIDONLY"
            Group.members = {
                {
                    name = "Alias",
                    fullName = "Alias-TestRealm",
                    guid = Player.guid,
                    subgroup = 1,
                    classFile = "MAGE",
                    role = "DAMAGER",
                },
            }
            CoiledAltar:AssignInterruptPlayer(Assignments.RANGED, 4, "Alias-TestRealm")
            assert.same({ Slot(Assignments.RANGED, 4) }, InspectConfig().assignments)
        end)

        it("does not mutate saved assignments", function()
            CoiledAltar:AssignInterruptPlayer(Assignments.MELEE, 1, Player.GetFullName())
            local snapshot = InspectConfig()
            snapshot.assignments[1].slot = 6
            assert.equals(Player.GetFullName(), CoiledAltar:GetInterruptSlot(Assignments.MELEE, 1).value)
            assert.same({ Slot(Assignments.MELEE, 1) }, InspectConfig().assignments)
        end)

        it("includes expectedSlots only for the raid leader", function()
            CoiledAltar:AssignInterruptPlayer(Assignments.MELEE, 2, "Alice")
            CoiledAltar:AssignInterruptText(Assignments.RANGED, 3, "忽略")
            Group.isRaidLeader = true
            local config = InspectConfig()
            assert.same({
                { player = "Alice-TestRealm", chain = Assignments.MELEE, slot = 2 },
            }, config.expectedSlots)
            Group.isRaidLeader = false
            assert.is_nil(InspectConfig().expectedSlots)
        end)
    end)

    describe("marked chain and reminder", function()
        it("reports the marked-enemy chain and reminder toggle", function()
            local config = InspectConfig()
            assert.equals(Assignments.MELEE, config.markedChain)
            assert.equals(true, config.reminder)
            CoiledAltar:SetMarkedChain(Assignments.RANGED)
            CoiledAltar:SetInterruptReminderEnabled(false)
            config = InspectConfig()
            assert.equals(Assignments.RANGED, config.markedChain)
            assert.equals(false, config.reminder)
        end)
    end)

    describe("serialization and request handling", function()
        it("encodes a complete snapshot within the 255-byte MessageProtocol limit", function()
            CoiledAltar:AssignInterruptPlayer(Assignments.MELEE, 1, Player.GetFullName())
            CoiledAltar:AssignInterruptPlayer(Assignments.MELEE, 4, Player.GetFullName())
            CoiledAltar:SetMarkedChain(Assignments.RANGED)
            local config = InspectConfig()
            local body = assert(ns.AddonCheckCodec.EncodeValue(config))
            local payload = assert(
                ns.AddonCheckCodec.EncodeResponsePayload(
                    "ok",
                    CoiledAltar.ADDON_CHECK_MODULE_ID,
                    AddonCheck.GetVersion(),
                    body
                )
            )
            local wire =
                assert(ns.MessageProtocol.Encode(ns.MessageProtocol.TYPE_RESPONSE, AddonCheck.TOPIC, "ac1", payload))
            assert.is_true(#wire <= ns.MessageProtocol.MAX_MESSAGE_LENGTH)
            local decoded = assert(ns.AddonCheckCodec.DecodeValue(body, 1))
            assert.same(config, decoded)
        end)

        it("answers a raid-leader CoiledAltar request without changing local settings", function()
            local AddonMessage = ns.Api.AddonMessage
            local MessageProtocol = ns.MessageProtocol
            ns.Api.MessageProtocolComm.Enable()
            Player.fullName = "Member-TestRealm"
            Group.raidLeaderFullName = "Leader-TestRealm"
            CoiledAltar:AssignInterruptPlayer(Assignments.RANGED, 3, Player.GetFullName())
            CoiledAltar:SetMarkedChain(Assignments.RANGED)
            CoiledAltar:SetInterruptReminderEnabled(false)
            local before = ns.Util.DeepCopy(CoiledAltar.db.assignments)

            local requestWire = assert(
                MessageProtocol.Encode(
                    MessageProtocol.TYPE_REQUEST,
                    AddonCheck.TOPIC,
                    "ca1",
                    "1|" .. CoiledAltar.ADDON_CHECK_MODULE_ID
                )
            )
            AddonMessage.Deliver(ns.Api.MessageProtocolComm.PREFIX.CONTROL, requestWire, "RAID", "Leader-TestRealm")
            assert.equals(1, #AddonMessage.sent)
            local decoded = assert(MessageProtocol.Decode(AddonMessage.sent[1].message))
            assert.equals(AddonCheck.TOPIC, decoded.topic)
            local response = assert(ns.AddonCheckCodec.DecodeResponsePayload(decoded.payload))
            assert.equals("ok", response.status)
            assert.equals(CoiledAltar.ADDON_CHECK_MODULE_ID, response.moduleId)
            assert.equals(AddonCheck.GetVersion(), response.version)
            local config = assert(ns.AddonCheckCodec.DecodeValue(response.body, 1))
            assert.same({ Slot(Assignments.RANGED, 3) }, config.assignments)
            assert.equals(Assignments.RANGED, config.markedChain)
            assert.equals(false, config.reminder)
            assert.same(before, CoiledAltar.db.assignments)
            assert.equals(Assignments.RANGED, CoiledAltar:GetMarkedChain())
            assert.is_false(CoiledAltar:IsInterruptReminderEnabled())
        end)
    end)

    describe("StartCheck permissions, timeout, and stale correlation ids", function()
        local function RaidAsLeader()
            ns.Api.MessageProtocolComm.Enable()
            Group.isRaidLeader = true
            Group.raidLeaderFullName = Player.GetFullName()
            Group.raidChatType = "RAID"
            Group.members = {
                {
                    name = "Player",
                    fullName = Player.GetFullName(),
                    guid = Player.GetGUID(),
                    subgroup = 1,
                    classFile = "DRUID",
                    role = "HEALER",
                },
                {
                    name = "Alpha",
                    fullName = "Alpha-TestRealm",
                    guid = "Player-1-AAAA0002",
                    subgroup = 1,
                    classFile = "MAGE",
                    role = "DAMAGER",
                },
            }
        end

        it("refuses to start when the player is not raid leader", function()
            Group.isRaidLeader = false
            Group.raidChatType = "RAID"
            local session, reason = AddonCheck.StartCheck(CoiledAltar.ADDON_CHECK_MODULE_ID)
            assert.is_nil(session)
            assert.equals("not_raid_leader", reason)
            assert.equals(0, #ns.Api.AddonMessage.sent)
        end)

        it("times out missing remotes and ignores a superseded correlation id", function()
            RaidAsLeader()
            local first = assert(AddonCheck.StartCheck(CoiledAltar.ADDON_CHECK_MODULE_ID, { timeout = 1 }))
            local firstCorrelation = first.correlationId
            local second = assert(AddonCheck.StartCheck(CoiledAltar.ADDON_CHECK_MODULE_ID, { timeout = 1 }))
            assert.equals(AddonCheck.SessionStatus.SUPERSEDED, first.status)
            assert.equals(AddonCheck.State.PENDING, second.results["Player-1-AAAA0002"].state)

            local body = assert(ns.AddonCheckCodec.EncodeValue({
                player = "Alpha-TestRealm",
                assignments = {},
                markedChain = Assignments.MELEE,
                reminder = true,
            }))
            local payload = assert(
                ns.AddonCheckCodec.EncodeResponsePayload(
                    "ok",
                    CoiledAltar.ADDON_CHECK_MODULE_ID,
                    AddonCheck.GetVersion(),
                    body
                )
            )
            local staleWire = assert(
                ns.MessageProtocol.Encode(
                    ns.MessageProtocol.TYPE_RESPONSE,
                    AddonCheck.TOPIC,
                    firstCorrelation,
                    payload
                )
            )
            ns.Api.AddonMessage.Deliver(
                ns.Api.MessageProtocolComm.PREFIX.CONTROL,
                staleWire,
                "WHISPER",
                "Alpha-TestRealm"
            )
            assert.equals(AddonCheck.State.PENDING, second.results["Player-1-AAAA0002"].state)

            ns.Api.Timer.Advance(1)
            assert.equals(AddonCheck.SessionStatus.COMPLETED, second.status)
            assert.equals(AddonCheck.State.TIMED_OUT, second.results["Player-1-AAAA0002"].state)
        end)
    end)

    describe("commander comparison and display", function()
        local AddonCheckPanel

        local function LoadPanel()
            ns.CollapsibleSection = ns.CollapsibleSection or {}
            ns.Layout = ns.Layout or {}
            ns.Widgets = ns.Widgets or {}
            assert(loadfile("ui/AddonCheckPanelModel.lua"))(Loader.ADDON_NAME, ns)
            assert(loadfile("ui/AddonCheckPanel.lua"))(Loader.ADDON_NAME, ns)
            AddonCheckPanel = ns.AddonCheckPanel
        end

        local function Result(state, extras)
            local result = { state = state }
            for key, value in pairs(extras or {}) do
                result[key] = value
            end
            return result
        end

        local function CommanderConfig()
            Group.isRaidLeader = true
            CoiledAltar:AssignInterruptPlayer(Assignments.MELEE, 1, "Alpha")
            CoiledAltar:AssignInterruptPlayer(Assignments.MELEE, 3, "Alpha")
            CoiledAltar:AssignInterruptPlayer(Assignments.RANGED, 5, "Beta")
            CoiledAltar:SetMarkedChain(Assignments.MELEE)
            CoiledAltar:SetInterruptReminderEnabled(true)
            return InspectConfig()
        end

        local function Peer(name, extras)
            local config = {
                player = name,
                assignments = {},
                markedChain = Assignments.MELEE,
                reminder = true,
            }
            for key, value in pairs(extras or {}) do
                config[key] = value
            end
            return config
        end

        before_each(function()
            LoadPanel()
        end)

        it("formats empty, same-chain, and both-chain assignments", function()
            assert.equals(L.COILED_ALTAR_ADDONCHECK_UNASSIGNED, CoiledAltar.FormatAddonCheckAssignment({}))
            assert.equals(
                string.format(
                    L.COILED_ALTAR_ADDONCHECK_CHAIN_SLOTS,
                    L.COILED_ALTAR_MARKED_SIDE_MELEE,
                    table.concat({ "1", "3" }, L.COILED_ALTAR_ADDONCHECK_SLOT_JOIN)
                ),
                CoiledAltar.FormatAddonCheckAssignment({
                    Slot(Assignments.MELEE, 3),
                    Slot(Assignments.MELEE, 1),
                })
            )
            assert.equals(
                string.format(L.COILED_ALTAR_ADDONCHECK_CHAIN_SLOTS, L.COILED_ALTAR_MARKED_SIDE_MELEE, "1")
                    .. L.COILED_ALTAR_ADDONCHECK_CHAIN_JOIN
                    .. string.format(L.COILED_ALTAR_ADDONCHECK_CHAIN_SLOTS, L.COILED_ALTAR_MARKED_SIDE_RANGED, "5"),
                CoiledAltar.FormatAddonCheckAssignment({
                    Slot(Assignments.RANGED, 5),
                    Slot(Assignments.MELEE, 1),
                })
            )
        end)

        it("treats assignment order as irrelevant when the sets match", function()
            local commander = CommanderConfig()
            assert.is_nil(CoiledAltar.ValidateAddonCheckConfig(Peer("Alpha-TestRealm", {
                assignments = { Slot(Assignments.MELEE, 3), Slot(Assignments.MELEE, 1) },
            }), commander))
        end)

        it("flags missing or extra assignments", function()
            local commander = CommanderConfig()
            assert.same(
                { "assignments" },
                CoiledAltar.ValidateAddonCheckConfig(Peer("Alpha-TestRealm", {
                    assignments = { Slot(Assignments.MELEE, 1) },
                }), commander)
            )
            assert.same(
                { "assignments" },
                CoiledAltar.ValidateAddonCheckConfig(Peer("Alpha-TestRealm", {
                    assignments = {
                        Slot(Assignments.MELEE, 1),
                        Slot(Assignments.MELEE, 3),
                        Slot(Assignments.MELEE, 4),
                    },
                }), commander)
            )
        end)

        it("matches empty expected and reported assignment sets", function()
            local commander = CommanderConfig()
            assert.is_nil(CoiledAltar.ValidateAddonCheckConfig(Peer("Unassigned-TestRealm"), commander))
        end)

        it("flags a marked-enemy mismatch without requiring an assignment mismatch", function()
            local commander = CommanderConfig()
            assert.same(
                { "markedChain" },
                CoiledAltar.ValidateAddonCheckConfig(Peer("Unassigned-TestRealm", {
                    markedChain = Assignments.RANGED,
                }), commander)
            )
        end)

        it("flags both assignment and marked-enemy mismatches", function()
            local commander = CommanderConfig()
            assert.same(
                { "assignments", "markedChain" },
                CoiledAltar.ValidateAddonCheckConfig(Peer("Alpha-TestRealm", {
                    assignments = { Slot(Assignments.RANGED, 2) },
                    markedChain = Assignments.RANGED,
                    reminder = false,
                }), commander)
            )
        end)

        it("does not warn when only the interrupt reminder differs", function()
            local commander = CommanderConfig()
            assert.is_nil(CoiledAltar.ValidateAddonCheckConfig(Peer("Unassigned-TestRealm", {
                reminder = false,
            }), commander))
        end)

        it("flags malformed responses", function()
            local commander = CommanderConfig()
            assert.same({ "assignments", "markedChain" }, CoiledAltar.ValidateAddonCheckConfig(nil, commander))
            assert.same(
                { "assignments" },
                CoiledAltar.ValidateAddonCheckConfig(Peer("Alpha-TestRealm", {
                    player = "",
                    assignments = { Slot(Assignments.MELEE, 1), Slot(Assignments.MELEE, 3) },
                }), commander)
            )
            assert.same(
                { "assignments" },
                CoiledAltar.ValidateAddonCheckConfig(Peer("Alpha-TestRealm", {
                    assignments = { { chain = "front", slot = 1 } },
                }), commander)
            )
            assert.same(
                { "markedChain" },
                CoiledAltar.ValidateAddonCheckConfig(Peer("Unassigned-TestRealm", {
                    markedChain = "both",
                }), commander)
            )
        end)

        it("shows expected versus reported values for mismatches", function()
            local moduleId = CoiledAltar.ADDON_CHECK_MODULE_ID
            local commander = CommanderConfig()
            local session = {
                id = 1,
                version = AddonCheck.GetVersion(),
                localConfigs = { [moduleId] = commander },
                moduleId = moduleId,
                status = AddonCheck.SessionStatus.COMPLETED,
                roster = {
                    { key = "ok", name = "Alpha", fullName = "Alpha-TestRealm", subgroup = 1 },
                    { key = "both", name = "Beta", fullName = "Beta-TestRealm", subgroup = 1 },
                    { key = "missing", name = "Missing", fullName = "Missing-TestRealm", subgroup = 2 },
                    { key = "off", name = "Gamma", fullName = "Gamma-TestRealm", subgroup = 2 },
                },
                results = {
                    ok = Result(AddonCheck.State.RESPONDED, {
                        playerName = "Alpha-TestRealm",
                        version = AddonCheck.GetVersion(),
                        configs = {
                            [moduleId] = Peer("Alpha-TestRealm", {
                                assignments = { Slot(Assignments.MELEE, 3), Slot(Assignments.MELEE, 1) },
                            }),
                        },
                    }),
                    both = Result(AddonCheck.State.RESPONDED, {
                        playerName = "Beta-TestRealm",
                        version = AddonCheck.GetVersion(),
                        configs = {
                            [moduleId] = Peer("Beta-TestRealm", {
                                assignments = { Slot(Assignments.MELEE, 2) },
                                markedChain = Assignments.RANGED,
                                reminder = false,
                            }),
                        },
                    }),
                    missing = Result(AddonCheck.State.TIMED_OUT, { playerName = "Missing-TestRealm" }),
                    off = Result(AddonCheck.State.RESPONDED, {
                        playerName = "Gamma-TestRealm",
                        version = AddonCheck.GetVersion(),
                        configs = {
                            [moduleId] = Peer("Gamma-TestRealm", { reminder = false }),
                        },
                    }),
                },
            }
            local model = AddonCheckPanel.BuildViewModel(session, {
                moduleId = moduleId,
                columns = CoiledAltar.AddonCheckColumns(),
                validator = CoiledAltar.ValidateAddonCheckConfig,
            })
            local byKey = AddonCheckPanel.IndexRowsByKey(model.rows)
            assert.equals(AddonCheckPanel.Category.OK, byKey.ok.category)
            assert.equals(
                string.format(
                    L.COILED_ALTAR_ADDONCHECK_CHAIN_SLOTS,
                    L.COILED_ALTAR_MARKED_SIDE_MELEE,
                    table.concat({ "1", "3" }, L.COILED_ALTAR_ADDONCHECK_SLOT_JOIN)
                ),
                byKey.ok.configValues[1]
            )
            assert.equals(L.COILED_ALTAR_MARKED_SIDE_MELEE, byKey.ok.configValues[2])
            assert.equals(L.COILED_ALTAR_ADDONCHECK_REMINDER_ON, byKey.ok.configValues[3])

            assert.equals(AddonCheckPanel.Category.ATTENTION, byKey.both.category)
            assert.same({ "assignments", "markedChain" }, byKey.both.invalidColumns)
            assert.equals(
                string.format(
                    L.COILED_ALTAR_ADDONCHECK_MISMATCH,
                    string.format(L.COILED_ALTAR_ADDONCHECK_CHAIN_SLOTS, L.COILED_ALTAR_MARKED_SIDE_RANGED, "5"),
                    string.format(L.COILED_ALTAR_ADDONCHECK_CHAIN_SLOTS, L.COILED_ALTAR_MARKED_SIDE_MELEE, "2")
                ),
                byKey.both.configValues[1]
            )
            assert.equals(
                string.format(
                    L.COILED_ALTAR_ADDONCHECK_MISMATCH,
                    L.COILED_ALTAR_MARKED_SIDE_MELEE,
                    L.COILED_ALTAR_MARKED_SIDE_RANGED
                ),
                byKey.both.configValues[2]
            )
            assert.equals(L.COILED_ALTAR_ADDONCHECK_REMINDER_OFF, byKey.both.configValues[3])

            assert.equals(AddonCheckPanel.Category.NO_RESPONSE, byKey.missing.category)
            assert.equals(L.ADDONCHECK_EM_DASH, byKey.missing.configValues[1])

            assert.equals(AddonCheckPanel.Category.OK, byKey.off.category)
            assert.equals(L.COILED_ALTAR_ADDONCHECK_UNASSIGNED, byKey.off.configValues[1])
            assert.equals(L.COILED_ALTAR_ADDONCHECK_REMINDER_OFF, byKey.off.configValues[3])
        end)
    end)
end)
