local _, ns = ...

---AddonCheck-owned wire payload and config-value codecs (not part of MessageProtocol).
local Codec = {}
ns.AddonCheckCodec = Codec

Codec.PAYLOAD_VERSION = "1"
Codec.MAX_MODULE_ID_LENGTH = 48

local MODULE_ID_PATTERN = "^[A-Za-z0-9_.-]+$"

---@param moduleId string
---@return boolean
function Codec.IsValidModuleId(moduleId)
    return type(moduleId) == "string"
        and #moduleId >= 1
        and #moduleId <= Codec.MAX_MODULE_ID_LENGTH
        and moduleId:find(MODULE_ID_PATTERN) ~= nil
end

---Tagged value codec for config snapshots. Strings are length-prefixed so `|` and binary-ish bytes are fine.
---@param value any
---@return string|nil
---@return string|nil reason
function Codec.EncodeValue(value)
    local valueType = type(value)
    if value == nil then
        return "N"
    elseif valueType == "boolean" then
        return value and "B1" or "B0"
    elseif valueType == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return nil, "invalid_number"
        end
        return "D" .. tostring(value) .. ";"
    elseif valueType == "string" then
        return "S" .. #value .. ":" .. value
    elseif valueType == "table" then
        local parts = {}
        for key, nested in pairs(value) do
            local encodedKey, keyReason = Codec.EncodeValue(key)
            if not encodedKey then
                return nil, keyReason or "serialize_failed"
            end
            local encodedNested, nestedReason = Codec.EncodeValue(nested)
            if not encodedNested then
                return nil, nestedReason or "serialize_failed"
            end
            parts[#parts + 1] = encodedKey .. encodedNested
        end
        return "T" .. #parts .. ":" .. table.concat(parts)
    end
    return nil, "unsupported_type"
end

---@param encoded string
---@param index integer
---@return any|nil value
---@return integer|nil nextIndex
---@return string|nil reason
function Codec.DecodeValue(encoded, index)
    local tag = encoded:sub(index, index)
    if tag == "" then
        return nil, nil, "truncated"
    end
    if tag == "N" then
        return nil, index + 1
    end
    if tag == "B" then
        local bit = encoded:sub(index + 1, index + 1)
        if bit == "1" then
            return true, index + 2
        elseif bit == "0" then
            return false, index + 2
        end
        return nil, nil, "invalid_bool"
    end
    if tag == "D" then
        local stop = encoded:find(";", index + 1, true)
        if not stop then
            return nil, nil, "invalid_number"
        end
        local number = tonumber(encoded:sub(index + 1, stop - 1))
        if not number then
            return nil, nil, "invalid_number"
        end
        return number, stop + 1
    end
    if tag == "S" then
        local colon = encoded:find(":", index + 1, true)
        if not colon then
            return nil, nil, "invalid_string"
        end
        local length = tonumber(encoded:sub(index + 1, colon - 1))
        if not length or length < 0 then
            return nil, nil, "invalid_string"
        end
        local start = colon + 1
        local stop = start + length - 1
        if stop > #encoded then
            return nil, nil, "truncated"
        end
        return encoded:sub(start, stop), stop + 1
    end
    if tag == "T" then
        local colon = encoded:find(":", index + 1, true)
        if not colon then
            return nil, nil, "invalid_table"
        end
        local count = tonumber(encoded:sub(index + 1, colon - 1))
        if not count or count < 0 or count ~= math.floor(count) then
            return nil, nil, "invalid_table"
        end
        local cursor = colon + 1
        local tableValue = {}
        for _ = 1, count do
            local key, afterKey, keyReason = Codec.DecodeValue(encoded, cursor)
            if keyReason then
                return nil, nil, keyReason
            end
            local nested, afterNested, nestedReason = Codec.DecodeValue(encoded, afterKey)
            if nestedReason then
                return nil, nil, nestedReason
            end
            tableValue[key] = nested
            cursor = afterNested
        end
        return tableValue, cursor
    end
    return nil, nil, "unsupported_type"
end

---@param moduleId string
---@return string|nil
function Codec.EncodeRequestPayload(moduleId)
    if not Codec.IsValidModuleId(moduleId) then
        return nil
    end
    return Codec.PAYLOAD_VERSION .. "|" .. moduleId
end

---@param payload string
---@return string|nil moduleId
function Codec.DecodeRequestPayload(payload)
    if type(payload) ~= "string" then
        return nil
    end
    local version, moduleId = payload:match("^([^|]*)|(.*)$")
    if version ~= Codec.PAYLOAD_VERSION or not Codec.IsValidModuleId(moduleId) then
        return nil
    end
    return moduleId
end

---@param status string
---@param moduleId string
---@param version string
---@param body string
---@return string|nil
function Codec.EncodeResponsePayload(status, moduleId, version, body)
    if type(status) ~= "string"
        or status == ""
        or status:find("|", 1, true)
        or not Codec.IsValidModuleId(moduleId)
        or type(version) ~= "string"
        or version == ""
        or version:find("|", 1, true)
        or type(body) ~= "string"
        or body:find("\0", 1, true)
    then
        return nil
    end
    return table.concat({ Codec.PAYLOAD_VERSION, status, moduleId, version, body }, "|")
end

---@class AddonCheckResponsePayload
---@field status string
---@field moduleId string
---@field version string
---@field body string

---@param payload string
---@return AddonCheckResponsePayload|nil
function Codec.DecodeResponsePayload(payload)
    if type(payload) ~= "string" then
        return nil
    end
    local version, status, moduleId, addonVersion, body = payload:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
    if version ~= Codec.PAYLOAD_VERSION
        or type(status) ~= "string"
        or status == ""
        or not Codec.IsValidModuleId(moduleId)
        or type(addonVersion) ~= "string"
        or addonVersion == ""
        or body == nil
    then
        return nil
    end
    if status ~= "ok" and status ~= "unsupported" and status ~= "failed" then
        return nil
    end
    return {
        status = status,
        moduleId = moduleId,
        version = addonVersion,
        body = body,
    }
end
