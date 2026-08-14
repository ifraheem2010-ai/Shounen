--!strict
--[[
	The type chart. LOCKED — see docs/TYPES.md before proposing any edit.

	Authored as three lists per attacker rather than as a multiplier grid, because the
	bug this chart actually gets is "the same defender ends up in two lists", and a
	grid hides that: the second write silently wins. findContradictions() reads the
	authored lists, not the derived grid, which is the only way to see it.
	That bug has been introduced twice during design. Run the validators after edits.

	Verified status of the data below:
	  contradictions ................. 0
	  weaknesses per type ............ 2-4
	  resistances per type ........... 2-5
	  legal typings .................. 72 of 78 (12 mono + 60 dual)
	  unresisted two-move combos ..... 0

	NOTE ON A SYNTAX TRAP THAT HAS ALREADY COST TIME:
	  TypeChart.ALL_TYPES: { TypeId } = {...}   -- invalid Luau, you cannot annotate
	                                            -- a table field assignment
	Everything here is a local with a normal annotation, assembled into one return
	table at the bottom, which sidesteps the problem entirely.
]]

local TypeIdModule = require(script.Parent.Parent.Types.TypeId)

type TypeId = TypeIdModule.TypeId
type TypeFamily = TypeIdModule.TypeFamily

export type Matchup = {
	superEffective: { TypeId },
	resisted: { TypeId },
	immune: { TypeId },
}

export type DefensiveProfile = {
	weaknesses: { TypeId },
	resistances: { TypeId },
	immunities: { TypeId },
	-- Attackers hitting for 4x. Only reachable on dual typings.
	quadWeaknesses: { TypeId },
}

export type TypingVerdict = {
	legal: boolean,
	reasons: { string },
	profile: DefensiveProfile,
}

export type Contradiction = {
	attacker: TypeId,
	defender: TypeId,
	listedIn: { string },
}

--[[ The data --------------------------------------------------------------- ]]

local DISCIPLINE_TYPES: { TypeId } =
	{ "Martial", "Ki", "Arcane", "Psyche", "Spirit", "Feral", "Forge" }

local ELEMENT_TYPES: { TypeId } = { "Flame", "Frost", "Storm", "Terra", "Aqua" }

local ALL_TYPES: { TypeId } = {
	"Martial",
	"Ki",
	"Arcane",
	"Psyche",
	"Spirit",
	"Feral",
	"Forge",
	"Flame",
	"Frost",
	"Storm",
	"Terra",
	"Aqua",
}

-- Omitted pairs are neutral (1x). Dual types multiply.
--
-- Three immunities, all asymmetric on purpose: Ki cannot touch Spirit but Spirit
-- hits Ki neutrally; Psyche cannot touch Forge (no mind to attack); Storm cannot
-- touch Terra. Symmetric immunities create dead matchups where neither side can
-- act. Asymmetric ones create hard reads and grant a free switch-in, which is the
-- most valuable resource in turn-based PvP. Three rewards prediction. Six would
-- make the entire metagame about juggling immunities.
local MATCHUPS: { [TypeId]: Matchup } = {
	Martial = {
		superEffective = { "Arcane", "Feral", "Frost" },
		resisted = { "Martial", "Forge", "Spirit", "Terra" },
		immune = {},
	},
	Ki = {
		superEffective = { "Martial", "Forge", "Terra" },
		resisted = { "Ki", "Arcane", "Psyche", "Frost" },
		immune = { "Spirit" },
	},
	Arcane = {
		superEffective = { "Ki", "Feral", "Aqua" },
		resisted = { "Arcane", "Psyche", "Flame", "Storm" },
		immune = {},
	},
	Psyche = {
		superEffective = { "Ki", "Feral", "Spirit" },
		resisted = { "Psyche", "Arcane" },
		immune = { "Forge" },
	},
	Spirit = {
		superEffective = { "Arcane", "Psyche", "Spirit" },
		resisted = { "Martial", "Feral", "Forge", "Frost" },
		immune = {},
	},
	Feral = {
		superEffective = { "Arcane", "Psyche", "Storm" },
		resisted = { "Martial", "Feral", "Forge", "Flame" },
		immune = {},
	},
	Forge = {
		superEffective = { "Martial", "Frost", "Terra" },
		resisted = { "Forge", "Flame", "Storm", "Aqua" },
		immune = {},
	},
	Flame = {
		superEffective = { "Feral", "Forge", "Frost" },
		resisted = { "Flame", "Storm", "Terra", "Aqua" },
		immune = {},
	},
	Frost = {
		superEffective = { "Storm", "Terra", "Aqua" },
		resisted = { "Ki", "Feral", "Frost" },
		immune = {},
	},
	Storm = {
		superEffective = { "Spirit", "Forge", "Aqua" },
		resisted = { "Ki", "Frost", "Storm" },
		immune = { "Terra" },
	},
	Terra = {
		superEffective = { "Flame", "Forge", "Storm" },
		resisted = { "Martial", "Arcane", "Spirit", "Terra" },
		immune = {},
	},
	Aqua = {
		superEffective = { "Martial", "Flame", "Terra" },
		resisted = { "Feral", "Frost", "Aqua" },
		immune = {},
	},
}

