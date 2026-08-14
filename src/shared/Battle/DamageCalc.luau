--!strict
--[[
	The Gen-5 damage formula.

	A pure function over numbers, types and one injected roll. It holds no state,
	touches no Roblox API, and never looks at a move id — it reads `power` and
	`damageClass` off a Damage effect, which is what "moves are data interpreted by
	the engine" means in practice. A move it has never seen computes correctly.

	THE FORMULA

	    levelTerm = floor(2 * level / 5 + 2)
	    core      = floor(levelTerm * power * attack / defence)
	    base      = floor(core / 50) + 2

	then, in this order, flooring after each step:

	    multi-target -> critical -> random roll -> STAB -> type -> burn -> other

	The order is not decorative. STAB is 1.5x and truncates, so swapping STAB and type
	changes the answer: at base 7 with a resistance, STAB-then-type gives 5 and
	type-then-STAB gives 4. Gen 5 does STAB first.

	DECISIONS WHERE GEN 5 IS AMBIGUOUS OR WHERE WE SIMPLIFY, ALL DELIBERATE

	1. Burn is a trailing damage modifier, not a halving of the Attack stat.
	   Gen 3 halved the stat before the formula; Gen 5's formula lists Burn among the
	   trailing modifiers. The two differ because of truncation — for the canonical
	   level-50 case, halving the stat gives 24 and the modifier gives 23. We match
	   Gen 5 and produce 23.

	2. Critical hits are 2x. That is Gen 5; Gen 6 onward reduced it to 1.5x.

	3. A crit ignores the attacker's NEGATIVE attack stages and the defender's
	   POSITIVE defence stages, and nothing else. So a crit punches through a wall
	   that has set up, but still benefits from the attacker's own boosts.

	4. Type effectiveness is applied as one combined multiplier from TypeChart, where
	   the real Gen 5 applies it one defending type at a time. These are provably
	   identical here: every multiplier in the chart is a power of two, doubling is
	   exact, and floor(floor(x/2)/2) equals floor(x/4). If a non-power-of-two
	   multiplier ever enters the chart this equivalence dies and this has to become
	   a per-type loop.

	5. The full Gen 5 4096-based fixed-point modifier chain with round-half-down is
	   NOT implemented; plain truncating multiplication is. This is what standard
	   Gen-5 damage calculators do, so hand-checking against one agrees. The two can
	   differ by one point in rare stacked-modifier cases. Revisit only if something
	   actually depends on that last point — balance is data-architect's, so it very
	   likely never will.

	OUT OF SCOPE HERE, ON PURPOSE
	Multi-hit moves (`effect.hits` / `effect.hitsRange`) mean calling this once per
	hit; the loop belongs to the effect interpreter, not to the formula. Weather is a
	declared modifier slot with no source yet — SetField exists in the vocabulary but
	nothing sets it until a later phase.
]]

local StatStages = require(script.Parent.StatStages)
local StatusEffects = require(script.Parent.StatusEffects)
local TypeChart = require(script.Parent.Parent.Data.TypeChart)
local MoveEffectModule = require(script.Parent.Parent.Types.MoveEffect)
local MoveModule = require(script.Parent.Parent.Types.Move)
local RngModule = require(script.Parent.Parent.Types.Rng)
local StatBlockModule = require(script.Parent.Parent.Types.StatBlock)
local TypeIdModule = require(script.Parent.Parent.Types.TypeId)

type DamageEffect = MoveEffectModule.DamageEffect
type Move = MoveModule.Move
type MoveEffect = MoveEffectModule.MoveEffect
type Rng = RngModule.Rng
type StageBlock = StatBlockModule.StageBlock
type StatBlock = StatBlockModule.StatBlock
type StatusId = MoveEffectModule.StatusId
type TypeId = TypeIdModule.TypeId

--[[
	One side of a single damage calculation.

	`stats` are COMPUTED BATTLE STATS, not species base stats — level, IVs and EVs are
	already folded in by the time anything reaches here. Keeping that conversion out
	of this file is what lets the formula be tested with round numbers.
]]
export type Combatant = {
	level: number,
	stats: StatBlock,
	stages: StageBlock,
	typing: { TypeId },
	status: StatusId?,
}

