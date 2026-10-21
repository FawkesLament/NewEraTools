local _, ns = ...

---Pure view-model for AddonCheckPanel (classify, format, sort, filter). No frames.
local L = ns.L
local AddonCheck = ns.AddonCheck
local Icons = ns.Assets.Icons

local Model = {}
ns.AddonCheckPanelModel = Model

---Summary bucket for a member row.
Model.Category = {
    OK = "ok",
    ATTENTION = "attention",
    NO_RESPONSE = "no_response",
}

---Member list filter.
Model.Filter = {
    ALL = "all",
    ISSUES = "issues",
}

---Built-in sort column ids (config columns use ConfigSortKey).
Model.SortColumn = {
    PARTY = "party",
    PLAYER = "player",
    VERSION = "version",
    STATUS = "status",
}

---Sort key for a module config column (1-based index into `columns`).
---@param index integer
---@return string
function Model.ConfigSortKey(index)
    return "config:" .. tostring(index)
end

local CATEGORY_SORT = {
    [Model.Category.ATTENTION] = 1,
    [Model.Category.NO_RESPONSE] = 2,
    [Model.Category.OK] = 3,
}

local SortColumn = Model.SortColumn

---@class AddonCheckPanelColumn
---@field key string  Config snapshot field key.
---@field title string  Column header text.
---@field format fun(value: any): string|nil  Human-readable value; nil/empty → em dash.

---@class AddonCheckPanelMemberRow
---@field key string
---@field party string  Raid party number display (or em dash).
---@field subgroup number|nil  Numeric party for sorting; nil when unknown.
---@field playerName string
---@field classFile string|nil
---@field version string
---@field configValues string[]  Parallel to columns; display strings.
---@field invalidColumns string[]  Column keys flagged by `validator` (may be empty).
---@field statusLabel string  Tooltip / accessible detail for the status icon.
---@field statusIcon string  Texture path for the status column.
---@field category string  AddonCheckPanel.Category.*
---@field sortName string
---@field raidIndex integer  1-based index in the session roster (raid order).

---@class AddonCheckPanelViewModel
---@field hasSession boolean
---@field running boolean
---@field buttonLabel string
---@field progressText string|nil
---@field summaryOk integer
---@field summaryAttention integer
---@field summaryNoResponse integer
---@field emptyText string|nil
---@field errorText string|nil
---@field rows AddonCheckPanelMemberRow[]
---@field visibleRows AddonCheckPanelMemberRow[]

---Comparable value for one row under `sortKey` (string or number).
---@param row AddonCheckPanelMemberRow
---@param sortKey string
---@return string|number
local function SortValue(row, sortKey)
    if sortKey == SortColumn.PARTY then
        return row.subgroup or 99
    end
    if sortKey == SortColumn.PLAYER then
        return row.sortName
    end
    if sortKey == SortColumn.VERSION then
        return string.lower(row.version or "")
    end
    if sortKey == SortColumn.STATUS then
        return CATEGORY_SORT[row.category] or 9
    end
    local configIndex = tonumber(string.match(sortKey, "^config:(%d+)$"))
    if configIndex then
        return string.lower(row.configValues[configIndex] or "")
    end
    return row.sortName
end

---@param a AddonCheckPanelMemberRow
---@param b AddonCheckPanelMemberRow
---@param sortKey string
---@param ascending boolean
---@return boolean
local function CompareRowsByColumn(a, b, sortKey, ascending)
    local av, bv = SortValue(a, sortKey), SortValue(b, sortKey)
    if av ~= bv then
        if ascending then
            return av < bv
        end
        return av > bv
    end
    -- Stable tie-break: keep raid order, then name.
    if a.raidIndex ~= b.raidIndex then
        return a.raidIndex < b.raidIndex
    end
    if a.sortName ~= b.sortName then
        return a.sortName < b.sortName
    end
    return a.key < b.key
end

---@param value any
---@return string
local function EmDashIfEmpty(value)
    if value == nil then
        return L.ADDONCHECK_EM_DASH
    end
    if type(value) == "string" and value == "" then
        return L.ADDONCHECK_EM_DASH
    end
    return tostring(value)
end

---@param fullName string|nil
---@param shortName string|nil
---@return string
local function DisplayPlayerName(fullName, shortName)
    if type(shortName) == "string" and shortName ~= "" then
        return shortName
    end
    if type(fullName) ~= "string" or fullName == "" then
        return L.ADDONCHECK_EM_DASH
    end
    return fullName:match("^([^%-]+)") or fullName
