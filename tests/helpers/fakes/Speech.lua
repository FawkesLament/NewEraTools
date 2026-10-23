return function()
    local Speech = {
        ---@type string[]
        spoken = {},
    }

    ---@param text any
    ---@return boolean
    function Speech.IsPlainText(text)
        if issecretvalue and issecretvalue(text) then
            return false
        end
        return type(text) == "string" and text ~= ""
    end

    ---@param text string
    function Speech.Say(text)
        if not Speech.IsPlainText(text) then
            return
        end
        Speech.spoken[#Speech.spoken + 1] = text
    end

    return Speech
end
