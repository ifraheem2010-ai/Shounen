--!strict
--[[
	The Phase 1 gate, as a test.

	`lune run gate-6v6` prints this same battle to a terminal. This file asserts the
	properties that printout is supposed to demonstrate, so the demo cannot quietly
	drift away from what is actually checked — both build the battle from
	tests/fixtures/GateBattle.luau.

	The determinism assertion here is the one that matters most in the whole suite. If
	it ever fails, an ungated source of randomness has got into the engine, and every
	other result in the project becomes a rumour rather than a fact.
]]

local TestKit = require(script.Parent.Parent.TestKit)
local Battle = require(script.Parent.Parent.fixtures.SyntheticBattle)
local GateBattle = require(script.Parent.Parent.fixtures.GateBattle)
local Shared = script.Parent.Parent.Parent.Shared
local Engine = require(Shared.Battle.Engine)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect
local fail = TestKit.fail

local GATE_SEED = 12345

local function runGate(seed: number?): any
	return Engine.run(GateBattle.build(seed or GATE_SEED))
end

describe("Phase 1 gate / the battle resolves", function()
	it("reaches a terminal outcome", function()
		local final = runGate()
		expect(Engine.isOver(final.state)).toBe(true)
		expect(final.outcome).never.toBe("InProgress")
	end)

	it("does not stall into the turn ceiling", function()
		local final = runGate()
		if final.outcome == "Draw" then
			fail(
				`the gate battle ran to the ceiling at {final.turns} turns instead of `
					.. `resolving — something is stalling`
			)
		end
	end)

	it("ends with one side wiped out", function()
		local final = runGate()
		local oneDown = Engine.isDefeated(final.state.sides[1])
		local twoDown = Engine.isDefeated(final.state.sides[2])
		expect(oneDown or twoDown).toBe(true)
	end)

	it("closes the log with exactly one terminal event", function()
		local final = runGate()
		expect(#Battle.eventsOfKind(final.events, "BattleEnded")).toBe(1)
		expect(final.events[#final.events].kind).toBe("BattleEnded")
	end)

	it("produces a log worth reading", function()
		local final = runGate()
		expect(#final.events).toBeGreaterThan(60)
		expect(final.turns).toBeGreaterThan(5)
		-- Six knockouts on the losing side at minimum.
		expect(#Battle.eventsOfKind(final.events, "Fainted")).toBeGreaterThanOrEqual(6)
	end)

	it("drives it with the real move table", function()
		local final = runGate()
		local used = Battle.eventsOfKind(final.events, "MoveUsed")
		expect(#used).toBeGreaterThan(0)
		local sawRealMove = false
		for _, event in used do
			-- Real ids are namespaced by type; the synthetic fixtures are not.
			if string.find(event.moveId, ".", 1, true) ~= nil then
				sawRealMove = true
			end
		end
		expect(sawRealMove).toBe(true)
	end)
end)

describe("Phase 1 gate / determinism", function()
	--[[
		Byte-identical, twice, from the same seed. This is the property the injected RNG
		exists to guarantee and the reason `math.random` is banned in src/shared/Battle.
	]]
	it("produces a byte-identical log from the same seed", function()
		local first = runGate()
		local second = runGate()

		if #first.events ~= #second.events then
			fail(`event counts differ: {#first.events} against {#second.events}`)
		end
		for index = 1, #first.events do
			if not TestKit._deepEqual(first.events[index], second.events[index]) then
				fail(
					`diverged at event {index}: `
						.. `{TestKit._show(first.events[index])} against `
						.. `{TestKit._show(second.events[index])}`
				)
			end
		end
		expect(first.outcome).toBe(second.outcome)
		expect(first.turns).toBe(second.turns)
	end)

	it("leaves the final state identical too, not just the log", function()
		local first = runGate()
		local second = runGate()
		for sideIndex = 1, 2 do
			for partyIndex, creature in first.state.sides[sideIndex].party do
				expect(creature.currentHp).toBe(
					second.state.sides[sideIndex].party[partyIndex].currentHp
				)
			end
		end
	end)

	it("produces a different battle from a different seed", function()
		local a = runGate(GATE_SEED)
		local b = runGate(GATE_SEED + 1)
		expect(a.events).never.toEqual(b.events)
	end)

	it("stays reproducible across several seeds", function()
		for _, seed in { 1, 777, 20260814 } do
			local first = runGate(seed)
			local second = runGate(seed)
			if not TestKit._deepEqual(first.events, second.events) then
				fail(`seed {seed} did not reproduce`)
			end
		end
	end)
end)
