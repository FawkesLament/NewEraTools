-- Production api/Spell.lua. Feature specs keep tests/helpers/fakes/Spell.lua.

describe("Spell production", function()
    local saved = {}

    local function SaveGlobals()
        saved.C_Spell = C_Spell
        saved.C_SpellBook = C_SpellBook
        saved.Enum = Enum
    end

    local function Load(player)
        local ns = { Api = { Player = player } }
        assert(loadfile("api/Spell.lua"))("NewEraTools", ns)
        return ns.Api.Spell
    end

    local function Player(classFile, specializationId)
        return {
            GetClassFile = function()
                return classFile
            end,
            GetSpecializationId = function()
                return specializationId
            end,
        }
    end

    before_each(function()
        SaveGlobals()
        C_Spell = nil
        C_SpellBook = nil
        Enum = nil
    end)

    after_each(function()
        C_Spell = saved.C_Spell
        C_SpellBook = saved.C_SpellBook
        Enum = saved.Enum
    end)

    describe("IsKnownByPlayerOrPet", function()
        it("is true when the player or the pet spellbook knows the spell", function()
            C_SpellBook = {
                IsSpellKnown = function(spellId, bank)
                    return spellId == 6552 and bank == nil
                end,
            }
            Enum = { SpellBookSpellBank = { Pet = 2 } }
            local Spell = Load(Player("WARRIOR"))

            assert.is_true(Spell.IsKnownByPlayerOrPet(6552))
            assert.is_false(Spell.IsKnownByPlayerOrPet(19647))

            C_SpellBook.IsSpellKnown = function(spellId, bank)
                return spellId == 19647 and bank == 2
            end
            assert.is_true(Spell.IsKnownByPlayerOrPet(19647))
        end)

        it("is false when the spellbook API is missing", function()
            assert.is_false(Load(Player("WARRIOR")).IsKnownByPlayerOrPet(6552))
        end)
    end)

    describe("GetInterruptName", function()
        local function Names(map)
            return {
                GetSpellName = function(spellId)
                    return map[spellId]
                end,
            }
        end

        it("returns the class interrupt name", function()
            C_Spell = Names({ [6552] = "Pummel" })
            assert.equals("Pummel", Load(Player("WARRIOR")).GetInterruptName())
        end)

        it("prefers the spec interrupt over the class interrupt", function()
            C_Spell = Names({
                [147362] = "Counter Shot",
                [187707] = "Muzzle",
            })
            assert.equals("Muzzle", Load(Player(nil, 255)).GetInterruptName())
            assert.equals("Counter Shot", Load(Player("HUNTER")).GetInterruptName())
            assert.equals("Counter Shot", Load(Player("HUNTER", 253)).GetInterruptName())
        end)

        it("returns nil when the class, spec, or name is missing", function()
            C_Spell = Names({ [6552] = "Pummel" })
            assert.is_nil(Load(Player(nil)).GetInterruptName())
            assert.is_nil(Load(Player("UNKNOWN")).GetInterruptName())

            C_Spell = Names({ [6552] = "" })
            assert.is_nil(Load(Player("WARRIOR")).GetInterruptName())
        end)
    end)
end)