export type DamageInput = {
	attacker: Combatant,
	defender: Combatant,
	move: Move,
	-- Which Damage effect of the move is resolving. Passed explicitly because a move
	-- may carry more than one, and the caller knows which step it is on.
	effect: DamageEffect,
	isCritical: boolean?,
	-- Gen 5 reduces damage when a move hits more than one target.
	targetCount: number?,
	-- Catch-all trailing multiplier for abilities and items, applied last.
	otherModifier: number?,
}

export type DamageResult = {
	damage: number,
	-- Before any modifier. Useful when a number looks wrong and you need to know
	-- whether the formula or a modifier is at fault.
	baseDamage: number,
	effectiveness: number,
	isStab: boolean,
	isCritical: boolean,
	randomFactor: number,
	attackUsed: number,
	defenseUsed: number,
}

export type DamageRange = { min: number, max: number }

local MIN_RANDOM_FACTOR = 85
local MAX_RANDOM_FACTOR = 100
local STAB_MULTIPLIER = 1.5
local CRITICAL_MULTIPLIER = 2
local BURN_MULTIPLIER = StatusEffects.BURN_PHYSICAL_MULTIPLIER
local MULTI_TARGET_MULTIPLIER = 0.75

-- Gen 5 critical hit ladder. Stage 4 and above sit at one half.
local CRITICAL_CHANCE_BY_STAGE: { [number]: number } = {
	[0] = 1 / 16,
	[1] = 1 / 8,
	[2] = 1 / 4,
	[3] = 1 / 3,
}
local MAX_CRITICAL_STAGE = 4
local MAX_CRITICAL_CHANCE = 1 / 2

--[[ Stat stages ------------------------------------------------------------ ]]

-- Re-exported from StatStages so there is exactly one stage ladder in the engine.
-- Two copies of this arithmetic would eventually disagree by a point, and a damage
-- formula that disagrees with the stat display by a point is a week of debugging.
local applyStage = StatStages.applyToStat

--[[ Critical hits ---------------------------------------------------------- ]]

local function criticalChance(critStage: number): number
	local stage = math.max(math.floor(critStage), 0)
	if stage >= MAX_CRITICAL_STAGE then
		return MAX_CRITICAL_CHANCE
	end
	return CRITICAL_CHANCE_BY_STAGE[stage]
end

local function rollCritical(critStage: number, rng: Rng): boolean
	return rng:nextBoolean(criticalChance(critStage))
end

--[[ Move inspection -------------------------------------------------------- ]]

-- First damaging step of a move, or nil for a status move. Never branches on id.
local function damageEffectOf(move: Move): DamageEffect?
	for _, effect: MoveEffect in move.effects do
		if effect.kind == "Damage" then
			return effect
		end
	end
	return nil
end

local function hasType(typing: { TypeId }, typeId: TypeId): boolean
	for _, candidate: TypeId in typing do
		if candidate == typeId then
			return true
		end
	end
	return false
end

--[[ The formula ------------------------------------------------------------ ]]

