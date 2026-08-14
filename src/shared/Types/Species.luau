--!strict
--[[
	Species data — one entry per collectible character.

	The roster is built PvP-first from day one, because retrofitting competitive
	balance onto 60 characters designed for PvE is brutal and nobody has ever enjoyed
	doing it.

	EVERY CHARACTER HAS EXACTLY ONE DECLARED ROLE. If a player cannot tell what a
	character is FOR within five seconds of seeing its stats, the design failed. The
	role is a field here rather than a convention precisely so a validator can hold
	the line: every role needs at least 3 characters by endgame and at least 1 in the
	vertical slice. A role with one character is a role that gets banned or ignored.
]]

local StatBlockModule = require(script.Parent.StatBlock)
local TypeIdModule = require(script.Parent.TypeId)

type StatBlock = StatBlockModule.StatBlock
type TypeId = TypeIdModule.TypeId

export type RoleId =
	"PhysicalSweeper"
	| "SpecialSweeper"
	| "SetupSweeper"
	| "Wallbreaker"
	| "PhysicalWall"
	| "SpecialWall"
	| "Pivot"
	| "RevengeKiller"
	| "Tank"
	| "Support"
	| "HazardSetter"
	| "Trapper"

export type GrowthRate = "Fast" | "MediumFast" | "MediumSlow" | "Slow"

export type LearnsetEntry = {
	level: number,
	moveId: string,
}

export type EvolutionRule =
	{ kind: "Level", level: number, into: string }
	| { kind: "Item", itemId: string, into: string }
	| { kind: "Friendship", threshold: number, into: string }

export type Species = {
	id: string,
	-- Original constructed word, 2-4 syllables. Never a real anime character name,
	-- never a Pokemon name, never a trademarked term. See CLAUDE.md section 9 —
	-- Brick Bronze was taken down in 2018 and that is the whole cautionary tale.
	name: string,
	-- One or two entries. Validate every dual against TypeChart.validateTyping.
	typing: { TypeId },
	role: RoleId,
	-- 1, 2, or 3. Legendaries are stage 3.
	stage: number,
	baseStats: StatBlock,
	-- 3..255, higher is easier to catch.
	catchRate: number,
	baseExpYield: number,
	growthRate: GrowthRate,
	-- Must be sorted ascending by level; the data validator enforces this.
	-- Every character learns a same-type damaging move by level 12.
	learnset: { LearnsetEntry },
	evolutions: { EvolutionRule },
	isLegendary: boolean?,
	flavorText: string,
}

local ROLE_IDS: { RoleId } = {
	"PhysicalSweeper",
	"SpecialSweeper",
	"SetupSweeper",
	"Wallbreaker",
	"PhysicalWall",
	"SpecialWall",
	"Pivot",
	"RevengeKiller",
	"Tank",
	"Support",
	"HazardSetter",
	"Trapper",
}

-- Reference spreads for a fully-evolved competitive character. A new species should
-- start from its role's template and move a few points, not be invented freehand.
local ROLE_TEMPLATES: { [RoleId]: StatBlock } = {
	PhysicalSweeper = { hp = 70, atk = 125, def = 70, spa = 50, spd = 70, spe = 125 },
	SpecialSweeper = { hp = 70, atk = 50, def = 70, spa = 125, spd = 70, spe = 125 },
	SetupSweeper = { hp = 80, atk = 105, def = 85, spa = 60, spd = 85, spe = 105 },
	Wallbreaker = { hp = 90, atk = 135, def = 85, spa = 60, spd = 85, spe = 65 },
	PhysicalWall = { hp = 105, atk = 70, def = 135, spa = 60, spd = 85, spe = 45 },
	SpecialWall = { hp = 105, atk = 60, def = 85, spa = 65, spd = 135, spe = 45 },
	Pivot = { hp = 85, atk = 95, def = 95, spa = 80, spd = 90, spe = 95 },
	RevengeKiller = { hp = 65, atk = 115, def = 60, spa = 60, spd = 65, spe = 130 },
	Tank = { hp = 100, atk = 105, def = 100, spa = 70, spd = 90, spe = 70 },
	Support = { hp = 95, atk = 60, def = 95, spa = 85, spd = 110, spe = 60 },
	HazardSetter = { hp = 100, atk = 85, def = 110, spa = 65, spd = 90, spe = 50 },
	Trapper = { hp = 80, atk = 100, def = 85, spa = 95, spd = 85, spe = 85 },
}

export type StatBand = { min: number, max: number }

local STAT_BANDS: { [string]: StatBand } = {
	Stage1 = { min = 280, max = 330 },
	Stage2 = { min = 400, max = 450 },
	Stage3 = { min = 510, max = 560 },
	Legendary = { min = 600, max = 680 },
}

local MAX_LEGENDARIES = 3
-- No character exceeds this in any single base stat before stage 3.
local MAX_SINGLE_STAT_BEFORE_STAGE_3 = 150
-- Every character learns a same-type damaging move by this level.
local STAB_BY_LEVEL = 12
-- Every role needs at least this many characters by endgame.
local MIN_CHARACTERS_PER_ROLE = 3

--[[
	Speed tiers. Speed is the single most contested stat in turn-based PvP, so the
	values players have to memorise are fixed and few.

	  130+ ...... scarf tier, revenge killers only, MAX 2 IN THE WHOLE GAME
	  120-125 ... fast sweeper
	  105-115 ... standard sweeper, the crowded tier
	  90-100 .... mid: pivots, bulky offense
	  65-85 ..... slow: wallbreakers, tanks
	  40-60 ..... walls and Inversion-field abusers

	The gap at 126-129 is deliberate and enforced. Creeping one point past an existing
	threat is the laziest form of power creep and it silently invalidates every design
	that was balanced against the old number.
]]
local FORBIDDEN_SPEED_RANGE: StatBand = { min = 126, max = 129 }
local MAX_SCARF_TIER_CHARACTERS = 2

return {
	ROLE_IDS = ROLE_IDS,
	ROLE_TEMPLATES = ROLE_TEMPLATES,
	STAT_BANDS = STAT_BANDS,
	MAX_LEGENDARIES = MAX_LEGENDARIES,
	MAX_SINGLE_STAT_BEFORE_STAGE_3 = MAX_SINGLE_STAT_BEFORE_STAGE_3,
	STAB_BY_LEVEL = STAB_BY_LEVEL,
	MIN_CHARACTERS_PER_ROLE = MIN_CHARACTERS_PER_ROLE,
	FORBIDDEN_SPEED_RANGE = FORBIDDEN_SPEED_RANGE,
	MAX_SCARF_TIER_CHARACTERS = MAX_SCARF_TIER_CHARACTERS,
}
