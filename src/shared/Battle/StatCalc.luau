--!strict
--[[
	Base stats plus level plus IVs plus EVs, into the numbers a battle actually uses.

	    HP     = floor((2*base + iv + floor(ev/4)) * level / 100) + level + 10
	    others = floor((2*base + iv + floor(ev/4)) * level / 100) + 5

	Gen 5. HP gets the extra level term and the flat 10, which is why a low-level
	creature has meaningfully more HP than attack and why early battles are slow.

	WHY THIS LIVES IN Battle/ RATHER THAN Data/

	It is a formula, not content — the same class of thing as DamageCalc, and it changes
	about as often as the damage formula does, which is to say never. Data/ holds the
	numbers it operates on. Putting it beside the species table would mean the UI, the
	save system and the engine all reaching into Data/ for arithmetic.

	NATURES ARE NOT APPLIED HERE. Gen 5 multiplies one stat by 1.1 and another by 0.9
	after this step. CreatureInstance now carries a RESERVED field for them (P12), but
	it is always nil and nothing reads it — reserving the storage was the cheap half,
	and this arithmetic is the half that does not exist yet.

	When they arrive, they slot in as a final multiplier at the end of this function.
	That is a behaviour change to a formula the whole game is balanced against, so it
	gets the same treatment the damage formula got: a test asserting the Gen 5 values
	before the multiplier is wired in. No schemaVersion bump is needed — the field is
	already there, which was the entire point of reserving it.
]]

local StatBlockModule = require(script.Parent.Parent.Types.StatBlock)

type StatBlock = StatBlockModule.StatBlock

local HP_LEVEL_BONUS = 10
local OTHER_STAT_BONUS = 5
local EV_DIVISOR = 4

--[[
	The shared half of both formulas. EVs are quartered before they count, so the 252
	cap is worth 63 points of the pre-level term and the 510 total is the real budget.
]]
local function statBase(base: number, iv: number, ev: number, level: number): number
	return math.floor((2 * base + iv + math.floor(ev / EV_DIVISOR)) * level / 100)
end

local function computeHp(base: number, iv: number, ev: number, level: number): number
	return statBase(base, iv, ev, level) + level + HP_LEVEL_BONUS
end

local function computeOther(base: number, iv: number, ev: number, level: number): number
	return statBase(base, iv, ev, level) + OTHER_STAT_BONUS
end

--[[
	Every battle stat at once.

	Written out per stat rather than looped: StatBlock is a record, and a Luau table
	indexer keyed by a union is invariant (CLAUDE.md section 10), so a loop over stat
	names would need casts that the explicit form does not.
]]
local function compute(
	baseStats: StatBlock,
	ivs: StatBlock,
	evs: StatBlock,
	level: number
): StatBlock
	if level < 1 then
		error(`StatCalc: level must be at least 1, got {level}`)
	end

	return {
		hp = computeHp(baseStats.hp, ivs.hp, evs.hp, level),
		atk = computeOther(baseStats.atk, ivs.atk, evs.atk, level),
		def = computeOther(baseStats.def, ivs.def, evs.def, level),
		spa = computeOther(baseStats.spa, ivs.spa, evs.spa, level),
		spd = computeOther(baseStats.spd, ivs.spd, evs.spd, level),
		spe = computeOther(baseStats.spe, ivs.spe, evs.spe, level),
	}
end

return {
	HP_LEVEL_BONUS = HP_LEVEL_BONUS,
	OTHER_STAT_BONUS = OTHER_STAT_BONUS,
	EV_DIVISOR = EV_DIVISOR,
	computeHp = computeHp,
	computeOther = computeOther,
	compute = compute,
}
