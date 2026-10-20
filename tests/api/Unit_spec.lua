-- Production api/Unit.lua. Feature specs keep tests/helpers/fakes/Unit.lua.
-- Class-color and UnitClassBase availability are captured when the file loads.

local SECRET = {}

local function Load()
    local ns = { Api = {} }
    assert(loadfile("api/Unit.lua"))("NewEraTools", ns)
    return ns.Api.Unit
end

local function InstallClient()
    issecret = function(value)
        return value == SECRET
    end
    GetNormalizedRealmName = function()
        return "ProbeRealm"
    end
    UnitExists = function()
        return false
    end
    UnitCanAssist = function()
        return false
    end
    UnitCanAttack = function()
        return false
    end
    UnitGUID = function()
        return nil
    end
    UnitClass = function()
        return nil, nil
    end
    UnitClassBase = nil
    C_ClassColor = nil
    RAID_CLASS_COLORS = nil
end

describe("Unit production", function()
    local saved = {}

    local function SaveGlobals()
        saved.issecret = issecret
        saved.GetNormalizedRealmName = GetNormalizedRealmName
        saved.UnitExists = UnitExists
        saved.UnitCanAssist = UnitCanAssist
        saved.UnitCanAttack = UnitCanAttack
        saved.UnitGUID = UnitGUID
        saved.UnitClass = UnitClass
        saved.UnitClassBase = UnitClassBase
        saved.C_ClassColor = C_ClassColor
        saved.RAID_CLASS_COLORS = RAID_CLASS_COLORS
    end

    before_each(function()
        SaveGlobals()
        InstallClient()
    end)

    after_each(function()
        issecret = saved.issecret
        GetNormalizedRealmName = saved.GetNormalizedRealmName
        UnitExists = saved.UnitExists
        UnitCanAssist = saved.UnitCanAssist
        UnitCanAttack = saved.UnitCanAttack
        UnitGUID = saved.UnitGUID
        UnitClass = saved.UnitClass
        UnitClassBase = saved.UnitClassBase
        C_ClassColor = saved.C_ClassColor
        RAID_CLASS_COLORS = saved.RAID_CLASS_COLORS
    end)

    describe("GetFullName", function()
        it("appends the realm for a same-realm name and leaves a qualified name alone", function()
            local Unit = Load()
            assert.equals("Bob-ProbeRealm", Unit.GetFullName("Bob"))
            assert.equals("Bob-Other", Unit.GetFullName("Bob-Other"))

            GetNormalizedRealmName = function()
                return nil
            end
            assert.equals("Bob-", Unit.GetFullName("Bob"))
        end)
    end)

    describe("Exists", function()
        it("accepts true and 1 and rejects other plain results", function()
            local Unit = Load()
            UnitExists = function(unit)
                if unit == "yes" then
                    return true
                end
                if unit == "one" then
                    return 1
                end
                if unit == "zero" then
                    return 0
                end
                if unit == "no" then
                    return false
                end
                return nil
            end
            assert.is_true(Unit.Exists("yes"))
            assert.is_true(Unit.Exists("one"))
            assert.is_false(Unit.Exists("zero"))
            assert.is_false(Unit.Exists("no"))
            assert.is_false(Unit.Exists("missing"))
            assert.is_false(Unit.Exists(""))
            assert.is_false(Unit.Exists(nil))
        end)

        it("fails closed when the token or the result is secret", function()
            local Unit = Load()
            local queried = 0
            UnitExists = function()
                queried = queried + 1
                return SECRET
            end
            assert.is_false(Unit.Exists(SECRET))
            assert.equals(0, queried)
            assert.is_false(Unit.Exists("player"))
            assert.equals(1, queried)
        end)
    end)

    describe("CanPlayerAssist", function()
        local calls

        local function Assist(fourArg, twoArg)
            calls = {}
            UnitExists = function(unit)
                return unit == "target"
            end
            UnitCanAssist = function(_, unit, immune, uninteractable)
                calls[#calls + 1] = { unit = unit, immune = immune, uninteractable = uninteractable }
                if immune ~= nil then
                    if fourArg == "error" then
                        error("secret call failed")
                    end
                    return fourArg
                end
                return twoArg
            end
        end

        it("returns nil for a missing unit and does not call UnitCanAssist", function()
            local Unit = Load()
            local called = false
            UnitCanAssist = function()
                called = true
            end
            assert.is_nil(Unit.CanPlayerAssist("target"))
            assert.is_nil(Unit.CanPlayerAssist(""))
            assert.is_false(called)
        end)

        it("keeps a plain four-argument result and does not fall back", function()
            local Unit = Load()
            Assist(true, false)
            assert.is_true(Unit.CanPlayerAssist("target"))
            assert.equals(1, #calls)
            assert.is_true(calls[1].immune)
            assert.is_true(calls[1].uninteractable)

            Assist(1, false)
            assert.is_true(Unit.CanPlayerAssist("target"))
            assert.equals(1, #calls)

            Assist(false, true)
            assert.is_false(Unit.CanPlayerAssist("target"))
            assert.equals(1, #calls)

            Assist(0, true)
            assert.is_false(Unit.CanPlayerAssist("target"))
            assert.equals(1, #calls)
        end)

        it("falls back to the two-argument call when the four-argument result is unusable", function()
            local Unit = Load()
            Assist(SECRET, false)
            assert.is_false(Unit.CanPlayerAssist("target"))
            assert.equals(2, #calls)
            assert.is_nil(calls[2].immune)

            Assist(SECRET, 0)
            assert.is_false(Unit.CanPlayerAssist("target"))

            Assist(SECRET, 1)
            assert.is_true(Unit.CanPlayerAssist("target"))

            Assist("maybe", false)
            assert.is_false(Unit.CanPlayerAssist("target"))
            assert.equals(2, #calls)

            Assist("error", true)
            assert.is_true(Unit.CanPlayerAssist("target"))
            assert.equals(2, #calls)

            Assist(SECRET, SECRET)
            assert.is_nil(Unit.CanPlayerAssist("target"))
            assert.equals(2, #calls)
        end)
    end)

    describe("CanPlayerAttack", function()
        it("returns nil for a missing unit and does not call UnitCanAttack", function()
            local Unit = Load()
            local called = false
            UnitCanAttack = function()
                called = true
            end
            assert.is_nil(Unit.CanPlayerAttack("target"))
            assert.is_nil(Unit.CanPlayerAttack(""))
            assert.is_false(called)
        end)

        it("reads a plain UnitCanAttack result and fails closed on secret or junk", function()
            local Unit = Load()
            UnitExists = function(unit)
                return unit == "target"
            end
            UnitCanAttack = function(_, unit)
                assert.equals("target", unit)
                return true
            end
            assert.is_true(Unit.CanPlayerAttack("target"))

            UnitCanAttack = function()
                return 1
            end
            assert.is_true(Unit.CanPlayerAttack("target"))

            UnitCanAttack = function()
                return false
            end
            assert.is_false(Unit.CanPlayerAttack("target"))

            UnitCanAttack = function()
                return 0
            end
            assert.is_false(Unit.CanPlayerAttack("target"))

            UnitCanAttack = function()
                return SECRET
            end
            assert.is_nil(Unit.CanPlayerAttack("target"))

            UnitCanAttack = function()
                error("secret call failed")
            end
            assert.is_nil(Unit.CanPlayerAttack("target"))
        end)
    end)

    describe("GetGUID", function()
        it("returns a plain guid and nil when the guid cannot be compared", function()
            local Unit = Load()
            UnitGUID = function(unit)
                if unit == "player" then
                    return "Player-1"
                end
                if unit == "secret" then
                    return SECRET
                end
                return ""
            end
            assert.equals("Player-1", Unit.GetGUID("player"))
            assert.is_nil(Unit.GetGUID("secret"))
            assert.is_nil(Unit.GetGUID("empty"))
            assert.is_nil(Unit.GetGUID(""))
            assert.is_nil(Unit.GetGUID(SECRET))
            assert.is_nil(Unit.GetGUID(nil))
        end)
    end)

    describe("GetClassFile", function()
        it("uses UnitClass, then UnitClassBase captured at load", function()
            UnitClass = function()
                return "Warrior", "WARRIOR"
            end
            local withClass = Load()
            assert.equals("WARRIOR", withClass.GetClassFile("raid1"))

            UnitClass = function()
                return nil, ""
            end
            UnitClassBase = function()
                return "PRIEST"
            end
            local withBase = Load()
            assert.equals("PRIEST", withBase.GetClassFile("raid2"))

            UnitClassBase = nil
            local withoutBase = Load()
            UnitClassBase = function()
                return "MAGE"
            end
            assert.is_nil(withoutBase.GetClassFile("raid3"))
        end)
    end)

    describe("GetClassColor", function()
        it("caches one rgb table and ignores a class-color API installed after load", function()
            RAID_CLASS_COLORS = {
                MAGE = { r = 0.25, g = 0.78, b = 0.92, extra = true },
            }
            local Unit = Load()
            C_ClassColor = {
                GetClassColor = function()
                    return { r = 1, g = 1, b = 1 }
                end,
            }
            local first = Unit.GetClassColor("MAGE")
            local second = Unit.GetClassColor("MAGE")
            assert.equals(first, second)
            assert.equals(0.25, first.r)
            assert.equals(0.78, first.g)
            assert.equals(0.92, first.b)
            assert.is_nil(first.extra)
            assert.is_nil(Unit.GetClassColor(nil))
            assert.is_nil(Unit.GetClassColor("EVOKER"))
        end)

        it("prefers C_ClassColor when that API exists at load", function()
            C_ClassColor = {
                GetClassColor = function(classFile)
                    assert.equals("WARRIOR", classFile)
                    return { r = 0.78, g = 0.61, b = 0.43, extra = true }
                end,
            }
            RAID_CLASS_COLORS = {
                WARRIOR = { r = 0, g = 0, b = 0 },
            }
            local Unit = Load()
            local color = Unit.GetClassColor("WARRIOR")
            assert.equals(0.78, color.r)
            assert.is_nil(color.extra)
            assert.equals(color, Unit.GetClassColor("WARRIOR"))
        end)
    end)
end)
