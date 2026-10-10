return function()
    local Timer = { now = 0, pending = {} }

    function Timer.After(seconds, callback)
        table.insert(Timer.pending, { due = Timer.now + seconds, callback = callback })
    end

    ---Fires every callback that is due at or before `Timer.now`, including ones they queue.
    local function FireDue()
        local guard = 0
        while guard < 10000 do
            guard = guard + 1
            local nextIndex
            for index, item in ipairs(Timer.pending) do
                if item.due <= Timer.now and (not nextIndex or item.due < Timer.pending[nextIndex].due) then
                    nextIndex = index
                end
            end
            if not nextIndex then
                return
            end
            table.remove(Timer.pending, nextIndex).callback()
        end
        error("Timer.FireDue: too many callbacks (possible tight loop)")
    end

    ---Advances fake time and runs callbacks that become due.
    function Timer.Advance(seconds)
        Timer.now = Timer.now + seconds
        FireDue()
    end

    ---Runs queued callbacks regardless of due time, including ones they queue, until none remain.
    ---Only safe for finite chains; repeating schedulers must use Advance instead.
    function Timer.RunPending()
        while #Timer.pending > 0 do
            table.remove(Timer.pending, 1).callback()
        end
    end

    return Timer
end
