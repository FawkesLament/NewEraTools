local _, ns = ...

local WorldFrameApi = {}
ns.Api.WorldFrame = WorldFrameApi

---The 3D world click host, or nil when it is missing or forbidden.
---@return Frame|nil
function WorldFrameApi.GetFrame()
    local frame = _G.WorldFrame
    if type(frame) ~= "table" then
        return nil
    end
    if type(frame.IsForbidden) == "function" then
        local ok, forbidden = pcall(frame.IsForbidden, frame)
        if ok and forbidden == true then
            return nil
        end
    end
    return frame
end
