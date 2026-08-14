--!strict
--[[
	Stat stages, -6 to +6.

	TWO LADDERS, AND THEY ARE NOT THE SAME LADDER.

	    battle stats (atk/def/spa/spd/spe)   (2 + s) / 2 up,  2 / (2 - s) down
	    accuracy and evasion                 (3 + s) / 3 up,  3 / (3 - s) down

	So +1 attack is 1.5x while +1 accuracy is 1.33x, and +2 attack is 2.0x. Reaching
	for the wrong one is the mistake this module exists to make hard, which is why the
	two functions are named for what they modify rather than for a direction.

	The asymmetry between up and down is deliberate Gen-3-onward design: +1 multiplies
	by 1.5 but -1 only multiplies by 0.67, so boosting yourself beats debuffing your
	opponent and spending a turn on setup is worth it. Flattening that would quietly
	kill every setup sweeper in the game.
]]

local StatBlockModule = require(script.Parent.Parent.Types.StatBlock)

type StageBlock = StatBlockModule.StageBlock
type StagedStat = StatBlockModule.StagedStat

export type StageChange = {
	stages: StageBlock,
	-- What actually landed after clamping. A +2 request against a stage already at +5
	-- applies 1, and the log needs to say so rather than claim two.
	applied: number,
	newStage: number,
}

export type ResetOptions = {
	onlyPositive: boolean?,
	onlyNegative: boolean?,
}

local MIN_STAGE = StatBlockModule.MIN_STAGE
local MAX_STAGE = StatBlockModule.MAX_STAGE
local STAGED_STATS = StatBlockModule.STAGED_STATS

local IS_STAGED_STAT: { [string]: boolean } = {}
for _, stat in STAGED_STATS do
	IS_STAGED_STAT[stat] = true
end

--[[
	A Luau table indexer keyed by a union type is invariant (CLAUDE.md section 10), so
	a StageBlock cannot be read with a variable StagedStat without a cast. The cast is
	safe because StagedStat is exactly the field set of StageBlock — and
	StatStages.spec asserts that the two lists match, so if they ever drift apart the
	suite fails before the cast can start lying.
]]
local function readStage(stages: StageBlock, stat: StagedStat): number
	return (stages :: any)[stat]
end

local function writeStage(stages: StageBlock, stat: StagedStat, value: number)
	(stages :: any)[stat] = value
end

local function clamp(stage: number): number
	return math.clamp(stage, MIN_STAGE, MAX_STAGE)
end

--[[ The ladders ------------------------------------------------------------ ]]

local function battleMultiplier(stage: number): number
	local clamped = clamp(stage)
	if clamped >= 0 then
		return (2 + clamped) / 2
	end
	return 2 / (2 - clamped)
end

local function accuracyMultiplier(stage: number): number
	local clamped = clamp(stage)
	if clamped >= 0 then
		return (3 + clamped) / 3
	end
	return 3 / (3 - clamped)
end

--[[
	Deliberately NOT written as floor(stat * battleMultiplier(stage)).

	`stat * (2 + s) / 2` multiplies before dividing; `stat * ((2 + s) / 2)` divides
	first and multiplies a rounded quotient. They agree for every value we have
	tested, but only the first form is the one DamageCalc was verified against, and a
	one-point drift in a damage formula is exactly the kind of bug that takes a week
	to find. Keep the arithmetic in this order.
]]
local function applyToStat(stat: number, stage: number): number
	local clamped = clamp(stage)
	if clamped >= 0 then
		return math.floor(stat * (2 + clamped) / 2)
	end
	return math.floor(stat * 2 / (2 - clamped))
end

--[[ Changing stages -------------------------------------------------------- ]]

local function change(stages: StageBlock, stat: StagedStat, delta: number): StageChange
	if not IS_STAGED_STAT[stat] then
		error(`StatStages: "{tostring(stat)}" is not a staged stat`)
	end

	local current = readStage(stages, stat)
	local updatedStage = clamp(current + delta)

	local updated = table.clone(stages)
	writeStage(updated, stat, updatedStage)

	return {
		stages = updated,
		applied = updatedStage - current,
		newStage = updatedStage,
	}
end

local function reset(stages: StageBlock, options: ResetOptions?): StageBlock
	local onlyPositive = options ~= nil and options.onlyPositive == true
	local onlyNegative = options ~= nil and options.onlyNegative == true

	local updated = table.clone(stages)
	-- Annotated because generalized iteration widens the element type to `string`,
	-- which the StagedStat-keyed helpers then reject. CLAUDE.md section 10.
	for _, stat: StagedStat in STAGED_STATS do
		local value = readStage(updated, stat)
		local shouldClear = true
		if onlyPositive then
			shouldClear = value > 0
		elseif onlyNegative then
			shouldClear = value < 0
		end
		if shouldClear then
			writeStage(updated, stat, 0)
		end
	end
	return updated
end

local function get(stages: StageBlock, stat: StagedStat): number
	if not IS_STAGED_STAT[stat] then
		error(`StatStages: "{tostring(stat)}" is not a staged stat`)
	end
	return readStage(stages, stat)
end

return {
	MIN_STAGE = MIN_STAGE,
	MAX_STAGE = MAX_STAGE,
	STAGED_STATS = STAGED_STATS,

	clamp = clamp,
	battleMultiplier = battleMultiplier,
	accuracyMultiplier = accuracyMultiplier,
	applyToStat = applyToStat,
	change = change,
	reset = reset,
	get = get,
}
