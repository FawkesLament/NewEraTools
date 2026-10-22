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

    local function Player(classFile)
        return {
            GetClassFile = function()
                return classFile
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
        it("returns the first known class interrupt name", function()
            C_SpellBook = {
                IsSpellKnown = function(spellId)
                    return spellId == 6552
                end,
            }
            C_Spell = {
                GetSpellName = function(spellId)
                    if spellId == 6552 then
                        return "Pummel"
                    end
                end,
            }

            assert.equals("Pummel", Load(Player("WARRIOR")).GetInterruptName())
        end)

        it("prefers earlier class candidates, including a pet-known Spell Lock", function()
            C_SpellBook = {
                IsSpellKnown = function()
                    return true
                end,
            }
            Enum = { SpellBookSpellBank = { Pet = 2 } }
            C_Spell = {
                GetSpellName = function(spellId)
                    if spellId == 147362 then
                        return "Counter Shot"
                    end
                    if spellId == 187707 then
                        return "Muzzle"
                    end
                    if spellId == 119914 then
                        return "Command Demon"
                    end
                    if spellId == 19647 then
                        return "Spell Lock"
                    end
                end,
            }

            assert.equals("Counter Shot", Load(Player("HUNTER")).GetInterruptName())
            assert.equals("Command Demon", Load(Player("WARLOCK")).GetInterruptName())

            C_SpellBook.IsSpellKnown = function(spellId, bank)
                return (spellId == 187707 and bank == nil) or (spellId == 19647 and bank == 2)
            end
            assert.equals("Muzzle", Load(Player("HUNTER")).GetInterruptName())
            assert.equals("Spell Lock", Load(Player("WARLOCK")).GetInterruptName())
        end)

        it("returns nil when the class, known spell, or name is missing", function()
            C_SpellBook = {
                IsSpellKnown = function()
                    return false
                end,
            }
            C_Spell = {
                GetSpellName = function()
                    return "Pummel"
                end,
            }

            assert.is_nil(Load(Player(nil)).GetInterruptName())
            assert.is_nil(Load(Player("WARRIOR")).GetInterruptName())

            C_SpellBook.IsSpellKnown = function()
                return true
            end
            C_Spell.GetSpellName = function()
                return ""
            end
            assert.is_nil(Load(Player("WARRIOR")).GetInterruptName())
        end)
    end)
end)
