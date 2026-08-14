--!strict
--[[
	Stats, and the -6..+6 stage system.

	Base stat bands (docs/TYPES.md has the full role table):
	  stage 1 ....... 280-330
	  stage 2 ....... 400-450
	  stage 3 ....... 510-560
	  legendary ..... 600-680, at most 3 in the entire game
	No character exceeds 150 in any single base stat before stage 3.
]]

export type StatId = "hp" | "atk" | "def" | "spa" | "spd" | "spe"

export type StatBlock = {
	hp: number,
	atk: number,
	def: number,
	spa: number,
	spd: number,
	spe: number,
}

-- HP has no stage. Accuracy and evasion have stages but no base value, which is why
-- these two lists are not the same list.
export type StagedStat = "atk" | "def" | "spa" | "spd" | "spe" | "accuracy" | "evasion"

export type StageBlock = {
	atk: number,
	def: number,
	spa: number,
	spd: number,
	spe: number,
	accuracy: number,
	evasion: number,
}

local STAT_IDS: { StatId } = { "hp", "atk", "def", "spa", "spd", "spe" }

local STAGED_STATS: { StagedStat } = { "atk", "def", "spa", "spd", "spe", "accuracy", "evasion" }

local MAX_STAGE = 6
local MIN_STAGE = -6

local MAX_IV = 31
local MAX_EV_PER_STAT = 252
local MAX_EV_TOTAL = 510

local function totalOf(stats: StatBlock): number
	return stats.hp + stats.atk + stats.def + stats.spa + stats.spd + stats.spe
end

local function zeroStages(): StageBlock
	return { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, accuracy = 0, evasion = 0 }
end

local function zeroStats(): StatBlock
	return { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
end

local function clampStage(stage: number): number
	return math.clamp(stage, MIN_STAGE, MAX_STAGE)
end

return {
	STAT_IDS = STAT_IDS,
	STAGED_STATS = STAGED_STATS,
	MAX_STAGE = MAX_STAGE,
	MIN_STAGE = MIN_STAGE,
	MAX_IV = MAX_IV,
	MAX_EV_PER_STAT = MAX_EV_PER_STAT,
	MAX_EV_TOTAL = MAX_EV_TOTAL,
	totalOf = totalOf,
	zeroStages = zeroStages,
	zeroStats = zeroStats,
	clampStage = clampStage,
}