--[[
	Legality bounds for a typing.

	MIN_WEAKNESSES     a typing with 0 or 1 weakness is too safe to counterplay
	MAX_DEFENSIVE      resistances + immunities above this centralises the metagame
	MAX_QUAD_WEAKNESS  two 4x weaknesses is not a character, it is a liability
]]
local MIN_WEAKNESSES = 2
local MAX_DEFENSIVE = 6
local MAX_QUAD_WEAKNESS = 1

-- More than this many unresisted two-move combos means offensive coverage is too
-- cheap and defensive play stops being a strategy.
local MAX_ACCEPTABLE_UNRESISTED_PAIRS = 4

--[[ Derived ---------------------------------------------------------------- ]]

local IS_TYPE: { [string]: boolean } = {}
for _, typeId in ALL_TYPES do
	IS_TYPE[typeId] = true
end

local FAMILY: { [TypeId]: TypeFamily } = {}
for _, typeId: TypeId in DISCIPLINE_TYPES do
	FAMILY[typeId] = "Discipline"
end
for _, typeId: TypeId in ELEMENT_TYPES do
	FAMILY[typeId] = "Element"
end

-- CHART[attacker][defender]. Sparse: a missing entry is neutral.
local CHART: { [TypeId]: { [TypeId]: number } } = {}
for _, attacker: TypeId in ALL_TYPES do
	local matchup = MATCHUPS[attacker]
	if matchup == nil then
		error(`TypeChart: no matchup row authored for "{attacker}"`)
	end

	local row: { [TypeId]: number } = {}
	for _, defender: TypeId in matchup.superEffective do
		row[defender] = 2
	end
	for _, defender: TypeId in matchup.resisted do
		row[defender] = 0.5
	end
	for _, defender: TypeId in matchup.immune do
		row[defender] = 0
	end
	CHART[attacker] = row
end

--[[ Lookup ----------------------------------------------------------------- ]]

local function assertType(typeId: TypeId, context: string)
	if not IS_TYPE[typeId] then
		error(`TypeChart: "{tostring(typeId)}" is not a known type ({context})`)
	end
end

local function familyOf(typeId: TypeId): TypeFamily
	assertType(typeId, "familyOf")
	return FAMILY[typeId]
end

local function getMultiplier(attacker: TypeId, defender: TypeId): number
	assertType(attacker, "getMultiplier attacker")
	assertType(defender, "getMultiplier defender")
	local entry = CHART[attacker][defender]
	return if entry == nil then 1 else entry
end

-- Validates the typing itself: 1 or 2 entries, distinct, both real types.
local function assertTyping(typing: { TypeId })
	local count = #typing
	if count < 1 or count > 2 then
		error(`TypeChart: a typing must have 1 or 2 entries, got {count}`)
	end
	for _, typeId: TypeId in typing do
		assertType(typeId, "typing")
	end
	if count == 2 and typing[1] == typing[2] then
		error(`TypeChart: dual typing "{typing[1]}" is the same type twice`)
	end
end

local function effectiveness(attacker: TypeId, defenderTyping: { TypeId }): number
	assertTyping(defenderTyping)
	local total = 1
	for _, defender: TypeId in defenderTyping do
		total *= getMultiplier(attacker, defender)
	end
	return total
end

--[[ Validators ------------------------------------------------------------- ]]

--[[
	Catches a defender listed as both super-effective and resisted (or immune) by the
	same attacker. This has happened twice. Wire it into CI and run it after every
	edit to MATCHUPS.
]]
local function findContradictions(): { Contradiction }
	local found: { Contradiction } = {}

	for _, attacker: TypeId in ALL_TYPES do
		local matchup = MATCHUPS[attacker]
		local seen: { [TypeId]: { string } } = {}

		local function record(defender: TypeId, listName: string)
			local lists = seen[defender]
			if lists == nil then
				seen[defender] = { listName }
			else
				table.insert(lists, listName)
			end
		end

		for _, defender: TypeId in matchup.superEffective do
			record(defender, "superEffective")
		end
		for _, defender: TypeId in matchup.resisted do
			record(defender, "resisted")
		end
		for _, defender: TypeId in matchup.immune do
			record(defender, "immune")
		end

		-- Iterate ALL_TYPES rather than `seen` so results are deterministically ordered.
		for _, defender: TypeId in ALL_TYPES do
			local lists = seen[defender]
			if lists ~= nil and #lists > 1 then
				table.insert(found, { attacker = attacker, defender = defender, listedIn = lists })
			end
		end
	end

	return found
