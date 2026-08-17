--!strict
--[[
	Species table validation.

	Named so `lune run run-tests -- --filter data` picks it up, alongside the move
	validator. Structural and rule checks only — "is Pyrecant too fast" is a question
	for a simulation sweep, "does Pyrecant's learnset name a move that exists" is a
	question a test should answer in a millisecond, forever.
]]

local TestKit = require(script.Parent.Parent.TestKit)
local Shared = script.Parent.Parent.Parent.Shared
local Moves = require(Shared.Data.Moves)
local Species = require(Shared.Data.Species)
local SpeciesTypes = require(Shared.Types.Species)
local StatBlock = require(Shared.Types.StatBlock)
local TypeChart = require(Shared.Data.TypeChart)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect
local fail = TestKit.fail

local EXPECTED_SPECIES_COUNT = 9
local STAB_REQUIRED_BY_LEVEL = 10

--[[
	The speed bands from CLAUDE.md section 5. The gaps between them are as deliberate as
	the bands: a speed of 127 exists only to creep one point past something at 126.
]]
local SPEED_BANDS = {
	{ min = 130, max = 255, name = "scarf" },
	{ min = 120, max = 125, name = "fast sweeper" },
	{ min = 105, max = 115, name = "standard sweeper" },
	{ min = 90, max = 100, name = "mid" },
	{ min = 65, max = 85, name = "slow" },
	{ min = 40, max = 60, name = "wall" },
}

local function bandFor(speed: number): string?
	for _, band in SPEED_BANDS do
		if speed >= band.min and speed <= band.max then
			return band.name
		end
	end
	return nil
end

local function bandForStage(stage: number): any
	if stage == 1 then
		return SpeciesTypes.STAT_BANDS.Stage1
	elseif stage == 2 then
		return SpeciesTypes.STAT_BANDS.Stage2
	end
	return SpeciesTypes.STAT_BANDS.Stage3
end

