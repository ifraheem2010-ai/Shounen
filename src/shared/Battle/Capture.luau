--!strict
--[[
	The Gen-5 capture formula.

	    a = floor( ((3*maxHp - 2*currentHp) * catchRate * ballBonus) / (3*maxHp) * statusBonus )
	    a >= 255                    -> caught, no rolls
	    b = floor( 65536 / (255/a)^(3/16) )
	    four shakes, each passing when a 16-bit roll comes in under b

	Two things fall out of that shape and are worth naming, because they are the whole
	reason capture feels the way it does:

	  Chipping HP matters more than it looks. The numerator is 3*maxHp - 2*currentHp,
	  so dropping a target from full to 1 HP roughly triples `a`.

	  The fourth root is brutal at the low end. `b` is a per-shake probability and the
	  catch needs four of them, so a 60% shake is a 13% catch. A legendary at catchRate
	  3 sits near 2.6% even at 1 HP.

	This module is pure arithmetic over numbers. It does not know what a creature is,
	does not read Species, and takes catchRate as a parameter — which is what lets it
	be tested against an external reference rather than against itself.
]]

local MoveEffectModule = require(script.Parent.Parent.Types.MoveEffect)
local RngModule = require(script.Parent.Parent.Types.Rng)

type Rng = RngModule.Rng
type StatusId = MoveEffectModule.StatusId

export type CaptureInput = {
	maxHp: number,
	currentHp: number,
	-- 3 (legendary) to 255 (trivial). Comes from Species, which does not exist yet.
	catchRate: number,
	ballMultiplier: number,
	status: StatusId?,
	-- Master-ball style: skips the maths entirely.
	guaranteed: boolean?,
}

export type CaptureResult = {
	captured: boolean,
	-- 0 to 4. How many shakes the ball managed before it broke, which is what the
	-- animation plays back.
	shakes: number,
	modifiedRate: number,
	shakeThreshold: number,
	guaranteed: boolean,
}

local SHAKE_COUNT = 4
local SHAKE_RANGE = 65536
local GUARANTEED_RATE = 255
local SHAKE_EXPONENT = 3 / 16

--[[
	Gen 5 status bonuses. Sleep and Freeze are worth twice as much as the others
	because they also stop the target attacking, so the turns spent setting them up are
	not turns spent taking damage.
]]
local STATUS_BONUS: { [string]: number } = {
	Sleep = 2,
	Freeze = 2,
	Paralysis = 1.5,
	Burn = 1.5,
	Poison = 1.5,
}

local function statusBonus(status: StatusId?): number
	if status == nil then
		return 1
	end
	return STATUS_BONUS[status] or 1
end

local function modifiedCatchRate(input: CaptureInput): number
	if input.maxHp <= 0 then
		error(`Capture: maxHp must be positive, got {input.maxHp}`)
	end
	if input.currentHp <= 0 then
		error(`Capture: a fainted target cannot be caught (currentHp {input.currentHp})`)
	end

	local hpTerm = 3 * input.maxHp - 2 * input.currentHp
	local raw = (hpTerm * input.catchRate * input.ballMultiplier) / (3 * input.maxHp)
	return math.floor(raw * statusBonus(input.status))
end

local function shakeThreshold(modifiedRate: number): number
	if modifiedRate >= GUARANTEED_RATE then
		return SHAKE_RANGE
	end
	if modifiedRate <= 0 then
		return 0
	end
	return math.floor(SHAKE_RANGE / (GUARANTEED_RATE / modifiedRate) ^ SHAKE_EXPONENT)
end

--[[
	Always draws exactly four values, even once a shake has already failed.

	Stopping early would make the number of values consumed depend on the outcome, and
	the whole battle downstream would shift depending on whether a ball broke on the
	first shake or the third. Four rolls always; the reported shake count is how many
	passed before the first failure, which is what the animation needs.
]]
local function attempt(input: CaptureInput, rng: Rng): CaptureResult
	local rate = modifiedCatchRate(input)
	local threshold = shakeThreshold(rate)

	if input.guaranteed == true or rate >= GUARANTEED_RATE then
		return {
			captured = true,
			shakes = SHAKE_COUNT,
			modifiedRate = rate,
			shakeThreshold = threshold,
			guaranteed = true,
		}
	end

	local passed = 0
	local stillGoing = true
	for _ = 1, SHAKE_COUNT do
		local roll = rng:nextInteger(0, SHAKE_RANGE - 1)
		if stillGoing and roll < threshold then
			passed += 1
		else
			stillGoing = false
		end
	end

	return {
		captured = passed == SHAKE_COUNT,
		shakes = passed,
		modifiedRate = rate,
		shakeThreshold = threshold,
		guaranteed = false,
	}
end

return {
	SHAKE_COUNT = SHAKE_COUNT,
	SHAKE_RANGE = SHAKE_RANGE,
	GUARANTEED_RATE = GUARANTEED_RATE,
	STATUS_BONUS = STATUS_BONUS,
	statusBonus = statusBonus,
	modifiedCatchRate = modifiedCatchRate,
	shakeThreshold = shakeThreshold,
	attempt = attempt,
}
