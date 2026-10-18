local Harness = require("helpers.aura_tracker")

describe("AuraTracker settings list", function()
    local ns, AuraTracker, Activation, UI
    local savedCreateFrame
    local buttons, structureClears, listSyncs, paints, bar, scroll

    local function NewFrame(kind)
        local frame = { kind = kind, shown = true, height = 0, width = 0 }

        function frame:SetHeight(height)
            self.height = height
        end
        function frame:GetHeight()
            return self.height
        end
        function frame:SetWidth(width)
            self.width = width
        end
        function frame:GetWidth()
            return self.width
        end
        function frame:SetSize(width, height)
            self.width = width
            self.height = height
        end
        function frame:ClearAllPoints() end
        function frame:SetPoint() end
        function frame:Show()
            self.shown = true
        end
        function frame:Hide()
            self.shown = false
        end
        function frame:SetParent(parent)
            self.parent = parent
        end
        function frame:GetParent()
            return self.parent
        end
        function frame:SetScript() end
        function frame:HookScript() end
        function frame:SetText() end
        function frame:SetAlpha() end
        function frame:SetFontObject() end
        function frame:SetJustifyH() end
        function frame:SetJustifyV() end
        function frame:SetWordWrap() end
        function frame:SetTextColor() end
        function frame:GetStringHeight()
            return 0
        end
        function frame:SetEnabled(enabled)
            self.enabled = enabled == true
        end
        function frame:SetChecked() end
        function frame:GetChecked()
            return false
        end
        function frame:GetUnboundedStringWidth()
            return 0
        end
        function frame:SetTexture() end
        function frame:CreateTexture()
            return NewFrame("Texture")
        end
        function frame:GetObjectType()
            return kind
        end
        return frame
    end

    local function LoadList()
        savedCreateFrame = CreateFrame
        buttons = 0
        structureClears = 0
        listSyncs = 0
        paints = 0
        bar = { full = 0, ids = 0, appearances = 0 }
        CreateFrame = function(kind, _, parent)
            local frame = NewFrame(kind)
            frame:SetParent(parent)
            if kind == "Button" then
                buttons = buttons + 1
            end
            return frame
        end

        assert(loadfile("ui/Layout.lua"))("NewEraTools", ns)
        local stack = ns.Layout.Stack
        function ns.Layout.Stack(container, options)
            local created = stack(container, options)
            local clear = created.Clear
            function created:Clear(...)
                structureClears = structureClears + 1
                return clear(self, ...)
            end
            return created
        end

        ns.Widgets = {
            ApplyBackdrop = function()
                paints = paints + 1
            end,
            AddHoverHighlight = function() end,
            CreateCheckbox = function()
                return NewFrame("CheckButton")
            end,
            CreateLabel = function()
                return NewFrame("FontString")
            end,
            CreateButton = function()
                return NewFrame("Button")
            end,
        }
        ns.CollapsibleSection = {
            Create = function(parentStack)
                local section = NewFrame("Frame")
                section.content = NewFrame("Frame")
                parentStack:Add(section, 1)
                function section:SetBadge() end
                function section:SetContentHeight(height)
                    parentStack:SetEntryHeight(section, height)
                end
                return section
            end,
        }
        ns.AuraTrackerBarUI = {
            Update = function(trackerId)
                if trackerId == nil then
                    bar.full = bar.full + 1
                else
                    bar.ids = bar.ids + 1
                end
            end,
            ApplyAppearance = function()
                bar.appearances = bar.appearances + 1
            end,
            HasPendingAppearance = function()
                return false
            end,
        }

        assert(loadfile("modules/combat/aura_tracker/ui/List.lua"))("NewEraTools", ns)
        assert(loadfile("modules/combat/aura_tracker/ui/Panel.lua"))("NewEraTools", ns)
        UI = ns.AuraTrackerUI
        UI.RefreshPendingClocks = function() end
        local syncList = UI.SyncTrackerList
        function UI.SyncTrackerList(...)
            listSyncs = listSyncs + 1
            return syncList(...)
        end

        scroll = NewFrame("ScrollFrame")
        scroll.vertical = 0
        scroll.sets = 0
        function scroll:GetObjectType()
            return "ScrollFrame"
        end
        function scroll:GetVerticalScroll()
            return self.vertical
        end
        function scroll:SetVerticalScroll(value)
            self.sets = self.sets + 1
            self.vertical = value
        end
        function scroll:GetVerticalScrollRange()
            return 1000
        end

        local settings = NewFrame("Frame")
        settings:SetParent(scroll)
        function settings:SetContentHeight() end
        local content = ns.Layout.Stack(settings)
        local list = NewFrame("Frame")
        local emptyEditor = NewFrame("Frame")
        local editor = NewFrame("Frame")
        content:Add(NewFrame("Spacer"), 100)
        content:Add(list, 0)
        content:Add(emptyEditor, 0)
        content:Add(editor, 0)
        UI.settingsContainer = settings
        UI.contentBody = content
        UI.listHost = list
        UI.emptyEditorHost = emptyEditor
        UI.editorHost = editor
    end

    before_each(function()
        ns, AuraTracker, Activation = Harness.Start()
        LoadList()
    end)

    after_each(function()
        CreateFrame = savedCreateFrame
    end)

    local function Row(id)
        return UI.trackerRows[id]
    end

    it("repaints one row when the tracker stays in its group", function()
        local first = AuraTracker:AddTracker()
        local second = AuraTracker:AddTracker()
        local firstFrame = Row(first).frame
        local secondFrame = Row(second).frame
        local clears = structureClears
        local syncs = listSyncs
        local scrollSets = scroll.sets
        local painted = paints
        local full = bar.full
        local idUpdates = bar.ids
        local created = buttons

        AuraTracker:SetSpellId(first, 774)

        assert.is_true(Row(first).frame == firstFrame)
        assert.is_true(Row(second).frame == secondFrame)
        assert.equals(created, buttons)
        assert.equals(clears, structureClears)
        assert.equals(syncs, listSyncs)
        assert.equals(scrollSets, scroll.sets)
        assert.equals(0, scroll.vertical)
        assert.equals(painted + 1, paints)
        assert.equals(full, bar.full)
        assert.equals(idUpdates + 1, bar.ids)
    end)

    it("adds a row without copying an existing one, and drops the row it removes", function()
        local kept = AuraTracker:AddTracker()
        local keptFrame = Row(kept).frame
        local created = buttons
        local parent = keptFrame:GetParent()

        local added = AuraTracker:AddTracker()
        assert.equals(created + 1, buttons)
        assert.is_true(Row(kept).frame == keptFrame)
        assert.is_true(keptFrame:GetParent() == parent)
        assert.is_true(Row(added).frame:GetParent() == parent)
        assert.is_true(Row(added).frame ~= keptFrame)

        local removedFrame = Row(added).frame
        local clears = structureClears
        AuraTracker:RemoveTracker(added)
        assert.is_nil(Row(added))
        assert.is_false(removedFrame.shown)
        assert.is_nil(removedFrame:GetParent())
        assert.is_true(Row(kept).frame == keptFrame)
        assert.equals(created + 1, buttons)
        assert.is_true(structureClears > clears)
        assert.equals(0, scroll.sets)
    end)

    it("moves a tracker to the inactive group without creating a row", function()
        local moving = AuraTracker:AddTracker()
        local staying = AuraTracker:AddTracker()
        local movingFrame = Row(moving).frame
        local stayingFrame = Row(staying).frame
        local activeParent = stayingFrame:GetParent()
        local created = buttons
        local clears = structureClears
        local scrollSets = scroll.sets

        AuraTracker:SetActivationScope(moving, Activation.SPECIALIZATION, 64)

        assert.is_true(Row(moving).frame == movingFrame)
        assert.is_true(Row(staying).frame == stayingFrame)
        assert.equals(created, buttons)
        assert.is_true(stayingFrame:GetParent() == activeParent)
        assert.is_true(movingFrame:GetParent() == UI.inactiveGroup.content)
        assert.is_true(movingFrame:GetParent() ~= activeParent)
        assert.is_true(structureClears > clears)
        assert.equals(scrollSets, scroll.sets)
        assert.equals(0, scroll.vertical)
    end)

    it("adjusts scroll only when the list sits above the viewport", function()
        AuraTracker:AddTracker()
        AuraTracker:AddTracker()
        assert.equals(0, scroll.sets)
        local anchor = UI.contentBody:GetOffset(UI.listHost)
        local oldHeight = UI.listHost:GetHeight()
        scroll.vertical = anchor + oldHeight

        AuraTracker:AddTracker()

        assert.equals(1, scroll.sets)
        assert.equals(anchor + UI.listHost:GetHeight(), scroll.vertical)
    end)

    it("updates bar appearance without rebuilding the list or moving scroll", function()
        local id = AuraTracker:AddTracker()
        local frame = Row(id).frame
        local clears = structureClears
        local syncs = listSyncs
        local scrollSets = scroll.sets
        local painted = paints
        local full = bar.full
        local ids = bar.ids
        local created = buttons

        AuraTracker:SetWidth(id, 240)

        assert.equals(1, bar.appearances)
        assert.equals(full, bar.full)
        assert.equals(ids, bar.ids)
        assert.equals(syncs, listSyncs)
        assert.equals(clears, structureClears)
        assert.equals(created, buttons)
        assert.equals(painted, paints)
        assert.equals(scrollSets, scroll.sets)
        assert.is_true(Row(id).frame == frame)
    end)

    it("refreshes the live bar without rebuilding the list", function()
        local id = AuraTracker:AddTracker()
        AuraTracker:SetEnabled(true)
        AuraTracker:SetUnit(id, ns.AuraTrackerSchema.UNIT_TARGET)
        local clears = structureClears
        local syncs = listSyncs
        local scrollSets = scroll.sets
        local painted = paints
        local created = buttons
        local full = bar.full
        local ids = bar.ids
        local appearances = bar.appearances

        AuraTracker:ListenForUnitContext()
        ns.Api.GameEvents.Fire("PLAYER_TARGET_CHANGED")
        ns.Api.Timer.RunPending()

        assert.equals(full + 2, bar.full)
        assert.equals(ids, bar.ids)
        assert.equals(appearances, bar.appearances)
        assert.equals(syncs, listSyncs)
        assert.equals(clears, structureClears)
        assert.equals(created, buttons)
        assert.equals(painted, paints)
        assert.equals(scrollSets, scroll.sets)
    end)
end)
