describe("PendingClock", function()
    local ns, PendingClock, Combat

    local function FakeFrame(parent)
        local frame = { parent = parent, shown = true }
        function frame:GetParent()
            return self.parent
        end
        function frame:SetSize() end
        function frame:SetPoint() end
        function frame:EnableMouse() end
        function frame:CreateTexture()
            return {
                SetAllPoints = function() end,
                SetAtlas = function() end,
                SetVertexColor = function() end,
            }
        end
        function frame:Hide()
            self.shown = false
        end
        function frame:Show()
            self.shown = true
        end
        return frame
    end

    before_each(function()
        Combat = dofile("tests/helpers/fakes/Combat.lua")()
        ns = {
            L = { SETTINGS_PENDING_COMBAT = "after combat" },
            Assets = {
                Icons = { CLOCK = "clock" },
                Colors = { TEXT_MUTED = { r = 1, g = 1, b = 1 } },
            },
            Widgets = { AttachTooltip = function() end },
            Api = { Combat = Combat },
        }
        CreateFrame = function()
            return FakeFrame()
        end
        assert(loadfile("ui/PendingClock.lua"))("NewEraTools", ns)
        PendingClock = ns.PendingClock
    end)

    it("starts hidden", function()
        local label = FakeFrame(FakeFrame())
        local clock = PendingClock.Attach(label)
        assert.is_false(clock.shown)
        assert.is_false(PendingClock.IsPending(clock))
    end)

    it("applies immediately outside combat", function()
        local label = FakeFrame(FakeFrame())
        local clock = PendingClock.Attach(label)
        local applied = 0
        local flushed = 0
        local deferred = PendingClock.Defer(clock, function()
            applied = applied + 1
        end, function()
            flushed = flushed + 1
        end)
        assert.is_false(deferred)
        assert.equals(1, applied)
        assert.equals(0, flushed)
        assert.is_false(clock.shown)
    end)

    it("shows the clock in combat and applies once combat ends", function()
        Combat.inCombat = true
        local label = FakeFrame(FakeFrame())
        local clock = PendingClock.Attach(label)
        local applied = 0
        local flushed = 0
        assert.is_true(PendingClock.Defer(clock, function()
            applied = applied + 1
        end, function()
            flushed = flushed + 1
        end))
        assert.equals(0, applied)
        assert.is_true(clock.shown)
        assert.is_true(PendingClock.IsPending(clock))

        -- A second edit of the same setting does not queue another apply.
        assert.is_true(PendingClock.Defer(clock, function()
            applied = applied + 1
        end, function()
            flushed = flushed + 1
        end))

        Combat.FireLeave()
        assert.equals(1, applied)
        assert.equals(1, flushed)
    end)

    it("runs one shared flush after every deferred apply", function()
        Combat.inCombat = true
        local first = PendingClock.Attach(FakeFrame(FakeFrame()))
        local second = PendingClock.Attach(FakeFrame(FakeFrame()))
        local applied = {}
        local flushed = 0
        local function OnFlushed()
            flushed = flushed + 1
        end
        PendingClock.Defer(first, function()
            applied[#applied + 1] = "scale"
        end, OnFlushed)
        PendingClock.Defer(second, function()
            applied[#applied + 1] = "rotation"
        end, OnFlushed)
        Combat.FireLeave()
        assert.same({ "scale", "rotation" }, applied)
        assert.equals(1, flushed)
    end)
end)
