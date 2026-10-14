local Loader = require("helpers.loader")

describe("AddonCheckPanel", function()
    local ns
    local AddonCheck
    local AddonCheckPanel
    local L

    local MODULE_ID = "Feature"
    local COLUMNS

    before_each(function()
        ns = Loader.Load()
        AddonCheck = ns.AddonCheck
        L = ns.L
        -- Create() needs frames; BuildViewModel only needs the model table.
        ns.CollapsibleSection = ns.CollapsibleSection or {}
        ns.Layout = ns.Layout or {}
        ns.Widgets = ns.Widgets or {}
        assert(loadfile("ui/AddonCheckPanelModel.lua"))(Loader.ADDON_NAME, ns)
        assert(loadfile("ui/AddonCheckPanel.lua"))(Loader.ADDON_NAME, ns)
        AddonCheckPanel = ns.AddonCheckPanel

        COLUMNS = {
            {
                key = "enabled",
                title = "Enabled",
                format = function(value)
                    if value == true then
                        return "On"
                    end
                    if value == false then
                        return "Off"
                    end
                    return nil
                end,
            },
            {
                key = "side",
                title = "Side",
                format = function(value)
                    if value == "left" then
                        return "Left"
                    end
                    if value == "right" then
                        return "Right"
                    end
                    return nil
                end,
            },
            {
                key = "mode",
                title = "Mode",
                format = function(value)
                    if value == "normal" then
                        return "Normal"
                    end
                    if value == "jailbreak" then
                        return "Jailbreak"
                    end
                    return nil
                end,
            },
        }
    end)

    local function MakeSession(overrides)
        local session = {
            id = 1,
            version = "0.2.0",
            localConfigs = { [MODULE_ID] = { side = "left", mode = "normal" } },
            results = {},
            moduleId = MODULE_ID,
            status = AddonCheck.SessionStatus.COMPLETED,
            roster = {},
        }
        for key, value in pairs(overrides or {}) do
            session[key] = value
        end
        return session
    end

    local function Result(state, fields)
        local result = {
            state = state,
            playerName = fields.playerName or "Player-Realm",
            version = fields.version,
            configs = fields.configs,
            message = fields.message,
        }
        return result
    end

        it("shows empty state before the first check", function()
            local model = AddonCheckPanel.BuildViewModel(nil, {
                moduleId = MODULE_ID,
                columns = COLUMNS,
            })
            assert.is_false(model.hasSession)
            assert.equals(L.ADDONCHECK_EMPTY, model.emptyText)
            assert.equals(0, #model.rows)
        end)

    it("formats module columns and uses em dash for missing values", function()
        local session = MakeSession({
            results = {
                a = Result(AddonCheck.State.RESPONDED, {
                    playerName = "Alice-Realm",
                    version = "0.2.0",
                    configs = { [MODULE_ID] = { enabled = true, side = "left", mode = "normal" } },
                }),
                b = Result(AddonCheck.State.RESPONDED, {
                    playerName = "Bob-Realm",
                    configs = { [MODULE_ID] = { enabled = false, side = "nope" } },
                }),
            },
            roster = {
                { key = "a", fullName = "Alice-Realm", name = "Alice", subgroup = 2 },
                { key = "b", fullName = "Bob-Realm", name = "Bob" },
            },
        })
        local model = AddonCheckPanel.BuildViewModel(session, {
            moduleId = MODULE_ID,
            columns = COLUMNS,
        })
        assert.equals(2, #model.rows)
        local byName = {}
        for _, row in ipairs(model.rows) do
            byName[row.playerName] = row
        end
        assert.same({ "On", "Left", "Normal" }, byName.Alice.configValues)
        -- false must format as Off, not em dash (Lua `and`/`or` trap).
        assert.same({ "Off", L.ADDONCHECK_EM_DASH, L.ADDONCHECK_EM_DASH }, byName.Bob.configValues)
        assert.equals("0.2.0", byName.Alice.version)
        assert.equals(L.ADDONCHECK_EM_DASH, byName.Bob.version)
        assert.equals("2", byName.Alice.party)
        assert.equals(2, byName.Alice.subgroup)
        assert.equals(L.ADDONCHECK_EM_DASH, byName.Bob.party)
        assert.is_nil(byName.Bob.subgroup)
    end)

    it("sorts by party number", function()
        local session = MakeSession({
            results = {
                a = Result(AddonCheck.State.RESPONDED, {
                    playerName = "Ada-R",
                    version = "0.2.0",
                    configs = { [MODULE_ID] = { side = "left", mode = "normal" } },
                }),
                b = Result(AddonCheck.State.RESPONDED, {
                    playerName = "Bea-R",
                    version = "0.2.0",
                    configs = { [MODULE_ID] = { side = "left", mode = "normal" } },
                }),
                c = Result(AddonCheck.State.RESPONDED, {
                    playerName = "Cara-R",
                    version = "0.2.0",
                    configs = { [MODULE_ID] = { side = "left", mode = "normal" } },
                }),
            },
            roster = {
                { key = "a", name = "Ada", fullName = "Ada-R", subgroup = 3 },
                { key = "b", name = "Bea", fullName = "Bea-R", subgroup = 1 },
                { key = "c", name = "Cara", fullName = "Cara-R", subgroup = 2 },
            },
        })
        local model = AddonCheckPanel.BuildViewModel(session, {
            moduleId = MODULE_ID,
            columns = COLUMNS,
            sortKey = AddonCheckPanel.SortColumn.PARTY,
            sortAscending = true,
        })
        assert.equals("Bea", model.visibleRows[1].playerName)
        assert.equals("Cara", model.visibleRows[2].playerName)
        assert.equals("Ada", model.visibleRows[3].playerName)
    end)

        it("classifies pending, timeout, unsupported, provider error, and ok", function()
        local session = MakeSession({
            results = {
                p = Result(AddonCheck.State.PENDING, { playerName = "Pending-R" }),
                t = Result(AddonCheck.State.TIMED_OUT, { playerName = "Timeout-R" }),
                u = Result(AddonCheck.State.RESPONDED, {
                    playerName = "Unsupported-R",
                    version = "0.1.0",
                    message = "unknown_module",
                }),
                f = Result(AddonCheck.State.FAILED, {
                    playerName = "Fail-R",
                    message = "provider_failed",
                }),
                o = Result(AddonCheck.State.RESPONDED, {
                    playerName = "Ok-R",
                    version = "0.2.0",
                    configs = { [MODULE_ID] = { side = "left", mode = "normal" } },
                }),
            },
            roster = {
                { key = "o", fullName = "Ok-R", name = "Ok", classFile = "WARRIOR" },
            },
        })
        local model = AddonCheckPanel.BuildViewModel(session, {
            moduleId = MODULE_ID,
            columns = COLUMNS,
        })
        assert.equals(1, model.summaryOk)
        assert.equals(2, model.summaryAttention)
        assert.equals(2, model.summaryNoResponse)
        -- Progress counts every non-pending terminal result (including timeouts / failures).
        assert.equals(string.format(L.ADDONCHECK_PROGRESS, 4, 5), model.progressText)

        local byKey = AddonCheckPanel.IndexRowsByKey(model.rows)
        assert.equals(AddonCheckPanel.Category.NO_RESPONSE, byKey.p.category)
        assert.equals(L.ADDONCHECK_STATUS_PENDING, byKey.p.statusLabel)
        assert.equals("Interface\\RaidFrame\\ReadyCheck-Waiting", byKey.p.statusIcon)
        assert.equals(AddonCheckPanel.Category.NO_RESPONSE, byKey.t.category)
        assert.equals(L.ADDONCHECK_STATUS_TIMEOUT, byKey.t.statusLabel)
        assert.equals("Interface\\RaidFrame\\ReadyCheck-NotReady", byKey.t.statusIcon)
        assert.equals(AddonCheckPanel.Category.ATTENTION, byKey.u.category)
        assert.equals(L.ADDONCHECK_STATUS_UNSUPPORTED, byKey.u.statusLabel)
        assert.equals("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew", byKey.u.statusIcon)
        assert.equals(AddonCheckPanel.Category.ATTENTION, byKey.f.category)
        assert.equals(L.ADDONCHECK_STATUS_PROVIDER_ERROR, byKey.f.statusLabel)
        assert.equals(AddonCheckPanel.Category.OK, byKey.o.category)
        assert.equals(L.ADDONCHECK_STATUS_OK, byKey.o.statusLabel)
        assert.equals("Interface\\RaidFrame\\ReadyCheck-Ready", byKey.o.statusIcon)
        assert.equals("WARRIOR", byKey.o.classFile)
    end)

    it("flags version differs without treating it as confirmed incompatible", function()
        local session = MakeSession({
            results = {
                v = Result(AddonCheck.State.RESPONDED, {
                    playerName = "Old-R",
                    version = "0.1.0",
                    configs = { [MODULE_ID] = { side = "left", mode = "normal" } },
                }),
            },
        })
        local model = AddonCheckPanel.BuildViewModel(session, {
            moduleId = MODULE_ID,
            columns = COLUMNS,
        })
        assert.equals(AddonCheckPanel.Category.ATTENTION, model.rows[1].category)
        assert.equals(L.ADDONCHECK_STATUS_VERSION_DIFFERS, model.rows[1].statusLabel)
        assert.is_false(model.rows[1].statusLabel == L.ADDONCHECK_STATUS_INCOMPATIBLE)
    end)

    it("does not treat config differences as issues unless a mismatch rule is provided", function()
        local session = MakeSession({
            results = {
                c = Result(AddonCheck.State.RESPONDED, {
                    playerName = "Other-R",
                    version = "0.2.0",
                    configs = { [MODULE_ID] = { side = "right", mode = "jailbreak" } },
                }),
            },
        })
        local plain = AddonCheckPanel.BuildViewModel(session, {
            moduleId = MODULE_ID,
            columns = COLUMNS,
        })
        assert.equals(AddonCheckPanel.Category.OK, plain.rows[1].category)

        local flagged = AddonCheckPanel.BuildViewModel(session, {
            moduleId = MODULE_ID,
            columns = COLUMNS,
            isConfigMismatch = function(config, localConfig)
                return config.side ~= localConfig.side
            end,
        })
        assert.equals(AddonCheckPanel.Category.ATTENTION, flagged.rows[1].category)
        assert.equals(L.ADDONCHECK_STATUS_CONFIG_MISMATCH, flagged.rows[1].statusLabel)
    end)

    it("marks validator-flagged column keys and treats empty/nil as valid", function()
        local session = MakeSession({
            results = {
                on = Result(AddonCheck.State.RESPONDED, {
                    playerName = "On-R",
                    version = "0.2.0",
                    configs = { [MODULE_ID] = { side = "left", mode = "normal", enabled = true } },
                }),
                off = Result(AddonCheck.State.RESPONDED, {
                    playerName = "Off-R",
                    version = "0.2.0",
                    configs = { [MODULE_ID] = { side = "left", mode = "normal", enabled = false } },
                }),
                empty = Result(AddonCheck.State.RESPONDED, {
                    playerName = "Empty-R",
                    version = "0.2.0",
                    configs = { [MODULE_ID] = { side = "right", mode = "normal", enabled = true } },
                }),
            },
            roster = {
                { key = "on", fullName = "On-R", name = "On" },
                { key = "off", fullName = "Off-R", name = "Off" },
                { key = "empty", fullName = "Empty-R", name = "Empty" },
            },
        })
        local model = AddonCheckPanel.BuildViewModel(session, {
            moduleId = MODULE_ID,
            columns = COLUMNS,
            validator = function(config)
                if config.enabled == true then
                    if config.side == "right" then
                        return {}
                    end
                    return nil
                end
                return { "enabled" }
            end,
        })
        local byKey = AddonCheckPanel.IndexRowsByKey(model.rows)
        assert.equals(AddonCheckPanel.Category.OK, byKey.on.category)
        assert.same({}, byKey.on.invalidColumns)
        assert.equals(AddonCheckPanel.Category.OK, byKey.empty.category)
        assert.same({}, byKey.empty.invalidColumns)
        assert.equals(AddonCheckPanel.Category.ATTENTION, byKey.off.category)
        assert.same({ "enabled" }, byKey.off.invalidColumns)
        assert.equals(L.ADDONCHECK_STATUS_VALIDATION, byKey.off.statusLabel)
        assert.equals("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew", byKey.off.statusIcon)
    end)

    it("passes the commander localConfig into the validator", function()
        local session = MakeSession({
            localConfigs = { [MODULE_ID] = { side = "left", mode = "normal" } },
            results = {
                m = Result(AddonCheck.State.RESPONDED, {
                    playerName = "Mode-R",
                    version = "0.2.0",
                    configs = { [MODULE_ID] = { side = "left", mode = "jailbreak", enabled = true } },
                }),
            },
            roster = {
                { key = "m", fullName = "Mode-R", name = "Mode" },
            },
        })
        local seenLocal
        local model = AddonCheckPanel.BuildViewModel(session, {
            moduleId = MODULE_ID,
            columns = COLUMNS,
            validator = function(config, localConfig)
                seenLocal = localConfig
                if config.mode ~= localConfig.mode then
                    return { "mode" }
                end
                return nil
            end,
        })
        assert.same({ side = "left", mode = "normal" }, seenLocal)
        assert.same({ "mode" }, model.rows[1].invalidColumns)
        assert.equals(AddonCheckPanel.Category.ATTENTION, model.rows[1].category)
    end)

    it("shows pending results from the current session only (no prior-session cache)", function()
        local session = MakeSession({
            status = AddonCheck.SessionStatus.RUNNING,
            results = {
                a = Result(AddonCheck.State.PENDING, { playerName = "Alice-Realm" }),
            },
            roster = {
                { key = "a", name = "Alice", fullName = "Alice-Realm", classFile = "MAGE" },
            },
        })
        local model = AddonCheckPanel.BuildViewModel(session, {
            moduleId = MODULE_ID,
            columns = COLUMNS,
        })
        assert.equals(1, #model.rows)
        assert.equals("Alice", model.rows[1].playerName)
        assert.equals(AddonCheckPanel.Category.NO_RESPONSE, model.rows[1].category)
        assert.equals(L.ADDONCHECK_STATUS_PENDING, model.rows[1].statusLabel)
        assert.equals(L.ADDONCHECK_EM_DASH, model.rows[1].configValues[1])
    end)

    it("keeps raid roster order by default and filters issues without reordering", function()
        local session = MakeSession({
            results = {
                z = Result(AddonCheck.State.RESPONDED, {
                    playerName = "Zed-R",
                    version = "0.2.0",
                    configs = { [MODULE_ID] = { side = "left", mode = "normal" } },
                }),
                a = Result(AddonCheck.State.TIMED_OUT, { playerName = "Ann-R" }),
                m = Result(AddonCheck.State.FAILED, {
                    playerName = "Mo-R",
                    message = "send_failed",
                }),
            },
            roster = {
                { key = "z", fullName = "Zed-R", name = "Zed" },
                { key = "a", fullName = "Ann-R", name = "Ann" },
                { key = "m", fullName = "Mo-R", name = "Mo" },
            },
        })
        local all = AddonCheckPanel.BuildViewModel(session, {
            moduleId = MODULE_ID,
            columns = COLUMNS,
            filter = AddonCheckPanel.Filter.ALL,
        })
        assert.equals(3, #all.visibleRows)
        assert.equals("Zed", all.visibleRows[1].playerName)
        assert.equals("Ann", all.visibleRows[2].playerName)
        assert.equals("Mo", all.visibleRows[3].playerName)

        local issues = AddonCheckPanel.BuildViewModel(session, {
            moduleId = MODULE_ID,
            columns = COLUMNS,
            filter = AddonCheckPanel.Filter.ISSUES,
        })
        assert.equals(2, #issues.visibleRows)
        assert.equals("Ann", issues.visibleRows[1].playerName)
        assert.equals("Mo", issues.visibleRows[2].playerName)
        for _, row in ipairs(issues.visibleRows) do
            assert.is_false(row.category == AddonCheckPanel.Category.OK)
        end
    end)

    it("sorts by column ascending then descending", function()
        local session = MakeSession({
            results = {
                c = Result(AddonCheck.State.RESPONDED, {
                    playerName = "Cara-R",
                    version = "0.3.0",
                    configs = { [MODULE_ID] = { side = "right", mode = "normal" } },
                }),
                a = Result(AddonCheck.State.RESPONDED, {
                    playerName = "Ada-R",
                    version = "0.1.0",
                    configs = { [MODULE_ID] = { side = "left", mode = "jailbreak" } },
                }),
                b = Result(AddonCheck.State.TIMED_OUT, { playerName = "Bea-R" }),
            },
            roster = {
                { key = "a", name = "Ada", fullName = "Ada-R" },
                { key = "b", name = "Bea", fullName = "Bea-R" },
                { key = "c", name = "Cara", fullName = "Cara-R" },
            },
        })

        local byPlayer = AddonCheckPanel.BuildViewModel(session, {
            moduleId = MODULE_ID,
            columns = COLUMNS,
            sortKey = AddonCheckPanel.SortColumn.PLAYER,
            sortAscending = true,
        })
        assert.equals("Ada", byPlayer.visibleRows[1].playerName)
        assert.equals("Bea", byPlayer.visibleRows[2].playerName)
        assert.equals("Cara", byPlayer.visibleRows[3].playerName)

        local byPlayerDesc = AddonCheckPanel.BuildViewModel(session, {
            moduleId = MODULE_ID,
            columns = COLUMNS,
            sortKey = AddonCheckPanel.SortColumn.PLAYER,
            sortAscending = false,
        })
        assert.equals("Cara", byPlayerDesc.visibleRows[1].playerName)
        assert.equals("Bea", byPlayerDesc.visibleRows[2].playerName)
        assert.equals("Ada", byPlayerDesc.visibleRows[3].playerName)

        local bySide = AddonCheckPanel.BuildViewModel(session, {
            moduleId = MODULE_ID,
            columns = COLUMNS,
            sortKey = AddonCheckPanel.ConfigSortKey(1),
            sortAscending = true,
        })
        local adaIdx, caraIdx
        for i = 1, #bySide.visibleRows do
            if bySide.visibleRows[i].playerName == "Ada" then
                adaIdx = i
            elseif bySide.visibleRows[i].playerName == "Cara" then
                caraIdx = i
            end
        end
        assert.is_true(adaIdx < caraIdx)

        local byStatus = AddonCheckPanel.BuildViewModel(session, {
            moduleId = MODULE_ID,
            columns = COLUMNS,
            sortKey = AddonCheckPanel.SortColumn.STATUS,
            sortAscending = true,
        })
        -- Version differs from session baseline → attention; timeout → no_response.
        assert.equals(AddonCheckPanel.Category.ATTENTION, byStatus.visibleRows[1].category)
        assert.equals(AddonCheckPanel.Category.ATTENTION, byStatus.visibleRows[2].category)
        assert.equals(AddonCheckPanel.Category.NO_RESPONSE, byStatus.visibleRows[3].category)

        local byStatusDesc = AddonCheckPanel.BuildViewModel(session, {
            moduleId = MODULE_ID,
            columns = COLUMNS,
            sortKey = AddonCheckPanel.SortColumn.STATUS,
            sortAscending = false,
        })
        assert.equals(AddonCheckPanel.Category.NO_RESPONSE, byStatusDesc.visibleRows[1].category)
    end)

    it("summarizes a large roster without dropping members", function()
        local results = {}
        local roster = {}
        for i = 1, 30 do
            local key = "m" .. i
            local ok = i % 3 == 0
            local timedOut = i % 3 == 1
            results[key] = Result(
                ok and AddonCheck.State.RESPONDED or (timedOut and AddonCheck.State.TIMED_OUT or AddonCheck.State.FAILED),
                {
                    playerName = string.format("P%02d-Realm", i),
                    version = ok and "0.2.0" or nil,
                    configs = ok and { [MODULE_ID] = { side = "left", mode = "normal" } } or nil,
                    message = (not ok and not timedOut) and "provider_failed" or nil,
                }
            )
            roster[#roster + 1] = {
                key = key,
                fullName = string.format("P%02d-Realm", i),
                name = string.format("P%02d", i),
            }
        end
        local model = AddonCheckPanel.BuildViewModel(MakeSession({ results = results, roster = roster }), {
            moduleId = MODULE_ID,
            columns = COLUMNS,
        })
        assert.equals(30, #model.rows)
        assert.equals(30, model.summaryOk + model.summaryAttention + model.summaryNoResponse)
        assert.equals(10, model.summaryOk)
        assert.equals(10, model.summaryAttention)
        assert.equals(10, model.summaryNoResponse)
    end)

    it("surfaces start errors on the view model", function()
        local model = AddonCheckPanel.BuildViewModel(nil, {
            moduleId = MODULE_ID,
            columns = COLUMNS,
            startError = string.format(L.ADDONCHECK_START_FAILED, "not_raid_leader"),
        })
        assert.equals(string.format(L.ADDONCHECK_START_FAILED, "not_raid_leader"), model.errorText)
    end)
end)

--[[
Manual in-game checks (raid leader):
1. /reload; open /netools → Sszorak.
2. As raid leader, "插件检查" appears next to "创建信号宏"; as member, that row is hidden.
3. Click 插件检查 → popup opens and check starts automatically; progress/rows update as replies arrive.
4. Click 插件检查 again (or reopen) to recheck; prior values show with （上次） until refreshed.
5. Demote raid lead while popup is open; popup closes.
6. Filter 仅异常 hides OK rows.
]]
