local Loader = require("helpers.loader")

describe("TwinFangs AddonCheck", function()
    local ns
    local TwinFangs
    local AddonCheck
    local Chain
    local Player
    local Group
    local L

    local function InspectConfig()
        return AddonCheck.GetConfig(TwinFangs.ADDON_CHECK_MODULE_ID)
    end

    local function AssignPrimary(name, regionId, index, extraPlayers)
        regionId = regionId or Chain.FRONT_LEFT
        local region = TwinFangs.db.interruptReminder.chain[regionId]
        region.group = 1
        local players = extraPlayers or {}
        index = index or (#players + 1)
        while #players < index do
            players[#players + 1] = { name = "Filler" .. #players .. "-TestRealm" }
        end
        players[index] = { name = name }
        region.players = players
        return region
    end

    local function AssignBackup(name, regionId)
        regionId = regionId or Chain.BACK_RIGHT
        local region = TwinFangs.db.interruptReminder.chain[regionId]
        region.group = 4
        if #region.players == 0 then
            region.players = { { name = "Primary-TestRealm" } }
        end
        region.backup = { name = name }
        return region
    end

    before_each(function()
        ns = Loader.Load()
        ns.Modules.Start(ns.Database.Load(nil))
        TwinFangs = ns.Modules.Get("TwinFangs")
        AddonCheck = ns.AddonCheck
        Chain = ns.Modules.Internals("TwinFangs").InterruptChain
        Player = ns.Api.Player
        Group = ns.Api.Group
        L = ns.L
    end)

    it("registers on module init without opening the settings UI", function()
        assert.is_true(AddonCheck.IsRegistered(TwinFangs.ADDON_CHECK_MODULE_ID))
        assert.equals("TwinFangs", TwinFangs.ADDON_CHECK_MODULE_ID)
        assert.is_true(AddonCheck.IsRegistered("Sszorak"))
    end)

    it("reports the same addon version as Sszorak AddonCheck", function()
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
        it("reports an unassigned player", function()
            local config = InspectConfig()
            assert.same({}, config.assignment)
            assert.is_nil(config.macro)
        end)

        it("reports a primary region and 1-based sequence", function()
            AssignPrimary(Player.GetFullName(), Chain.FRONT_RIGHT, 2)
            local config = InspectConfig()
            assert.equals(Chain.FRONT_RIGHT, config.assignment.region)
            assert.equals(2, config.assignment.index)
            assert.equals(2, config.assignment.indexEnd)
            assert.is_nil(config.assignment.backup)
            assert.equals("party", config.assignment.channel)
            assert.equals("pppp", config.channels)
        end)

        it("reports a consecutive interrupt range for repeated primaries", function()
            local name = Player.GetFullName()
            TwinFangs.db.interruptReminder.chain.front_left.group = 1
            TwinFangs.db.interruptReminder.chain.front_left.players = {
                { name = "A-TestRealm" },
                { name = name },
                { name = name },
                { name = name },
                { name = "B-TestRealm" },
            }
            local config = InspectConfig()
            assert.equals(Chain.FRONT_LEFT, config.assignment.region)
            assert.equals(2, config.assignment.index)
            assert.equals(4, config.assignment.indexEnd)
            assert.equals(
                string.format(L.TWIN_FANGS_ADDONCHECK_PRIMARY_RANGE, L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT, 2, 4)
                    .. " · /p",
                TwinFangs.FormatAddonCheckAssignment(config.assignment)
            )
        end)

        it("reports a backup-only assignment", function()
            AssignBackup(Player.GetFullName(), Chain.BACK_LEFT)
            local config = InspectConfig()
            assert.is_nil(config.assignment.region)
            assert.is_nil(config.assignment.index)
            assert.equals(Chain.BACK_LEFT, config.assignment.backup)
            assert.is_nil(config.macro)
        end)

        it("reports primary and backup together", function()
            AssignPrimary(Player.GetFullName(), Chain.FRONT_LEFT, 1)
            AssignBackup(Player.GetFullName(), Chain.BACK_RIGHT)
            local config = InspectConfig()
            assert.equals(Chain.FRONT_LEFT, config.assignment.region)
            assert.equals(1, config.assignment.index)
            assert.equals(Chain.BACK_RIGHT, config.assignment.backup)
            assert.equals("party", config.assignment.channel)
            assert.equals("party", config.assignment.backupChannel)
        end)

        it("reports the four-zone channel snapshot and per-role channels", function()
            local Schema = ns.Modules.Internals("TwinFangs").Schema
            AssignPrimary(Player.GetFullName(), Chain.FRONT_LEFT, 1)
            AssignBackup(Player.GetFullName(), Chain.BACK_RIGHT)
            TwinFangs.db.interruptReminder.chain.front_left.channel = Schema.CHANNEL_SAY
            TwinFangs.db.interruptReminder.chain.back_right.channel = Schema.CHANNEL_YELL
            local config = InspectConfig()
            assert.equals("s", config.channels:sub(1, 1))
            assert.equals("y", config.channels:sub(4, 4))
            assert.equals(Schema.CHANNEL_SAY, config.assignment.channel)
            assert.equals(Schema.CHANNEL_YELL, config.assignment.backupChannel)
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
            AssignPrimary("Alias-TestRealm", Chain.BACK_LEFT, 3, {
                { name = "One-TestRealm" },
                { name = "Two-TestRealm" },
                { name = "Alias-TestRealm" },
            })
            local config = InspectConfig()
            assert.equals(Chain.BACK_LEFT, config.assignment.region)
            assert.equals(3, config.assignment.index)
        end)

        it("does not mutate the saved interrupt chain", function()
            AssignPrimary(Player.GetFullName(), Chain.FRONT_LEFT, 1)
            local before = TwinFangs.db.interruptReminder.chain.front_left.players[1].name
            local snapshot = InspectConfig()
            snapshot.assignment.region = "mutated"
            assert.equals(before, TwinFangs.db.interruptReminder.chain.front_left.players[1].name)
            assert.equals(Chain.FRONT_LEFT, InspectConfig().assignment.region)
        end)
    end)

    describe("soak reminder", function()
        it("reports disabled without the saved group", function()
            TwinFangs:SetSoakGroup("right")
            TwinFangs:SetSoakReminderEnabled(false)
            local config = InspectConfig()
            assert.equals(false, config.soak)
        end)

        it("reports the selected group when enabled", function()
            TwinFangs:SetSoakReminderEnabled(true)
            TwinFangs:SetSoakGroup("middle")
            assert.equals("middle", InspectConfig().soak)
            TwinFangs:SetSoakGroup("left")
            assert.equals("left", InspectConfig().soak)
            TwinFangs:SetSoakGroup("right")
            assert.equals("right", InspectConfig().soak)
        end)

        it("fails safely on invalid soak settings", function()
            TwinFangs.db.soakReminder.enabled = "yes"
            local config, err = InspectConfig()
            assert.is_nil(config)
            assert.equals("provider_failed", err)
            TwinFangs.db.soakReminder.enabled = true
            TwinFangs.db.soakReminder.group = "center"
            config, err = InspectConfig()
            assert.is_nil(config)
            assert.equals("provider_failed", err)
        end)
    end)

    describe("serialization and request handling", function()
        it("encodes a complete snapshot within the 255-byte MessageProtocol limit", function()
            AssignPrimary(Player.GetFullName(), Chain.FRONT_LEFT, 2)
            AssignBackup(Player.GetFullName(), Chain.BACK_RIGHT)
            TwinFangs:SetSoakReminderEnabled(true)
            TwinFangs:SetSoakGroup("right")
            local config = InspectConfig()
            local body = assert(ns.AddonCheckCodec.EncodeValue(config))
            local payload = assert(
                ns.AddonCheckCodec.EncodeResponsePayload("ok", TwinFangs.ADDON_CHECK_MODULE_ID, AddonCheck.GetVersion(), body)
            )
            local wire = assert(
                ns.MessageProtocol.Encode(
                    ns.MessageProtocol.TYPE_RESPONSE,
                    AddonCheck.TOPIC,
                    "ac1",
                    payload
                )
            )
            assert.is_true(#wire <= ns.MessageProtocol.MAX_MESSAGE_LENGTH)
            local decoded = assert(ns.AddonCheckCodec.DecodeValue(body, 1))
            assert.same(config, decoded)
        end)

        it("answers a raid-leader TwinFangs request with the local snapshot", function()
            local AddonMessage = ns.Api.AddonMessage
            local MessageProtocol = ns.MessageProtocol
            ns.Api.MessageProtocolComm.Enable()
            Player.fullName = "Member-TestRealm"
            Group.raidLeaderFullName = "Leader-TestRealm"
            AssignPrimary(Player.GetFullName(), Chain.FRONT_LEFT, 1)
            TwinFangs:SetSoakReminderEnabled(true)
            TwinFangs:SetSoakGroup("left")

            local requestWire = assert(
                MessageProtocol.Encode(
                    MessageProtocol.TYPE_REQUEST,
                    AddonCheck.TOPIC,
                    "tf1",
                    "1|" .. TwinFangs.ADDON_CHECK_MODULE_ID
                )
            )
            AddonMessage.Deliver(ns.Api.MessageProtocolComm.PREFIX.CONTROL, requestWire, "RAID", "Leader-TestRealm")
            assert.equals(1, #AddonMessage.sent)
            local decoded = assert(MessageProtocol.Decode(AddonMessage.sent[1].message))
            local response = assert(ns.AddonCheckCodec.DecodeResponsePayload(decoded.payload))
            assert.equals("ok", response.status)
            assert.equals(TwinFangs.ADDON_CHECK_MODULE_ID, response.moduleId)
            assert.equals(AddonCheck.GetVersion(), response.version)
            local config = assert(ns.AddonCheckCodec.DecodeValue(response.body, 1))
            assert.equals(Chain.FRONT_LEFT, config.assignment.region)
            assert.equals(1, config.assignment.index)
            assert.is_nil(config.macro)
            assert.equals("left", config.soak)
        end)
    end)

    describe("StartCheck permissions, timeout, and leavers", function()
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
            local session, reason = AddonCheck.StartCheck(TwinFangs.ADDON_CHECK_MODULE_ID)
            assert.is_nil(session)
            assert.equals("not_raid_leader", reason)
            assert.equals(0, #ns.Api.AddonMessage.sent)
        end)

        it("times out missing remotes and keeps a leaver on the fixed roster", function()
            RaidAsLeader()
            local session = assert(AddonCheck.StartCheck(TwinFangs.ADDON_CHECK_MODULE_ID, { timeout = 1 }))
            assert.equals(AddonCheck.SessionStatus.RUNNING, session.status)
            assert.equals(AddonCheck.State.RESPONDED, session.results[Player.GetGUID()].state)
            assert.equals(AddonCheck.State.PENDING, session.results["Player-1-AAAA0002"].state)

            Group.members = { Group.members[1] }
            ns.Api.Timer.Advance(1)
            assert.equals(AddonCheck.SessionStatus.COMPLETED, session.status)
            assert.equals(AddonCheck.State.TIMED_OUT, session.results["Player-1-AAAA0002"].state)
            assert.equals(2, #session.roster)
        end)
    end)

    describe("result display", function()
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

        before_each(function()
            LoadPanel()
        end)

        it("formats primary, backup, and combined assignments", function()
            assert.equals(L.TWIN_FANGS_ADDONCHECK_UNASSIGNED, TwinFangs.FormatAddonCheckAssignment({}))
            assert.equals(
                string.format(L.TWIN_FANGS_ADDONCHECK_PRIMARY, L.TWIN_FANGS_INTERRUPT_REGION_FRONT_RIGHT, 4),
                TwinFangs.FormatAddonCheckAssignment({ region = Chain.FRONT_RIGHT, index = 4 })
            )
            assert.equals(
                string.format(L.TWIN_FANGS_ADDONCHECK_PRIMARY_RANGE, L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT, 2, 4),
                TwinFangs.FormatAddonCheckAssignment({ region = Chain.FRONT_LEFT, index = 2, indexEnd = 4 })
            )
            assert.equals(
                string.format(L.TWIN_FANGS_ADDONCHECK_BACKUP, L.TWIN_FANGS_INTERRUPT_REGION_BACK_LEFT),
                TwinFangs.FormatAddonCheckAssignment({ backup = Chain.BACK_LEFT })
            )
            assert.equals(
                string.format(L.TWIN_FANGS_ADDONCHECK_PRIMARY, L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT, 2)
                    .. "\n"
                    .. string.format(L.TWIN_FANGS_ADDONCHECK_BACKUP, L.TWIN_FANGS_INTERRUPT_REGION_BACK_RIGHT),
                TwinFangs.FormatAddonCheckAssignment({
                    region = Chain.FRONT_LEFT,
                    index = 2,
                    backup = Chain.BACK_RIGHT,
                })
            )
        end)

        it("distinguishes disabled soak from a missing field", function()
            assert.equals(L.TWIN_FANGS_ADDONCHECK_SOAK_DISABLED, TwinFangs.FormatAddonCheckSoak(false))
            assert.equals(L.TWIN_FANGS_SOAK_GROUP_LEFT, TwinFangs.FormatAddonCheckSoak("left"))
            assert.is_nil(TwinFangs.FormatAddonCheckSoak(nil))
        end)

        it("shows complete, missing, and partial responses", function()
            local moduleId = TwinFangs.ADDON_CHECK_MODULE_ID
            local columns = TwinFangs.AddonCheckColumns()
            local session = {
                id = 1,
                version = AddonCheck.GetVersion(),
                localConfigs = { [moduleId] = InspectConfig() },
                moduleId = moduleId,
                status = AddonCheck.SessionStatus.COMPLETED,
                roster = {
                    {
                        key = "ok",
                        name = "Ok",
                        fullName = "Ok-TestRealm",
                        subgroup = 1,
                    },
                    {
                        key = "missing",
                        name = "Missing",
                        fullName = "Missing-TestRealm",
                        subgroup = 1,
                    },
                    {
                        key = "partial",
                        name = "Partial",
                        fullName = "Partial-TestRealm",
                        subgroup = 2,
                    },
                    {
                        key = "old",
                        name = "Old",
                        fullName = "Old-TestRealm",
                        subgroup = 2,
                    },
                },
                results = {
                    ok = Result(AddonCheck.State.RESPONDED, {
                        playerName = "Ok-TestRealm",
                        version = AddonCheck.GetVersion(),
                        configs = {
                            [moduleId] = {
                                assignment = { region = Chain.FRONT_LEFT, index = 2 },
                                soak = "left",
                            },
                        },
                    }),
                    missing = Result(AddonCheck.State.TIMED_OUT, { playerName = "Missing-TestRealm" }),
                    partial = Result(AddonCheck.State.RESPONDED, {
                        playerName = "Partial-TestRealm",
                        version = AddonCheck.GetVersion(),
                        configs = {
                            [moduleId] = {
                                assignment = { backup = Chain.BACK_RIGHT },
                            },
                        },
                    }),
                    old = Result(AddonCheck.State.RESPONDED, {
                        playerName = "Old-TestRealm",
                        version = AddonCheck.GetVersion(),
                        message = "unknown_module",
                    }),
                },
            }
            local model = AddonCheckPanel.BuildViewModel(session, {
                moduleId = moduleId,
                columns = columns,
                validator = TwinFangs.ValidateAddonCheckConfig,
            })
            local byKey = AddonCheckPanel.IndexRowsByKey(model.rows)
            assert.equals(AddonCheckPanel.Category.OK, byKey.ok.category)
            assert.equals(
                string.format(L.TWIN_FANGS_ADDONCHECK_PRIMARY, L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT, 2),
                byKey.ok.configValues[1]
            )
            assert.equals(L.TWIN_FANGS_SOAK_GROUP_LEFT, byKey.ok.configValues[2])

            assert.equals(AddonCheckPanel.Category.NO_RESPONSE, byKey.missing.category)
            assert.equals(L.ADDONCHECK_EM_DASH, byKey.missing.configValues[1])
            assert.equals(L.ADDONCHECK_EM_DASH, byKey.missing.version)

            assert.equals(AddonCheckPanel.Category.ATTENTION, byKey.partial.category)
            assert.equals(
                string.format(L.TWIN_FANGS_ADDONCHECK_BACKUP, L.TWIN_FANGS_INTERRUPT_REGION_BACK_RIGHT),
                byKey.partial.configValues[1]
            )
            assert.equals(L.ADDONCHECK_EM_DASH, byKey.partial.configValues[2])
            assert.same({ "soak" }, byKey.partial.invalidColumns)

            assert.equals(AddonCheckPanel.Category.ATTENTION, byKey.old.category)
            assert.equals(L.ADDONCHECK_STATUS_UNSUPPORTED, byKey.old.statusLabel)
        end)

        it("does not flag informational assignment or disabled soak against the commander", function()
            assert.is_nil(TwinFangs.ValidateAddonCheckConfig({
                assignment = { region = Chain.FRONT_RIGHT, index = 4 },
                soak = false,
            }))
            assert.same(
                { "soak" },
                TwinFangs.ValidateAddonCheckConfig({
                    assignment = {},
                    soak = "center",
                })
            )
        end)

        it("appends slash commands to primary and backup lines", function()
            local Schema = ns.Modules.Internals("TwinFangs").Schema
            assert.equals(
                string.format(L.TWIN_FANGS_ADDONCHECK_PRIMARY, L.TWIN_FANGS_INTERRUPT_REGION_FRONT_LEFT, 2) .. " · /s",
                TwinFangs.FormatAddonCheckAssignment({
                    region = Chain.FRONT_LEFT,
                    index = 2,
                    channel = Schema.CHANNEL_SAY,
                })
            )
            assert.equals(
                string.format(L.TWIN_FANGS_ADDONCHECK_BACKUP, L.TWIN_FANGS_INTERRUPT_REGION_BACK_RIGHT) .. " · /y",
                TwinFangs.FormatAddonCheckAssignment({
                    backup = Chain.BACK_RIGHT,
                    backupChannel = Schema.CHANNEL_YELL,
                })
            )
        end)

        it("flags a channel snapshot that differs from the commander", function()
            local commander = {
                assignment = { region = Chain.FRONT_LEFT, index = 1 },
                channels = "sypy",
                soak = false,
            }
            assert.same(
                { "assignment" },
                TwinFangs.ValidateAddonCheckConfig({
                    assignment = { region = Chain.FRONT_LEFT, index = 1 },
                    channels = "pppp",
                    soak = false,
                }, commander)
            )
            assert.is_nil(TwinFangs.ValidateAddonCheckConfig({
                assignment = { region = Chain.FRONT_LEFT, index = 1 },
                channels = "sypy",
                soak = false,
            }, commander))
            assert.is_nil(TwinFangs.ValidateAddonCheckConfig({
                assignment = { region = Chain.FRONT_LEFT, index = 1 },
                soak = false,
            }, {
                assignment = { region = Chain.FRONT_LEFT, index = 1 },
                soak = false,
            }))
            assert.same(
                { "assignment" },
                TwinFangs.ValidateAddonCheckConfig({
                    assignment = { region = Chain.FRONT_LEFT, index = 1 },
                    soak = false,
                }, commander)
            )
        end)
    end)
end)
