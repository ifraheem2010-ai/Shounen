--!strict
--[[
	Which volatiles actually do anything.

	D13 recorded that only three of the thirteen volatiles change engine behaviour and
	left a VOLATILE_BEHAVIOUR table so the gap was greppable. Greppable is not checked:
	a move applying Confusion currently looks like it works — the state updates, the log
	says VolatileApplied, and nothing whatsoever happens afterwards.

	This file closes that. For every volatile, it runs the same turn twice — once with
	the volatile sitting on the target and once without — and compares the complete
	event logs. A volatile listed as live MUST change the log. A volatile not listed
	MUST NOT. Either direction failing is a real finding:

	  a listed one stops mattering  -> the behaviour regressed
	  an unlisted one starts        -> someone implemented it without updating the table

	The second case is the one worth having. Implementing Confusion and forgetting to
	record it would leave the documentation lying, and this is the test that catches it.
]]

local TestKit = require(script.Parent.Parent.TestKit)
local Battle = require(script.Parent.Parent.fixtures.SyntheticBattle)
local Moves = require(script.Parent.Parent.fixtures.SyntheticMoves)
local Shared = script.Parent.Parent.Parent.Shared
local MoveEffect = require(Shared.Types.MoveEffect)
local RNG = require(Shared.Battle.RNG)
local TurnResolver = require(Shared.Battle.TurnResolver)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect
local fail = TestKit.fail

local EXPECTED_LIVE = { "Flinch", "Recharge", "Taunt" }

local ALL_MOVES: { [string]: any } = {
	strike = Moves.build("strike", "Martial", "Physical", 90),
	-- The subject uses a Status move so Taunt has something to bite on. Recharge and
	-- Flinch block anything, so one move covers all three live cases.
	boost = Moves.utility("boost", "Ki", {
		{ kind = "StatStage", stat = "atk", delta = 1, target = "Self" },
	}, { targeting = "Self" }),
}

local SPECIES: { [string]: any } = {
	fast = { stats = Battle.statsWith({ spe = 120 }), typing = { "Aqua" } },
	slow = { stats = Battle.statsWith({ spe = 50 }), typing = { "Aqua" } },
}

local BOTH = { [1] = { kind = "Move", slot = 1 }, [2] = { kind = "Move", slot = 1 } }

--[[
	Runs one turn with `volatileId` pre-placed on side 2's active creature, and returns
	the complete event log. Side 2 uses a Status move; side 1 attacks so the turn has
	something in it either way.
]]
local function logWith(volatileId: string?): { any }
	local state = Battle.state({
		sides = {
			Battle.side({
				id = 1,
				party = {
					Battle.creature({
						uid = "attacker",
						speciesId = "fast",
						moveIds = { "strike" },
					}),
				},
			}),
			Battle.side({
				id = 2,
				party = {
					Battle.creature({ uid = "subject", speciesId = "slow", moveIds = { "boost" } }),
				},
			}),
		},
	})

	if volatileId ~= nil then
		(state.sides[2].active.volatiles :: any)[volatileId] = { turnsRemaining = nil }
	end

	return TurnResolver.resolveTurn(state, BOTH, {
		dex = Battle.dex({ species = SPECIES, moves = ALL_MOVES }),
		rng = RNG.new(4242),
	}).events
end

describe("Volatile gap / the behaviour table is honest", function()
	it("names exactly the three volatiles with behaviour", function()
		local named: { string } = {}
		for volatileId in TurnResolver.VOLATILE_BEHAVIOUR do
			table.insert(named, volatileId)
		end
		table.sort(named)
		expect(named).toEqual(EXPECTED_LIVE)
	end)

	it("only names volatiles that exist in the vocabulary", function()
		local known: { [string]: boolean } = {}
		for _, volatileId in MoveEffect.VOLATILE_IDS do
			known[volatileId] = true
		end
		for volatileId in TurnResolver.VOLATILE_BEHAVIOUR do
			if not known[volatileId] then
				fail(`VOLATILE_BEHAVIOUR names "{volatileId}", which is not a volatile`)
			end
		end
	end)

	it("leaves ten of the thirteen inert", function()
		local live = 0
		for _ in TurnResolver.VOLATILE_BEHAVIOUR do
			live += 1
		end
		expect(#MoveEffect.VOLATILE_IDS).toBe(13)
		expect(live).toBe(3)
		expect(#MoveEffect.VOLATILE_IDS - live).toBe(10)
	end)
end)

describe("Volatile gap / measured against the engine", function()
	local baseline = logWith(nil)

	--[[
		One test per volatile, so a failure names the one that moved rather than
		reporting "something changed".
	]]
	for _, volatileId in MoveEffect.VOLATILE_IDS do
		local isLive = TurnResolver.VOLATILE_BEHAVIOUR[volatileId] ~= nil
		local label = if isLive then "changes the turn" else "changes nothing"

		it(`{volatileId} {label}`, function()
			local withVolatile = logWith(volatileId)
			local differs = not TestKit._deepEqual(withVolatile, baseline)

			if isLive and not differs then
				fail(
					`"{volatileId}" is listed in VOLATILE_BEHAVIOUR as `
						.. `"{TurnResolver.VOLATILE_BEHAVIOUR[volatileId]}" but the turn played out `
						.. `identically without it — the behaviour has regressed`
				)
			end
			if not isLive and differs then
				fail(
					`"{volatileId}" changed the turn but is not listed in VOLATILE_BEHAVIOUR. `
						.. `If it was just implemented, add it to the table; the documentation is `
						.. `now wrong either way`
				)
			end
			expect(differs).toBe(isLive)
		end)
	end
end)