local function computeWithRoll(input: DamageInput, randomFactor: number): DamageResult
	if
		randomFactor % 1 ~= 0
		or randomFactor < MIN_RANDOM_FACTOR
		or randomFactor > MAX_RANDOM_FACTOR
	then
		error(
			`DamageCalc: the random factor must be an integer within `
				.. `{MIN_RANDOM_FACTOR}..{MAX_RANDOM_FACTOR}, got {randomFactor}`
		)
	end

	local move = input.move
	if move.category == "Status" then
		error(`DamageCalc: "{move.id}" is a Status move and deals no damage`)
	end

	local effect = input.effect
	if effect.kind ~= "Damage" then
		error(`DamageCalc: expected a Damage effect, got "{(effect :: any).kind}"`)
	end

	local attacker = input.attacker
	local defender = input.defender
	local isCritical = input.isCritical == true
	local targetCount = input.targetCount or 1
	local otherModifier = input.otherModifier or 1

	if attacker.level < 1 then
		error(`DamageCalc: level must be at least 1, got {attacker.level}`)
	end

	--[[
		Physical and special read different stat pairs. This branches on the EFFECT's
		damageClass rather than the move's category, because the effect is the more
		specific statement of the two and a move could in principle carry both.
	]]
	local isPhysical = effect.damageClass == "Physical"

	local rawAttack = if isPhysical then attacker.stats.atk else attacker.stats.spa
	local rawDefense = if isPhysical then defender.stats.def else defender.stats.spd
	local attackStage = if isPhysical then attacker.stages.atk else attacker.stages.spa
	local defenseStage = if isPhysical then defender.stages.def else defender.stages.spd

	-- Gen 5: a crit ignores the attacker's drops and the defender's boosts, so
	-- neither debuffing the attacker nor setting up defensively can soften one.
	if isCritical and attackStage < 0 then
		attackStage = 0
	end
	if (isCritical or effect.ignoresDefenseBoosts == true) and defenseStage > 0 then
		defenseStage = 0
	end

	local attack = applyStage(rawAttack, attackStage)
	local defense = applyStage(rawDefense, defenseStage)
	if defense < 1 then
		defense = 1
	end

	local levelTerm = math.floor(2 * attacker.level / 5 + 2)
	local core = math.floor(levelTerm * effect.power * attack / defense)
	local baseDamage = math.floor(core / 50) + 2

	local effectiveness = if effect.respectsTypeChart == false
		then 1
		else TypeChart.effectiveness(move.typeId, defender.typing)

	local isStab = hasType(attacker.typing, move.typeId)
	local isBurned = attacker.status == "Burn" and isPhysical

	local damage = baseDamage

	if targetCount > 1 then
		damage = math.floor(damage * MULTI_TARGET_MULTIPLIER)
	end
	if isCritical then
		damage = math.floor(damage * CRITICAL_MULTIPLIER)
	end
	damage = math.floor(damage * randomFactor / 100)
	if isStab then
		damage = math.floor(damage * STAB_MULTIPLIER)
	end
	damage = math.floor(damage * effectiveness)
	if isBurned then
		damage = math.floor(damage * BURN_MULTIPLIER)
	end
	if otherModifier ~= 1 then
		damage = math.floor(damage * otherModifier)
	end

	-- A connecting hit always does something. An immune one does not — the clamp must
	-- never resurrect a zero that came from the type chart.
	if effectiveness > 0 and damage < 1 then
		damage = 1
	end

	return {
		damage = damage,
		baseDamage = baseDamage,
		effectiveness = effectiveness,
		isStab = isStab,
		isCritical = isCritical,
		randomFactor = randomFactor,
		attackUsed = attack,
		defenseUsed = defense,
	}
end

-- Draws exactly one value from the injected generator. Exactly one, always, so the
-- stream stays aligned no matter which branch the damage takes.
local function compute(input: DamageInput, rng: Rng): DamageResult
	return computeWithRoll(input, rng:nextInteger(MIN_RANDOM_FACTOR, MAX_RANDOM_FACTOR))
end

-- The damage window, for previews and for AI that needs to know whether a hit can
-- kill. Consumes no randomness. Every step is monotonic in the roll, so the extremes
-- of the roll really are the extremes of the damage.
local function range(input: DamageInput): DamageRange
	return {
		min = computeWithRoll(input, MIN_RANDOM_FACTOR).damage,
		max = computeWithRoll(input, MAX_RANDOM_FACTOR).damage,
	}
end

return {
	MIN_RANDOM_FACTOR = MIN_RANDOM_FACTOR,
	MAX_RANDOM_FACTOR = MAX_RANDOM_FACTOR,
	STAB_MULTIPLIER = STAB_MULTIPLIER,
	CRITICAL_MULTIPLIER = CRITICAL_MULTIPLIER,
	BURN_MULTIPLIER = BURN_MULTIPLIER,
	MULTI_TARGET_MULTIPLIER = MULTI_TARGET_MULTIPLIER,

	applyStage = applyStage,
	criticalChance = criticalChance,
	rollCritical = rollCritical,
	damageEffectOf = damageEffectOf,
	computeWithRoll = computeWithRoll,
	compute = compute,
	range = range,
}
