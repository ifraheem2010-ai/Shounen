--!strict
--[[
	The five non-volatile statuses: Burn, Poison, Paralysis, Sleep, Freeze.

	Non-volatile means one at a time and it survives switching out. A creature that is
	already burned cannot then be poisoned — canApply refuses rather than overwriting,
	because "the last status wins" turns every status move into a cleanse for the
	opponent.

	This module decides; it does not mutate. Every function takes the current status
	and returns what should happen, so the caller owns the state transition and the
	log entry. That keeps it pure and makes every rule here testable in isolation.

	GEN 5, WITH ONE DELIBERATE DIVERGENCE

	  Burn         halves physical damage, chips 1/8 max HP per turn
	  Poison       chips 1/8 max HP per turn
	  Paralysis    25% chance to lose the turn, and cuts speed
	  Sleep        1-3 turns, cannot act, wakes and acts on the turn after
	  Freeze       cannot act, 20% chance to thaw each turn

	THE DIVERGENCE: paralysis cuts speed to one HALF here. Gen 5 cuts it to one
	QUARTER. That was specified for this project rather than inherited, and quarter
	speed is famously punishing enough to decide games on its own. It is one constant
	below — set PARALYSIS_SPEED_MULTIPLIER to 0.25 to return to Gen 5.
]]

local BattleStateModule = require(script.Parent.Parent.Types.BattleState)
local MoveEffectModule = require(script.Parent.Parent.Types.MoveEffect)
local RngModule = require(script.Parent.Parent.Types.Rng)

type MoveFailureReason = BattleStateModule.MoveFailureReason
type Rng = RngModule.Rng
type StatusId = MoveEffectModule.StatusId

--[[
	The verdict on whether a creature may act this turn.

	`clearStatus` is separate from `canAct` on purpose: waking up and thawing both let
	the creature act AND cure the status, while a full paralysis blocks the turn and
	leaves the paralysis in place. Folding them together loses that distinction.
]]
export type ActionCheck = {
	canAct: boolean,
	reason: MoveFailureReason?,
	clearStatus: boolean,
	turnsRemaining: number?,
}

local BURN_PHYSICAL_MULTIPLIER = 0.5
-- See the divergence note above. Gen 5 is 0.25.
local PARALYSIS_SPEED_MULTIPLIER = 0.5
local FULL_PARALYSIS_CHANCE = 0.25
local FREEZE_THAW_CHANCE = 0.2
-- Burn and poison each take max HP / 8 at end of turn in Gen 5.
local CHIP_DENOMINATOR = 8
local SLEEP_MIN_TURNS = 1
local SLEEP_MAX_TURNS = 3

local CHIPS_HP: { [string]: boolean } = { Burn = true, Poison = true }

--[[ Application ------------------------------------------------------------ ]]

local function canApply(current: StatusId?, _incoming: StatusId): boolean
	return current == nil
end

-- Sleep is the only status with a countdown. Everything else returns nil and, just as
-- importantly, spends no randomness — an unnecessary draw here would shift every
-- later roll in the battle.
local function initialDuration(status: StatusId, rng: Rng): number?
	if status == "Sleep" then
		return rng:nextInteger(SLEEP_MIN_TURNS, SLEEP_MAX_TURNS)
	end
	return nil
end

--[[ Passive modifiers ------------------------------------------------------ ]]

local function physicalDamageMultiplier(status: StatusId?): number
	if status == "Burn" then
		return BURN_PHYSICAL_MULTIPLIER
	end
	return 1
end

local function speedMultiplier(status: StatusId?): number
	if status == "Paralysis" then
		return PARALYSIS_SPEED_MULTIPLIER
	end
	return 1
end

--[[ End of turn ------------------------------------------------------------ ]]

-- Always at least 1. floor(7 / 8) is zero, and a status that does nothing to a small
-- creature is a status that reads as broken.
local function endOfTurnDamage(status: StatusId?, maxHp: number): number
	if status == nil or not CHIPS_HP[status] then
		return 0
	end
	return math.max(1, math.floor(maxHp / CHIP_DENOMINATOR))
end

--[[ Acting ----------------------------------------------------------------- ]]

local function checkAction(status: StatusId?, turnsRemaining: number?, rng: Rng): ActionCheck
	if status == nil then
		return { canAct = true, reason = nil, clearStatus = false, turnsRemaining = turnsRemaining }
	end

	if status == "Sleep" then
		--[[
			A counter of N blocks exactly N attempts, then the creature wakes on the
			next one and acts that same turn. Counting down before the check instead
			of after is the off-by-one that turns a 3-turn sleep into a 4-turn one.
		]]
		local remaining = turnsRemaining or 0
		if remaining <= 0 then
			return { canAct = true, reason = nil, clearStatus = true, turnsRemaining = nil }
		end
		return {
			canAct = false,
			reason = "Asleep",
			clearStatus = false,
			turnsRemaining = remaining - 1,
		}
	end

	if status == "Freeze" then
		if rng:nextBoolean(FREEZE_THAW_CHANCE) then
			return { canAct = true, reason = nil, clearStatus = true, turnsRemaining = nil }
		end
		return {
			canAct = false,
			reason = "Frozen",
			clearStatus = false,
			turnsRemaining = turnsRemaining,
		}
	end

	if status == "Paralysis" then
		if rng:nextBoolean(FULL_PARALYSIS_CHANCE) then
			return {
				canAct = false,
				reason = "FullyParalysed",
				clearStatus = false,
				turnsRemaining = turnsRemaining,
			}
		end
		return { canAct = true, reason = nil, clearStatus = false, turnsRemaining = turnsRemaining }
	end

	-- Burn and Poison never stop a creature acting; they just grind it down.
	return { canAct = true, reason = nil, clearStatus = false, turnsRemaining = turnsRemaining }
end

return {
	BURN_PHYSICAL_MULTIPLIER = BURN_PHYSICAL_MULTIPLIER,
	PARALYSIS_SPEED_MULTIPLIER = PARALYSIS_SPEED_MULTIPLIER,
	FULL_PARALYSIS_CHANCE = FULL_PARALYSIS_CHANCE,
	FREEZE_THAW_CHANCE = FREEZE_THAW_CHANCE,
	CHIP_DENOMINATOR = CHIP_DENOMINATOR,
	SLEEP_MIN_TURNS = SLEEP_MIN_TURNS,
	SLEEP_MAX_TURNS = SLEEP_MAX_TURNS,

	canApply = canApply,
	initialDuration = initialDuration,
	physicalDamageMultiplier = physicalDamageMultiplier,
	speedMultiplier = speedMultiplier,
	endOfTurnDamage = endOfTurnDamage,
	checkAction = checkAction,
}
