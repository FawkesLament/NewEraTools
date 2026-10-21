local _, ns = ...

---Nameplate-number badge layout. Saved appearance lives in TwinFangsSchema.
local Hint = {}
ns.TwinFangsHintUI = Hint

-- Gap from the Blizzard nameplate before saved offsets. Not saved.
Hint.GAP = 7
-- Preview-only number. Live casts assign 1-10 from the current wave.
Hint.PLACEHOLDER_NUMBER = 24
