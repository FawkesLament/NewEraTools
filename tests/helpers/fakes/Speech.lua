return function()
    local Speech = {
        ---@type string[]
        spoken = {},
    }

    ---@param text string
    function Speech.Say(text)
        Speech.spoken[#Speech.spoken + 1] = text
    end

    return Speech
end
