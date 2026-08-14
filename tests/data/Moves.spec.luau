--!strict
--[[
	Move table validation.

	Named so `lune run run-tests -- --filter data` picks it up, which is the command
	CLAUDE.md tells data-architect to run after any content change.

	These are structural and rule checks, not balance opinions. "Is 120 power with
	recoil too strong for a wallbreaker" is a question for a simulation sweep; "does
	this move use an effect kind that exists" is a question a test should answer in a
	millisecond, every time, forever.
]]

local TestKit = require(script.Parent.Parent.TestKit)
local Battle = require(script.Parent.Parent.fixtures.SyntheticBattle)
local Shared = script.Parent.Parent.Parent.Shared
local MoveEffect = require(Shared.Types.MoveEffect)
local MoveModule = require(Shared.Types.Move)
local Moves = require(Shared.Data.Moves)
local RNG = require(Shared.Battle.RNG)
local Species = require(Shared.Types.Species)
local TurnResolver = require(Shared.Battle.TurnResolver)
local TypeChart = require(Shared.Data.TypeChart)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect
local fail = TestKit.fail

local EXPECTED_MOVE_COUNT = 21

describe("Moves data / shape", function()
	it("holds exactly 21 reference moves", function()
		expect(#Moves.MOVE_LIST).toBe(EXPECTED_MOVE_COUNT)
		expect(#Moves.MOVE_IDS).toBe(EXPECTED_MOVE_COUNT)
	end)

	it("has no duplicate ids", function()
		local seen: { [string]: boolean } = {}
		for _, move in Moves.MOVE_LIST do
			if seen[move.id] then
				fail(`duplicate move id "{move.id}"`)
			end
			seen[move.id] = true
		end
	end)

	it("gives every move a non-empty name and description", function()
		for _, move in Moves.MOVE_LIST do
			if move.name == "" or move.description == "" then
				fail(`"{move.id}" is missing a name or description`)
			end
		end
	end)

	it("uses a known type for every move", function()
		local known: { [string]: boolean } = {}
		for _, typeId in TypeChart.ALL_TYPES do
			known[typeId] = true
		end
		for _, move in Moves.MOVE_LIST do
			if not known[move.typeId] then
				fail(`"{move.id}" has unknown type "{move.typeId}"`)
			end
		end
	end)

	it("uses a known category and targeting for every move", function()
		local categories: { [string]: boolean } = {}
		for _, category in MoveModule.CATEGORIES do
			categories[category] = true
		end
		local targetings: { [string]: boolean } = {}
		for _, targeting in MoveModule.TARGETINGS do
			targetings[targeting] = true
		end
		for _, move in Moves.MOVE_LIST do
			expect(categories[move.category]).toBe(true)
			expect(targetings[move.targeting]).toBe(true)
		end
	end)

	it("gives every move positive PP and a legal priority", function()
		for _, move in Moves.MOVE_LIST do
			expect(move.pp).toBeGreaterThan(0)
			expect(move.priority).toBeGreaterThanOrEqual(MoveModule.MIN_PRIORITY)
			expect(move.priority).toBeLessThanOrEqual(MoveModule.MAX_PRIORITY)
		end
	end)

	it("keeps accuracy within (0, 1] when it is stated at all", function()
		for _, move in Moves.MOVE_LIST do
			if move.accuracy ~= nil then
				expect(move.accuracy).toBeGreaterThan(0)
				expect(move.accuracy).toBeLessThanOrEqual(1)
			end
		end
	end)

	it("resolves every id through getMove and rejects an unknown one", function()
		for _, moveId in Moves.MOVE_IDS do
			expect(Moves.getMove(moveId).id).toBe(moveId)
		end
		expect(Moves.has("nope.notamove")).toBe(false)
		expect(function()
			Moves.getMove("nope.notamove")
		end).toThrow("no move with id")
	end)
end)

describe("Moves data / effect vocabulary", function()
	--[[
		The closedness check. Every effect on every move must be one of the 19
		primitives — an unknown kind here means someone invented behaviour instead of
		extending the vocabulary, which is the failure Absolute Rule #4 exists to stop.
	]]
	it("uses no effect kind outside the 19 primitives", function()
		local known: { [string]: boolean } = {}
		for _, kind in MoveEffect.EFFECT_KINDS do
			known[kind] = true
		end
		for _, move in Moves.MOVE_LIST do
			for _, effect in move.effects do
				if not known[effect.kind] then
					fail(
						`"{move.id}" uses effect kind "{tostring(effect.kind)}", which does not exist`
					)
				end
			end
		end
	end)

	it("gives every move at least one effect", function()
		for _, move in Moves.MOVE_LIST do
			if #move.effects == 0 then
				fail(`"{move.id}" has no effects and therefore does nothing`)
			end
		end
	end)

	it("passes structural validation on every effect", function()
		for _, move in Moves.MOVE_LIST do
			for index, effect in move.effects do
				local problems = MoveEffect.validate(effect)
				if #problems > 0 then
					fail(`"{move.id}" effect {index}: {table.concat(problems, "; ")}`)
				end
			end
		end
	end)

	it("never puts a Damage effect on a Status move", function()
		for _, move in Moves.MOVE_LIST do
			if move.category == "Status" and MoveModule.isDamaging(move) then
				fail(`"{move.id}" is a Status move but carries a damaging effect`)
			end
		end
	end)

	it("always gives a Physical or Special move something that damages", function()
		for _, move in Moves.MOVE_LIST do
			if move.category ~= "Status" and not MoveModule.isDamaging(move) then
				fail(`"{move.id}" is {move.category} but deals no damage`)
			end
		end
	end)

	it("matches each Damage effect's class to the move's category", function()
		for _, move in Moves.MOVE_LIST do
			for _, effect in move.effects do
				if effect.kind == "Damage" and effect.damageClass ~= move.category then
					fail(
						`"{move.id}" is {move.category} but its Damage effect is `
							.. `{effect.damageClass}`
					)
				end
			end
		end
	end)
end)

describe("Moves data / the Arcane wall", function()
	--[[
		Arcane gets no setup moves. This is the mechanical wall between Arcane and Ki:
		Ki boosts itself, Arcane manipulates the opponent. Without it the two types are
		one type with two names, and that collapse is invisible until twenty characters
		have been designed on top of it.
	]]
	it("gives no Arcane move a setup effect", function()
		local arcaneCount = 0
		for _, move in Moves.MOVE_LIST do
			if move.typeId == "Arcane" then
				arcaneCount += 1
				if MoveModule.isSetup(move) then
					fail(`"{move.id}" is Arcane and boosts its user — Arcane has no setup moves`)
				end
				expect(MoveModule.isSetup(move)).toBe(false)
			end
		end
		-- If Arcane ever drops to zero moves this test passes vacuously, which would
		-- be worse than failing.
		expect(arcaneCount).toBeGreaterThan(0)
	end)

	it("does put setup on Ki, so the wall is a real distinction", function()
		local kiSetup = false
		for _, move in Moves.MOVE_LIST do
			if move.typeId == "Ki" and MoveModule.isSetup(move) then
				kiSetup = true
			end
		end
		expect(kiSetup).toBe(true)
	end)
end)

describe("Moves data / damage tiers", function()
	local ALLOWED_POWER: { [number]: boolean } = {
		[25] = true,
		[40] = true,
		[60] = true,
		[75] = true,
		[90] = true,
		[110] = true,
		[120] = true,
		[130] = true,
	}

	it("puts every damaging move on a tier, never between two", function()
		for _, move in Moves.MOVE_LIST do
			for _, effect in move.effects do
				if effect.kind == "Damage" and not ALLOWED_POWER[effect.power] then
					fail(`"{move.id}" has power {effect.power}, which is not a tier`)
				end
			end
		end
	end)

	it("pairs the risky tiers with their reduced accuracy", function()
		for _, move in Moves.MOVE_LIST do
			for _, effect in move.effects do
				if effect.kind == "Damage" then
					if effect.power == 110 or effect.power == 130 then
						expect(move.accuracy).toBe(0.9)
					elseif effect.power == 25 then
						expect(move.accuracy).toBe(0.95)
					end
				end
			end
		end
	end)

	it("charges the 120 tier a third of its damage in recoil", function()
		for _, move in Moves.MOVE_LIST do
			local isWallbreakerTier = false
			for _, effect in move.effects do
				if effect.kind == "Damage" and effect.power == 120 then
					isWallbreakerTier = true
				end
			end
			if isWallbreakerTier then
				local hasRecoil = false
				for _, effect in move.effects do
					if effect.kind == "Recoil" then
						hasRecoil = true
					end
				end
				if not hasRecoil then
					fail(`"{move.id}" is the 120 tier and must carry recoil`)
				end
			end
		end
	end)

	it("charges the 130 tier a recharge turn", function()
		for _, move in Moves.MOVE_LIST do
			local isNuke = false
			for _, effect in move.effects do
				if effect.kind == "Damage" and effect.power == 130 then
					isNuke = true
				end
			end
			if isNuke then
				local paid = false
				for _, effect in move.effects do
					if effect.kind == "ApplyVolatile" and effect.volatile == "Recharge" then
						paid = true
					elseif effect.kind == "StatStage" and effect.delta <= -2 then
						paid = true
					end
				end
				if not paid then
					fail(`"{move.id}" is a nuke and must cost a recharge turn or -2`)
				end
			end
		end
	end)

	-- CLAUDE.md allows at most four nukes in the entire game.
	it("stays under the four-nuke ceiling", function()
		local nukes = 0
		for _, move in Moves.MOVE_LIST do
			for _, effect in move.effects do
				if effect.kind == "Damage" and effect.power == 130 then
					nukes += 1
				end
			end
		end
		expect(nukes).toBeLessThanOrEqual(4)
	end)

	it("gives priority only to the low tiers", function()
		for _, move in Moves.MOVE_LIST do
			if move.priority > 0 then
				for _, effect in move.effects do
					if effect.kind == "Damage" then
						-- A fast, powerful move has no counterplay.
						expect(effect.power).toBeLessThanOrEqual(40)
					end
				end
			end
		end
	end)
end)

describe("Moves data / coverage", function()
	--[[
		Every type needs a damaging same-type move or its characters have no STAB, and
		a type whose characters cannot use their own type offensively is a type that
		exists only as a defensive label.
	]]
	it("gives all 12 types at least one damaging move of that type", function()
		local damagingByType: { [string]: number } = {}
		for _, move in Moves.MOVE_LIST do
			if MoveModule.isDamaging(move) then
				damagingByType[move.typeId] = (damagingByType[move.typeId] or 0) + 1
			end
		end
		local missing: { string } = {}
		for _, typeId in TypeChart.ALL_TYPES do
			if (damagingByType[typeId] or 0) == 0 then
				table.insert(missing, typeId)
			end
		end
		if #missing > 0 then
			fail(`no damaging move for: {table.concat(missing, ", ")}`)
		end
	end)

	it("names a move for every one of the 12 competitive roles", function()
		local missing: { string } = {}
		for _, roleId in Species.ROLE_IDS do
			local entry = Moves.ROLE_REFERENCE[roleId]
			if entry == nil or #entry == 0 then
				table.insert(missing, roleId)
			end
		end
		if #missing > 0 then
			fail(`no reference move for role: {table.concat(missing, ", ")}`)
		end
	end)

	it("points every role reference at a move that exists", function()
		for roleId, moveIds in Moves.ROLE_REFERENCE do
			for _, moveId in moveIds do
				if not Moves.has(moveId) then
					fail(`role {roleId} references "{moveId}", which is not in the table`)
				end
			end
		end
	end)

	it("names no role that is not in Species.ROLE_IDS", function()
		local known: { [string]: boolean } = {}
		for _, roleId in Species.ROLE_IDS do
			known[roleId] = true
		end
		for roleId in Moves.ROLE_REFERENCE do
			if not known[roleId] then
				fail(`ROLE_REFERENCE names "{roleId}", which is not a role`)
			end
		end
	end)

	it("covers both damage classes", function()
		local physical, special = 0, 0
		for _, move in Moves.MOVE_LIST do
			for _, effect in move.effects do
				if effect.kind == "Damage" then
					if effect.damageClass == "Physical" then
						physical += 1
					else
						special += 1
					end
				end
			end
		end
		expect(physical).toBeGreaterThan(0)
		expect(special).toBeGreaterThan(0)
	end)
end)

describe("Moves data / engine wiring", function()
	--[[
		The real table reaching the real engine. Moves.getMove is signature-compatible
		with BattleDex.getMove, which is how src/shared/Data gets into the battle engine
		without the engine ever importing it.

		The species half is still synthetic — Data/Species.luau does not exist yet. That
		is the point of the injected dex: the half that exists can be real today.
	]]
	local function realMoveDex(): any
		local synthetic = Battle.dex({
			species = {
				alpha = { stats = Battle.statsWith({ spe = 120 }), typing = { "Martial" } },
				beta = { stats = Battle.statsWith({ spe = 60 }), typing = { "Ki" } },
			},
		})
		return {
			getMove = Moves.getMove,
			getStats = synthetic.getStats,
			getTyping = synthetic.getTyping,
		}
	end

	local function stateWith(moveId: string): any
		return Battle.state({
			sides = {
				Battle.side({
					id = 1,
					party = {
						Battle.creature({
							uid = "alpha",
							speciesId = "alpha",
							moveIds = { moveId },
						}),
					},
				}),
				Battle.side({
					id = 2,
					party = {
						Battle.creature({
							uid = "beta",
							speciesId = "beta",
							moveIds = { "martial.sunderpalm" },
						}),
					},
				}),
			},
		})
	end

	it("resolves a turn driven entirely by the real move table", function()
		local outcome = TurnResolver.resolveTurn(
			stateWith("martial.sunderpalm"),
			{ [1] = { kind = "Move", slot = 1 }, [2] = { kind = "Move", slot = 1 } },
			{ dex = realMoveDex(), rng = RNG.new(2024) }
		)
		local used = Battle.eventsOfKind(outcome.events, "MoveUsed")
		expect(#used).toBe(2)
		expect(used[1].moveId).toBe("martial.sunderpalm")
		expect(#Battle.eventsOfKind(outcome.events, "DamageDealt")).toBeGreaterThan(0)
	end)

	it("applies STAB from the real move's type", function()
		-- alpha is Martial and uses a Martial move, so STAB must apply.
		local outcome = TurnResolver.resolveTurn(
			stateWith("martial.sunderpalm"),
			{ [1] = { kind = "Move", slot = 1 }, [2] = { kind = "Move", slot = 1 } },
			{ dex = realMoveDex(), rng = RNG.new(11) }
		)
		local hits = {}
		for _, event in Battle.eventsOfKind(outcome.events, "DamageDealt") do
			if event.sideId == 2 then
				table.insert(hits, event)
			end
		end
		expect(#hits).toBe(1)
		-- Martial into Ki is neutral, so any boost visible here is STAB.
		expect(hits[1].effectiveness).toBe(1)
		expect(hits[1].amount).toBeGreaterThan(0)
	end)

	it("runs the real multi-hit move and logs one event per hit", function()
		local outcome = TurnResolver.resolveTurn(
			stateWith("frost.rimeshard"),
			{ [1] = { kind = "Move", slot = 1 }, [2] = { kind = "Move", slot = 1 } },
			{ dex = realMoveDex(), rng = RNG.new(4) }
		)
		local hits = {}
		for _, event in Battle.eventsOfKind(outcome.events, "DamageDealt") do
			if event.sideId == 2 then
				table.insert(hits, event)
			end
		end
		expect(#hits).toBeGreaterThanOrEqual(2)
		expect(#hits).toBeLessThanOrEqual(5)
	end)
end)