end

local function defensiveProfile(typing: { TypeId }): DefensiveProfile
	assertTyping(typing)

	local profile: DefensiveProfile = {
		weaknesses = {},
		resistances = {},
		immunities = {},
		quadWeaknesses = {},
	}

	for _, attacker: TypeId in ALL_TYPES do
		local multiplier = effectiveness(attacker, typing)
		if multiplier == 0 then
			table.insert(profile.immunities, attacker)
		elseif multiplier > 1 then
			table.insert(profile.weaknesses, attacker)
			if multiplier >= 4 then
				table.insert(profile.quadWeaknesses, attacker)
			end
		elseif multiplier < 1 then
			table.insert(profile.resistances, attacker)
		end
	end

	return profile
end

--[[
	Bounds check on any mono or dual typing. Run this before approving a dual type:
	dual typing multiplies both power and bugs.

	A typing with zero weaknesses is not "strong", it is unbeatable, and the only
	honest response is to reject it or hand it deliberately bad stats.
]]
local function validateTyping(typing: { TypeId }): TypingVerdict
	local profile = defensiveProfile(typing)
	local reasons: { string } = {}

	local weaknessCount = #profile.weaknesses
	local defensiveCount = #profile.resistances + #profile.immunities
	local quadCount = #profile.quadWeaknesses

	if weaknessCount < MIN_WEAKNESSES then
		table.insert(
			reasons,
			`only {weaknessCount} weakness(es); minimum is {MIN_WEAKNESSES} — too safe`
		)
	end
	if defensiveCount > MAX_DEFENSIVE then
		table.insert(
			reasons,
			`{defensiveCount} resistances+immunities; maximum is {MAX_DEFENSIVE} — centralising`
		)
	end
	if quadCount > MAX_QUAD_WEAKNESS then
		table.insert(
			reasons,
			`{quadCount} quadruple weaknesses; maximum is {MAX_QUAD_WEAKNESS} — unplayable`
		)
	end

	return {
		legal = #reasons == 0,
		reasons = reasons,
		profile = profile,
	}
end

local function allTypings(): { { TypeId } }
	local typings: { { TypeId } } = {}
	for _, typeId: TypeId in ALL_TYPES do
		table.insert(typings, { typeId })
	end
	for firstIndex = 1, #ALL_TYPES do
		for secondIndex = firstIndex + 1, #ALL_TYPES do
			table.insert(typings, { ALL_TYPES[firstIndex], ALL_TYPES[secondIndex] })
		end
	end
	return typings
end

local function allLegalTypings(): { { TypeId } }
	local legal: { { TypeId } } = {}
	for _, typing in allTypings() do
		if validateTyping(typing).legal then
			table.insert(legal, typing)
		end
	end
	return legal
end

--[[
	Coverage check: which two-move type combinations nothing in the game can resist?

	Measured against the LEGAL TYPING POOL, not the 12 mono-types. Measuring against
	mono-types alone reports ~20 false alarms, because no real team is made of
	mono-types. Each result is a { attackerA, attackerB } pair.
]]
local function findUnresistedPairs(): { { TypeId } }
	local pool = allLegalTypings()
	local unresisted: { { TypeId } } = {}

	for firstIndex = 1, #ALL_TYPES do
		for secondIndex = firstIndex + 1, #ALL_TYPES do
			local first: TypeId = ALL_TYPES[firstIndex]
			local second: TypeId = ALL_TYPES[secondIndex]

			local answered = false
			for _, typing in pool do
				if effectiveness(first, typing) < 1 and effectiveness(second, typing) < 1 then
					answered = true
					break
				end
			end

			if not answered then
				table.insert(unresisted, { first, second })
			end
		end
	end

	return unresisted
end

return {
	ALL_TYPES = ALL_TYPES,
	DISCIPLINE_TYPES = DISCIPLINE_TYPES,
	ELEMENT_TYPES = ELEMENT_TYPES,
	MATCHUPS = MATCHUPS,
	CHART = CHART,

	MIN_WEAKNESSES = MIN_WEAKNESSES,
	MAX_DEFENSIVE = MAX_DEFENSIVE,
	MAX_QUAD_WEAKNESS = MAX_QUAD_WEAKNESS,
	MAX_ACCEPTABLE_UNRESISTED_PAIRS = MAX_ACCEPTABLE_UNRESISTED_PAIRS,

	familyOf = familyOf,
	getMultiplier = getMultiplier,
	effectiveness = effectiveness,
	defensiveProfile = defensiveProfile,

	validateTyping = validateTyping,
	findContradictions = findContradictions,
	findUnresistedPairs = findUnresistedPairs,
	allTypings = allTypings,
	allLegalTypings = allLegalTypings,
}