end

---Normalizes validator output to a list of column keys (nil/empty → no issues).
---@param flagged string[]|nil
---@return string[]
local function NormalizeInvalidColumns(flagged)
    if type(flagged) ~= "table" or #flagged == 0 then
        return {}
    end
    local keys = {}
    for i = 1, #flagged do
        local key = flagged[i]
        if type(key) == "string" and key ~= "" then
            keys[#keys + 1] = key
        end
    end
    return keys
end

---@param result AddonCheckRequestResult
---@param moduleId string
---@param baselineVersion string|nil
---@param localConfig any
---@param isConfigMismatch fun(config: any, localConfig: any): boolean|nil
---@param validator fun(config: any, localConfig: any): string[]|nil
---@return string category
---@return string statusLabel
---@return string statusIcon
---@return string[] invalidColumns
local function ClassifyResult(result, moduleId, baselineVersion, localConfig, isConfigMismatch, validator)
    local emptyInvalid = {}
    local state = result.state
    if state == AddonCheck.State.PENDING then
        return Model.Category.NO_RESPONSE, L.ADDONCHECK_STATUS_PENDING, Icons.READY_CHECK_WAITING, emptyInvalid
    end
    if state == AddonCheck.State.TIMED_OUT then
        return Model.Category.NO_RESPONSE, L.ADDONCHECK_STATUS_TIMEOUT, Icons.READY_CHECK_NOT_READY, emptyInvalid
    end
    if state == AddonCheck.State.INCOMPATIBLE then
        return Model.Category.ATTENTION, L.ADDONCHECK_STATUS_INCOMPATIBLE, Icons.WARNING, emptyInvalid
    end
    if state == AddonCheck.State.FAILED then
        if result.message == "provider_failed" then
            return Model.Category.ATTENTION, L.ADDONCHECK_STATUS_PROVIDER_ERROR, Icons.WARNING, emptyInvalid
        end
        return Model.Category.ATTENTION, L.ADDONCHECK_STATUS_FAILED, Icons.WARNING, emptyInvalid
    end
    if state == AddonCheck.State.RESPONDED then
        local config = result.configs and result.configs[moduleId]
        if result.message == "unknown_module" or config == nil then
            return Model.Category.ATTENTION, L.ADDONCHECK_STATUS_UNSUPPORTED, Icons.WARNING, emptyInvalid
        end
        local invalidColumns = NormalizeInvalidColumns(validator and validator(config, localConfig) or nil)
        if #invalidColumns > 0 then
            return Model.Category.ATTENTION, L.ADDONCHECK_STATUS_VALIDATION, Icons.WARNING, invalidColumns
        end
        if isConfigMismatch and localConfig ~= nil and isConfigMismatch(config, localConfig) then
            return Model.Category.ATTENTION, L.ADDONCHECK_STATUS_CONFIG_MISMATCH, Icons.WARNING, emptyInvalid
        end
        if baselineVersion and result.version and result.version ~= "" and result.version ~= baselineVersion then
            return Model.Category.ATTENTION, L.ADDONCHECK_STATUS_VERSION_DIFFERS, Icons.WARNING, emptyInvalid
        end
        return Model.Category.OK, L.ADDONCHECK_STATUS_OK, Icons.READY_CHECK_READY, emptyInvalid
    end
    return Model.Category.ATTENTION, L.ADDONCHECK_STATUS_FAILED, Icons.WARNING, emptyInvalid
end

---@param columns AddonCheckPanelColumn[]
---@param config any
---@return string[]
local function FormatConfigValues(columns, config)
    local values = {}
    for i = 1, #columns do
        local column = columns[i]
        -- Do not use `and`/`or` for lookup: false config values must not become nil.
        local raw = nil
        if type(config) == "table" then
            raw = config[column.key]
        end
        local formatted = column.format and column.format(raw) or nil
        if formatted == nil or formatted == "" then
            values[i] = L.ADDONCHECK_EM_DASH
        else
            values[i] = formatted
        end
    end
    return values
end

---@param session AddonCheckSession
---@return table<string, AddonCheckRosterMember>
local function RosterByKey(session)
    local byKey = {}
    if session.roster then
        for i = 1, #session.roster do
            local member = session.roster[i]
            byKey[member.key] = member
        end
    end
    return byKey
end

---Builds a pure view-model for one AddonCheck session (or empty state). Unit-testable without frames.
---@param session AddonCheckSession|nil
---@param options { moduleId: string, columns: AddonCheckPanelColumn[], filter: string|nil, isConfigMismatch: fun(config: any, localConfig: any): boolean|nil, validator: fun(config: any, localConfig: any): string[]|nil, startError: string|nil, sortKey: string|nil, sortAscending: boolean|nil }
---@return AddonCheckPanelViewModel
function Model.BuildViewModel(session, options)
    local moduleId = options.moduleId
    local columns = options.columns
    local filter = options.filter or Model.Filter.ALL
    local startError = options.startError
    local sortKey = options.sortKey
    local sortAscending = options.sortAscending ~= false

    ---@type AddonCheckPanelViewModel
    local model = {
        hasSession = session ~= nil,
        running = session ~= nil and session.status == AddonCheck.SessionStatus.RUNNING,
        buttonLabel = session ~= nil and L.ADDONCHECK_RECHECK or L.ADDONCHECK_CHECK,
        progressText = nil,
        summaryOk = 0,
        summaryAttention = 0,
        summaryNoResponse = 0,
        emptyText = nil,
        errorText = startError,
        rows = {},
        visibleRows = {},
    }

    if not session then
        model.emptyText = L.ADDONCHECK_EMPTY
        return model
    end

    local baselineVersion = session.version
    local localConfig = session.localConfigs and session.localConfigs[moduleId]
    local rosterByKey = RosterByKey(session)
    local responded = 0
    local total = 0

    ---@param key string
    ---@param result AddonCheckRequestResult
    ---@param member AddonCheckRosterMember|nil
    ---@param raidIndex integer
    local function AppendRow(key, result, member, raidIndex)
        total = total + 1
        if result.state ~= AddonCheck.State.PENDING then
            responded = responded + 1
        end
        local category, statusLabel, statusIcon, invalidColumns =
            ClassifyResult(result, moduleId, baselineVersion, localConfig, options.isConfigMismatch, options.validator)
        local config = result.configs and result.configs[moduleId]
        local playerName = DisplayPlayerName(result.playerName or (member and member.fullName), member and member.name)
        local subgroup = member and member.subgroup
        local party = (type(subgroup) == "number") and tostring(subgroup) or L.ADDONCHECK_EM_DASH
        local row = {
            key = key,
            party = party,
            subgroup = type(subgroup) == "number" and subgroup or nil,
            playerName = playerName,
            classFile = member and member.classFile,
            version = EmDashIfEmpty(result.version),
            configValues = FormatConfigValues(columns, config),
            invalidColumns = invalidColumns,
            statusLabel = statusLabel,
            statusIcon = statusIcon,
            category = category,
            sortName = string.lower(playerName),
            raidIndex = raidIndex,
        }
        model.rows[#model.rows + 1] = row
        if category == Model.Category.OK then
            model.summaryOk = model.summaryOk + 1
        elseif category == Model.Category.ATTENTION then
            model.summaryAttention = model.summaryAttention + 1
        else
            model.summaryNoResponse = model.summaryNoResponse + 1
        end
    end

    -- Default list order matches the raid roster snapshot; no status-based reordering.
    local seen = {}
    if session.roster then
        for i = 1, #session.roster do
            local member = session.roster[i]
            local result = session.results[member.key]
            if result then
                seen[member.key] = true
                AppendRow(member.key, result, member, i)
            end
        end
    end
    for key, result in pairs(session.results) do
        if not seen[key] then
            AppendRow(key, result, rosterByKey[key], #model.rows + 1)
        end
    end

    if sortKey then
        table.sort(model.rows, function(a, b)
            return CompareRowsByColumn(a, b, sortKey, sortAscending)
        end)
    end

    for i = 1, #model.rows do
        local row = model.rows[i]
        if filter == Model.Filter.ALL or row.category ~= Model.Category.OK then
            model.visibleRows[#model.visibleRows + 1] = row
        end
    end

    model.progressText = string.format(L.ADDONCHECK_PROGRESS, responded, total)
    if total == 0 then
        model.emptyText = L.ADDONCHECK_EMPTY
    end
    return model
end

---Indexes row display data by member key.
---@param rows AddonCheckPanelMemberRow[]
---@return table<string, AddonCheckPanelMemberRow>
function Model.IndexRowsByKey(rows)
    local byKey = {}
    for i = 1, #rows do
        local row = rows[i]
        byKey[row.key] = row
    end
    return byKey
end