describe("Species data / shape", function()
	it("holds the nine starter-line species", function()
		expect(#Species.SPECIES_LIST).toBe(EXPECTED_SPECIES_COUNT)
		expect(#Species.SPECIES_IDS).toBe(EXPECTED_SPECIES_COUNT)
	end)

	it("has no duplicate ids", function()
		local seen: { [string]: boolean } = {}
		for _, entry in Species.SPECIES_LIST do
			if seen[entry.id] then
				fail(`duplicate species id "{entry.id}"`)
			end
			seen[entry.id] = true
		end
	end)

	it("gives every species a name and a concept line", function()
		for _, entry in Species.SPECIES_LIST do
			if entry.name == "" or entry.flavorText == "" then
				fail(`"{entry.id}" is missing a name or flavor text`)
			end
		end
	end)

	it("resolves every id and rejects an unknown one", function()
		for _, speciesId in Species.SPECIES_IDS do
			expect(Species.getSpecies(speciesId).id).toBe(speciesId)
		end
		expect(Species.has("nope.nothere")).toBe(false)
		expect(function()
			Species.getSpecies("nope.nothere")
		end).toThrow("no species with id")
	end)

	it("declares a real role for every species", function()
		local roles: { [string]: boolean } = {}
		for _, roleId in SpeciesTypes.ROLE_IDS do
			roles[roleId] = true
		end
		for _, entry in Species.SPECIES_LIST do
			if not roles[entry.role] then
				fail(`"{entry.id}" declares role "{entry.role}", which is not a role`)
			end
		end
	end)

	it("keeps catch rate and exp yield sane", function()
		for _, entry in Species.SPECIES_LIST do
			expect(entry.catchRate).toBeGreaterThanOrEqual(3)
			expect(entry.catchRate).toBeLessThanOrEqual(255)
			expect(entry.baseExpYield).toBeGreaterThan(0)
		end
	end)

	it("numbers stages 1 to 3", function()
		for _, entry in Species.SPECIES_LIST do
			expect(entry.stage).toBeGreaterThanOrEqual(1)
			expect(entry.stage).toBeLessThanOrEqual(3)
		end
	end)
end)

describe("Species data / typings", function()
	--[[
		72 of the 78 possible typings are legal. Six duals are not, and a species on one
		of them is either unkillable or a liability rather than a character.
	]]
	it("gives every species a legal typing", function()
		for _, entry in Species.SPECIES_LIST do
			local verdict = TypeChart.validateTyping(entry.typing)
			if not verdict.legal then
				fail(
					`"{entry.id}" typing {table.concat(entry.typing, "/")}: `
						.. table.concat(verdict.reasons, "; ")
				)
			end
		end
	end)

	it("keeps the starters mono-typed", function()
		-- Dual typing multiplies both power and bugs. The starters are the last place
		-- to spend that budget.
		for _, entry in Species.SPECIES_LIST do
			expect(#entry.typing).toBe(1)
		end
	end)

	it("covers exactly the starter triangle", function()
		local seen: { [string]: boolean } = {}
		for _, entry in Species.SPECIES_LIST do
			seen[entry.typing[1]] = true
		end
		expect(seen.Flame).toBe(true)
		expect(seen.Frost).toBe(true)
		expect(seen.Terra).toBe(true)
	end)

	--[[
		The triangle has to actually be a triangle in the chart, or the starter choice
		is cosmetic.
	]]
	it("still forms a 2x cycle in the chart", function()
		expect(TypeChart.getMultiplier("Flame", "Frost")).toBe(2)
		expect(TypeChart.getMultiplier("Frost", "Terra")).toBe(2)
		expect(TypeChart.getMultiplier("Terra", "Flame")).toBe(2)
	end)
end)

describe("Species data / stat bands", function()
	it("keeps every stat total inside its stage band", function()
		for _, entry in Species.SPECIES_LIST do
			local total = StatBlock.totalOf(entry.baseStats)
			local band = bandForStage(entry.stage)
			if total < band.min or total > band.max then
				fail(
					`"{entry.id}" (stage {entry.stage}) totals {total}, `
						.. `outside {band.min}-{band.max}`
				)
			end
		end
	end)

	it("keeps no single stat above 150 before stage 3", function()
		for _, entry in Species.SPECIES_LIST do
			if entry.stage < 3 then
				for _, statId in StatBlock.STAT_IDS do
					local value = (entry.baseStats :: any)[statId]
					if value > SpeciesTypes.MAX_SINGLE_STAT_BEFORE_STAGE_3 then
						fail(`"{entry.id}" has {statId} {value} at stage {entry.stage}`)
					end
				end
			end
		end
	end)

	it("places every speed inside a named tier", function()
		for _, entry in Species.SPECIES_LIST do
			local band = bandFor(entry.baseStats.spe)
			if band == nil then
				fail(
					`"{entry.id}" has speed {entry.baseStats.spe}, which is between tiers — `
						.. `pick a band rather than creeping past one`
				)
			end
		end
	end)

	--[[
		Creeping one point past an existing threat is the laziest form of power creep,
		and 126-129 is the window where it would happen.
	]]
	it("puts nobody in the forbidden speed window", function()
		local forbidden = SpeciesTypes.FORBIDDEN_SPEED_RANGE
		for _, entry in Species.SPECIES_LIST do
			local speed = entry.baseStats.spe
			if speed >= forbidden.min and speed <= forbidden.max then
				fail(`"{entry.id}" sits at speed {speed}, inside the forbidden window`)
			end
		end
	end)

	it("grows every stat total across a line", function()
		for _, line in Species.STARTER_LINES do
			local previous = 0
			for _, speciesId in line do
				local total = StatBlock.totalOf(Species.getSpecies(speciesId).baseStats)
				if total <= previous then
					fail(`"{speciesId}" totals {total}, no more than its previous stage`)
				end
				previous = total
			end
		end
	end)
end)

describe("Species data / learnsets", function()
	it("names no move that does not exist", function()
		for _, entry in Species.SPECIES_LIST do
			for _, learn in entry.learnset do
				if not Moves.has(learn.moveId) then
					fail(
						`"{entry.id}" learns "{learn.moveId}" at {learn.level}, which is not a move`
					)
				end
			end
		end
	end)

	it("sorts every learnset by level", function()
		for _, entry in Species.SPECIES_LIST do
			local previous = 0
			for _, learn in entry.learnset do
				if learn.level < previous then
					fail(
						`"{entry.id}" learnset is out of order: {learn.moveId} at `
							.. `{learn.level} follows level {previous}`
					)
				end
				previous = learn.level
			end
		end
	end)

	it("keeps every learn level within 1 to 100", function()
		for _, entry in Species.SPECIES_LIST do
			for _, learn in entry.learnset do
				expect(learn.level).toBeGreaterThanOrEqual(1)
				expect(learn.level).toBeLessThanOrEqual(100)
			end
		end
	end)

	it("teaches no move twice in one learnset", function()
		for _, entry in Species.SPECIES_LIST do
			local seen: { [string]: boolean } = {}
			for _, learn in entry.learnset do
				if seen[learn.moveId] then
					fail(`"{entry.id}" learns "{learn.moveId}" more than once`)
				end
				seen[learn.moveId] = true
			end
		end
	end)

	it("gives every species something to do at level 1", function()
		for _, entry in Species.SPECIES_LIST do
			local atOne = Species.movesAtLevel(entry.id, 1)
			if #atOne == 0 then
				fail(`"{entry.id}" knows nothing at level 1`)
			end
		end
	end)

	it("hands back at most four moves as a default set", function()
		for _, entry in Species.SPECIES_LIST do
			expect(#Species.defaultMoveset(entry.id, 100)).toBeLessThanOrEqual(4)
		end
	end)

	--[[
		The case the guarantee exists for. Glacivast learns its only Frost move at level 1
		and four other things afterwards, so a plain last-four rule hands back a Frost
		wall carrying no Frost move at all.
	]]
	it("keeps a same-type move even when it was learned first", function()
		local moveset = Species.defaultMoveset("frost.glacivast", 50)
		expect(moveset).toContain("frost.rimeshard")
		expect(#moveset).toBe(4)
	end)

	it("keeps a same-type move for every species that has one", function()
		for _, entry in Species.SPECIES_LIST do
			local hasStabAtAll = false
			for _, learn in entry.learnset do
				local move = Moves.getMove(learn.moveId)
				if move.typeId == entry.typing[1] and learn.level <= 100 then
					hasStabAtAll = true
				end
			end
			if not hasStabAtAll then
				continue
			end

			local moveset = Species.defaultMoveset(entry.id, 100)
			local carriesStab = false
			for _, moveId in moveset do
				if Moves.getMove(moveId).typeId == entry.typing[1] then
					carriesStab = true
				end
			end
			if not carriesStab then
				fail(
					`"{entry.id}" default set drops its only same-type move: {TestKit._show(moveset)}`
				)
			end
		end
	end)

	it("gives the default set the most recently learned moves", function()
		-- Pyrecant at 100 knows seven; the four it carries are the last four.
		expect(Species.defaultMoveset("flame.pyrecant", 100)).toEqual({
			"aqua.ebbstrike",
			"psyche.mindfracture",
			"storm.voltlance",
			"flame.cinderlash",
		})
	end)
end)

describe("Species data / same-type coverage", function()
	local function stabLevel(entry: any): number?
		for _, learn in entry.learnset do
			local move = Moves.getMove(learn.moveId)
			if move.typeId == entry.typing[1] then
				return learn.level
			end
		end
		return nil
	end

	it("gives every species a same-type move at some level", function()
		for _, entry in Species.SPECIES_LIST do
			if stabLevel(entry) == nil then
				fail(`"{entry.id}" never learns a {entry.typing[1]} move at all`)
			end
		end
	end)

	--[[
		THE GAP THAT WAS.

		CLAUDE.md section 6 wants a same-type damaging move by level 12; this asserts the
		stricter level 10. Six of nine species used to fail it, because Moves.luau held
		exactly one move of each starter type and two were endgame tiers. The 60-tier
		flame.emberwake and terra.gravelmaul closed it and NO_EARLY_STAB is now empty.

		The test does not change, and that is deliberate. It asserts the recorded set
		matches the real one in both directions, so with the record empty it now enforces
		the level-10 rule outright: a new species without early same-type coverage fails
		here unless someone writes down why.
	]]
	it("has an early-STAB gap on exactly the recorded species", function()
		local actual: { string } = {}
		for _, entry in Species.SPECIES_LIST do
			local level = stabLevel(entry)
			if level == nil or level > STAB_REQUIRED_BY_LEVEL then
				table.insert(actual, entry.id)
			end
		end
		table.sort(actual)

		local recorded: { string } = {}
		for speciesId in Species.NO_EARLY_STAB do
			table.insert(recorded, speciesId)
		end
		table.sort(recorded)

		if not TestKit._deepEqual(actual, recorded) then
			fail(
				`species without STAB by level {STAB_REQUIRED_BY_LEVEL} are `
					.. `{TestKit._show(actual)} but NO_EARLY_STAB records {TestKit._show(recorded)}. `
					.. `Update the record, or add the low-tier move that closes the gap.`
			)
		end
	end)

	it("gives a reason for every recorded gap", function()
		for speciesId, reason in Species.NO_EARLY_STAB do
			expect(Species.has(speciesId)).toBe(true)
			expect(#reason).toBeGreaterThan(0)
		end
	end)

	--[[
		Frost is the control case. Its move is the multi-hit tier, which is genuinely an
		early-game move, so its line carries STAB from level 1 — proving the gap is a
		move-table problem and not something inherent to starters.
	]]
	it("leaves the Frost line with STAB from level 1", function()
		for _, speciesId in Species.STARTER_LINES[2] do
			expect(stabLevel(Species.getSpecies(speciesId))).toBe(1)
		end
	end)
end)

describe("Species data / evolution", function()
	it("points every evolution at a species that exists", function()
		for _, entry in Species.SPECIES_LIST do
			for _, rule in entry.evolutions do
				if not Species.has(rule.into) then
					fail(`"{entry.id}" evolves into "{rule.into}", which does not exist`)
				end
			end
		end
	end)

	it("evolves into the next stage up, never sideways or back", function()
		for _, entry in Species.SPECIES_LIST do
			for _, rule in entry.evolutions do
				local target = Species.getSpecies(rule.into)
				if target.stage ~= entry.stage + 1 then
					fail(
						`"{entry.id}" (stage {entry.stage}) evolves into "{rule.into}" `
							.. `(stage {target.stage})`
					)
				end
			end
		end
	end)

	it("keeps the typing across an evolution", function()
		for _, entry in Species.SPECIES_LIST do
			for _, rule in entry.evolutions do
				expect(Species.getSpecies(rule.into).typing).toEqual(entry.typing)
			end
		end
	end)

	it("gives every level evolution a level between 2 and 100", function()
		for _, entry in Species.SPECIES_LIST do
			for _, rule in entry.evolutions do
				if rule.kind == "Level" then
					expect(rule.level).toBeGreaterThan(1)
					expect(rule.level).toBeLessThanOrEqual(100)
				end
			end
		end
	end)

	it("ends every line at stage 3", function()
		for _, entry in Species.SPECIES_LIST do
			if entry.stage == 3 then
				expect(#entry.evolutions).toBe(0)
			else
				expect(#entry.evolutions).toBeGreaterThan(0)
			end
		end
	end)

	--[[
		A loop here is not a data error, it is an infinite level-up. Walking the chain
		with a visited set is the only check that catches a three-way cycle.
	]]
	it("contains no evolution loop", function()
		for _, entry in Species.SPECIES_LIST do
			local visited: { [string]: boolean } = { [entry.id] = true }
			local current = entry
			local steps = 0

			while #current.evolutions > 0 do
				steps += 1
				if steps > EXPECTED_SPECIES_COUNT then
					fail(`evolution chain from "{entry.id}" did not terminate`)
				end
				local nextId = current.evolutions[1].into
				if visited[nextId] then
					fail(`evolution loop: "{entry.id}" reaches "{nextId}" twice`)
				end
				visited[nextId] = true
				current = Species.getSpecies(nextId)
			end
		end
	end)

	it("makes every species reachable as a starter or an evolution", function()
		local reachable: { [string]: boolean } = {}
		for _, line in Species.STARTER_LINES do
			reachable[line[1]] = true
		end
		for _, entry in Species.SPECIES_LIST do
			for _, rule in entry.evolutions do
				reachable[rule.into] = true
			end
		end
		for _, entry in Species.SPECIES_LIST do
			if not reachable[entry.id] then
				fail(`"{entry.id}" cannot be obtained by any route`)
			end
		end
	end)

	it("lists three lines of three", function()
		expect(#Species.STARTER_LINES).toBe(3)
		for _, line in Species.STARTER_LINES do
			expect(#line).toBe(3)
			for _, speciesId in line do
				expect(Species.has(speciesId)).toBe(true)
			end
		end
	end)
end)
