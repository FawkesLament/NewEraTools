local _, ns = ...
local Internals = ns.Modules.Internals("TwinFangs")

---Nameplate-number badge layout. Saved appearance lives in TwinFangsSchema.
local Hint = {}
Internals.HintUI = Hint

-- Gap from the Blizzard nameplate before saved offsets. Not saved.
Hint.GAP = 7
-- Preview-only number. Live casts assign 1-10 from the current wave.
Hint.PLACEHOLDER_NUMBER = 24
