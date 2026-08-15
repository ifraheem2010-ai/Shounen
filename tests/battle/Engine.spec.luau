--!strict
--[[
	Engine tests.

	Engine is the loop around TurnResolver: ask both sides what they want, hand it over,
	deal with the wreckage, decide whether the battle is still going. Everything that
	needs a decision from outside the simulation lives here — which action to take, and
	which creature to send in after a faint — because TurnResolver is a pure function of
	its inputs and asking a question is not.

	Controllers are injected. A test controller is three lines; a real one is a player
	waiting on a remote. Neither is the engine's business.
]]

local TestKit = require(script.Parent.Parent.TestKit)
local Battle = require(script.Parent.Parent.fixtures.SyntheticBattle)
local Moves = require(script.Parent.Parent.fixtures.SyntheticMoves)
local Shared = script.Parent.Parent.Parent.Shared
local Engine = require(Shared.Battle.Engine)
local RNG = require(Shared.Battle.RNG)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect
local fail = TestKit.fail

local ALL_MOVES: { [string]: any } = {
	idle = Moves.build("idle", "Martial", "Physical", 10),
	nuke = Moves.build("nuke", "Martial", "Physical", 130),
	pivot = Moves.utility("pivot", "Aqua", {
		{ kind = "Damage", power = 60, damageClass = "Physical" },
		{ kind = "SelfSwitch" },
	}, { category = "Physical", accuracy = 1 }),
}

local ITEMS: { [string]: any } = {
	ball = {
		id = "ball",
		name = "Plain Ball",
		effects = { { kind = "Capture", ballMultiplier = 1 } },
	},
	masterball = {
		id = "masterball",
		name = "Certain Ball",
		effects = { { kind = "Capture", ballMultiplier = 1, guaranteed = true } },
	},
	potion = {
		id = "potion",
		name = "Potion",
		effects = { { kind = "Heal", flat = 50, target = "Self" } },
	},
}

local SPECIES: { [string]: any } = {
	fast = { stats = Battle.statsWith({ spe = 120 }), typing = { "Aqua" }, catchRate = 45 },
	slow = { stats = Battle.statsWith({ spe = 50 }), typing = { "Aqua" }, catchRate = 45 },
	easy = { stats = Battle.statsWith({ spe = 50 }), typing = { "Aqua" }, catchRate = 255 },
}

local function dex(): any
	return Battle.dex({ species = SPECIES, moves = ALL_MOVES, items = ITEMS })
end

--[[
	The simplest possible controller: always the same action, always the first legal
	replacement. Records what it was asked so the prompt itself can be asserted.
]]
local function scripted(action: any, replacementPick: number?): any
	-- The call list is captured directly. A local is not in scope inside its own table
	-- constructor, so a closure that reached for `controller` here would capture nil.
	local calls: { any } = {}
	local controller: any = {
		replacementCalls = calls,
		chooseAction = function(_sideId: number, _state: any): any
			return action
		end,
		chooseReplacement = function(sideId: number, legal: { number }, _state: any): number
			table.insert(calls, { sideId = sideId, legal = legal })
			if replacementPick ~= nil then
				for _, index in legal do
					if index == replacementPick then
						return replacementPick
					end
				end
			end
			return legal[1]
		end,
	}
	return controller
end

local ATTACK = { kind = "Move", slot = 1 }

--[[
	`firstHp` sets only the lead's HP. A nuke deals about 55 against these stats, so a
	test that wants a faint inside one turn has to start the lead low — the rest of the
	party stays healthy so there is something to replace it with.
]]
local function party(prefix: string, count: number, options: { [string]: any }?): { any }
	local o: any = options or {}
	local members = {}
	for index = 1, count do
		local hp = o.currentHp or 200
		if index == 1 and o.firstHp ~= nil then
			hp = o.firstHp
		end
		table.insert(
			members,
			Battle.creature({
				uid = `{prefix}{index}`,
				speciesId = o.speciesId or "slow",
				moveIds = o.moveIds or { "idle" },
				currentHp = hp,
			})
		)
	end
	return members
end

local function engineWith(options: { [string]: any }?): any
	local o: any = options or {}
	local state = Battle.state({
		sides = {
			Battle.side({
				id = 1,
				party = o.partyOne or party("a", 1, { speciesId = "fast", moveIds = { "nuke" } }),
			}),
			Battle.side({
				id = 2,
				party = o.partyTwo or party("b", 1),
				isWild = o.wild,
			}),
		},
	})
	return Engine.create({
		state = state,
		dex = dex(),
		rng = RNG.new(o.seed or 12345),
		controllers = {
			[1] = o.controllerOne or scripted(ATTACK),
			[2] = o.controllerTwo or scripted(ATTACK),
		},
		maxTurns = o.maxTurns,
	})
end

--[[ The loop -------------------------------------------------------------- ]]

describe("Engine / the turn loop", function()
	it("asks each controller for an action and runs the turn", function()
		local engine = engineWith()
		local result = Engine.runTurn(engine)
		expect(#Battle.eventsOfKind(result.events, "MoveUsed")).toBe(2)
		expect(engine.state.turn).toBe(2)
	end)

	it("appends every turn's events to the running log", function()
		local engine = engineWith({ partyOne = party("a", 3), partyTwo = party("b", 3) })
		Engine.runTurn(engine)
		local afterOne = #engine.state.log
		Engine.runTurn(engine)
		expect(#engine.state.log).toBeGreaterThan(afterOne)
	end)

	it("refuses to run a turn once the battle is over", function()
		local engine = engineWith()
		Engine.run(engine)
		expect(Engine.isOver(engine.state)).toBe(true)
		expect(function()
			Engine.runTurn(engine)
		end).toThrow("over")
	end)
end)

--[[ Ending ---------------------------------------------------------------- ]]

describe("Engine / deciding the battle is finished", function()
	it("ends when one side has nothing left", function()
		local final = Engine.run(engineWith())
		expect(final.outcome).toBe("Side1Win")
		expect(Engine.isOver(final.state)).toBe(true)
	end)

	it("emits exactly one terminal event, and it is last", function()
		local final = Engine.run(engineWith())
		local ended = Battle.eventsOfKind(final.events, "BattleEnded")
		expect(#ended).toBe(1)
		expect(final.events[#final.events].kind).toBe("BattleEnded")
		expect(ended[1].outcome).toBe("Side1Win")
	end)

	it("writes the outcome onto the state", function()
		local final = Engine.run(engineWith())
		expect(final.state.outcome).toBe("Side1Win")
	end)

	it("names the other side when it is the one that falls", function()
		local final = Engine.run(engineWith({
			partyOne = party("a", 1, { currentHp = 5 }),
			partyTwo = party("b", 1, { speciesId = "fast", moveIds = { "nuke" } }),
		}))
		expect(final.outcome).toBe("Side2Win")
	end)

	it("keeps going while either side still has a body", function()
		local engine = engineWith({ partyTwo = party("b", 3) })
		Engine.runTurn(engine)
		expect(Engine.isOver(engine.state)).toBe(false)
	end)

	--[[
		Two walls that cannot kill each other must still terminate. Without a ceiling
		the loop runs forever, which in a real server is not a hung battle, it is a
		hung thread.
	]]
	it("stops at the turn ceiling rather than looping forever", function()
		local final = Engine.run(engineWith({
			partyOne = party("a", 1, { currentHp = 200 }),
			partyTwo = party("b", 1, { currentHp = 200 }),
			maxTurns = 5,
		}))
		expect(final.turns).toBe(5)
		expect(final.outcome).toBe("Draw")
	end)
end)

--[[ Forced replacement ----------------------------------------------------- ]]

describe("Engine / replacing a fainted creature", function()
	it("asks the controller which creature to send in", function()
		local controller = scripted(ATTACK)
		local engine = engineWith({ partyTwo = party("b", 3), controllerTwo = controller })
		Engine.run(engine)
		expect(#controller.replacementCalls).toBeGreaterThan(0)
		expect(controller.replacementCalls[1].sideId).toBe(2)
	end)

	it("only offers creatures that are still standing", function()
		local controller = scripted(ATTACK)
		local engine = engineWith({ partyTwo = party("b", 3), controllerTwo = controller })
		Engine.run(engine)
		for _, call in controller.replacementCalls do
			for _, index in call.legal do
				if index == 1 then
					fail("offered the creature that had just fainted")
				end
			end
		end
	end)

	--[[
		This is what D20 was waiting on. The controller's answer must actually be used,
		not treated as advice — a pivot or a faint replacement that ignores the player
		is worse than one that picks at random, because it looks like it listened.
	]]
	it("sends in the creature the controller actually named", function()
		local engine = engineWith({
			partyTwo = party("b", 3, { firstHp = 10 }),
			controllerTwo = scripted(ATTACK, 3),
		})
		Engine.runTurn(engine)
		expect(engine.state.sides[2].active.partyIndex).toBe(3)
	end)

	it("rejects a controller that names a fainted creature", function()
		local badController: any = {
			chooseAction = function(): any
				return ATTACK
			end,
			chooseReplacement = function(): number
				return 1
			end,
		}
		local engine = engineWith({ partyTwo = party("b", 3), controllerTwo = badController })
		expect(function()
			Engine.run(engine)
		end).toThrow("legal")
	end)

	it("logs the replacement as a switch in", function()
		local engine = engineWith({ partyTwo = party("b", 3, { firstHp = 10 }) })
		local result = Engine.runTurn(engine)
		expect(#Battle.eventsOfKind(result.events, "SwitchIn")).toBe(1)
	end)

	it("does not log a switch out for a creature that fainted", function()
		local engine = engineWith({ partyTwo = party("b", 3, { firstHp = 10 }) })
		local result = Engine.runTurn(engine)
		-- The faint is the exit. Announcing a withdrawal as well reads as two events
		-- for one thing happening.
		expect(#Battle.eventsOfKind(result.events, "SwitchOut")).toBe(0)
	end)

	it("makes the replacement pay the hazard toll", function()
		local engine = engineWith({ partyTwo = party("b", 3, { firstHp = 10 }) })
		engine.state.sides[2].hazards.Caltrops = 1
		local result = Engine.runTurn(engine)
		expect(#Battle.eventsOfKind(result.events, "HazardDamage")).toBe(1)
	end)
end)

--[[ Pivoting with a real choice -------------------------------------------- ]]

describe("Engine / SelfSwitch asks the player", function()
	it("uses the controller's pick rather than a random one", function()
		local engine = engineWith({
			partyOne = party("a", 3, { speciesId = "fast", moveIds = { "pivot" } }),
			partyTwo = party("b", 1, { currentHp = 500 }),
			controllerOne = scripted(ATTACK, 3),
		})
		Engine.runTurn(engine)
		expect(engine.state.sides[1].active.partyIndex).toBe(3)
	end)

	it("still withdraws when the controller picks the other option", function()
		local engine = engineWith({
			partyOne = party("a", 3, { speciesId = "fast", moveIds = { "pivot" } }),
			partyTwo = party("b", 1, { currentHp = 500 }),
			controllerOne = scripted(ATTACK, 2),
		})
		Engine.runTurn(engine)
		expect(engine.state.sides[1].active.partyIndex).toBe(2)
	end)
end)

--[[ Items and capture ------------------------------------------------------ ]]

describe("Engine / items", function()
	local USE_BALL = { kind = "Item", itemId = "ball", targetsOpponent = true }
	local USE_MASTER = { kind = "Item", itemId = "masterball", targetsOpponent = true }
	local USE_POTION = { kind = "Item", itemId = "potion" }

	it("runs an item's effects and logs the use", function()
		local engine = engineWith({
			partyOne = party("a", 1, { speciesId = "fast", currentHp = 100 }),
			controllerOne = scripted(USE_POTION),
		})
		local result = Engine.runTurn(engine)
		expect(#Battle.eventsOfKind(result.events, "ItemUsed")).toBe(1)
		expect(#Battle.eventsOfKind(result.events, "Healed")).toBe(1)
	end)

	--[[
		The Capture effect, which D25 left unwired because it needed a catch rate and an
		item path. Both exist now.
	]]
	it("attempts a capture against a wild creature", function()
		local engine = engineWith({ wild = true, controllerOne = scripted(USE_BALL) })
		local result = Engine.runTurn(engine)
		local attempts = Battle.eventsOfKind(result.events, "CaptureAttempt")
		expect(#attempts).toBe(1)
		expect(attempts[1].shakes).toBeGreaterThanOrEqual(0)
		expect(attempts[1].shakes).toBeLessThanOrEqual(4)
	end)

	it("ends the battle when the capture lands", function()
		local final = Engine.run(engineWith({ wild = true, controllerOne = scripted(USE_MASTER) }))
		expect(final.outcome).toBe("Captured")
		local attempts = Battle.eventsOfKind(final.events, "CaptureAttempt")
		expect(attempts[1].succeeded).toBe(true)
	end)

	--[[
		You cannot pocket someone else's character. A trainer battle that could be ended
		with a ball would make every gym optional.
	]]
	it("refuses to capture from a trainer battle", function()
		local engine = engineWith({ wild = false, controllerOne = scripted(USE_BALL) })
		local result = Engine.runTurn(engine)
		local attempts = Battle.eventsOfKind(result.events, "CaptureAttempt")
		expect(#attempts).toBe(1)
		expect(attempts[1].succeeded).toBe(false)
		expect(Engine.isOver(engine.state)).toBe(false)
	end)

	--[[
		Summed across twenty seeds rather than read off one. A single capture attempt is
		a coin flip, so a one-seed comparison would pass or fail on the seed rather than
		on whether the catch rate reached the formula at all.
	]]
	--[[
		The plain-ball version of this passes even when the wild check is removed, because
		a 45 catch rate at full HP fails about seven times in eight regardless. A
		guaranteed ball removes the luck: if the check is gone, this captures.
	]]
	it("refuses a guaranteed ball in a trainer battle too", function()
		local engine = engineWith({ wild = false, controllerOne = scripted(USE_MASTER) })
		local result = Engine.runTurn(engine)
		local attempts = Battle.eventsOfKind(result.events, "CaptureAttempt")
		expect(#attempts).toBe(1)
		expect(attempts[1].succeeded).toBe(false)
		expect(Engine.isOver(engine.state)).toBe(false)
	end)

	it("reads the catch rate from the dex rather than assuming one", function()
		local function totalShakes(speciesId: string): number
			local total = 0
			for seed = 1, 20 do
				local engine = engineWith({
					wild = true,
					partyTwo = party("b", 1, { speciesId = speciesId }),
					controllerOne = scripted(USE_BALL),
					seed = seed,
				})
				local attempt =
					Battle.eventsOfKind(Engine.runTurn(engine).events, "CaptureAttempt")[1]
				total += attempt.shakes
			end
			return total
		end
		-- catchRate 255 against catchRate 45, same HP and no status.
		expect(totalShakes("easy")).toBeGreaterThan(totalShakes("slow"))
	end)
end)

--[[ Running and forfeiting ------------------------------------------------- ]]

describe("Engine / running away", function()
	local RUN = { kind = "Run" }

	it("ends the battle when the escape succeeds", function()
		-- Side 1 is far faster, which is a guaranteed escape in Gen 5.
		local final = Engine.run(engineWith({ wild = true, controllerOne = scripted(RUN) }))
		expect(final.outcome).toBe("Fled")
		expect(Battle.eventsOfKind(final.events, "FleeAttempt")[1].succeeded).toBe(true)
	end)

	it("cannot run from a trainer", function()
		local engine = engineWith({ wild = false, controllerOne = scripted(RUN) })
		local result = Engine.runTurn(engine)
		expect(Battle.eventsOfKind(result.events, "FleeAttempt")[1].succeeded).toBe(false)
		expect(Engine.isOver(engine.state)).toBe(false)
	end)
end)

describe("Engine / forfeiting", function()
	it("hands the win to the other side immediately", function()
		local final = Engine.run(engineWith({ controllerOne = scripted({ kind = "Forfeit" }) }))
		expect(final.outcome).toBe("Side2Win")
	end)
end)

--[[ Determinism ------------------------------------------------------------ ]]

describe("Engine / determinism", function()
	--[[
		The property the whole engine exists to preserve. Same seed, same controllers,
		byte-identical log — otherwise a bug report is a rumour.
	]]
	it("produces an identical event log from the same seed", function()
		local function fullLog(): { any }
			return Engine.run(engineWith({
				partyOne = party("a", 3, { speciesId = "fast", moveIds = { "nuke" } }),
				partyTwo = party("b", 3),
				seed = 20260814,
			})).events
		end
		expect(fullLog()).toEqual(fullLog())
	end)

	it("produces a different log from a different seed", function()
		local function fullLog(seed: number): { any }
			return Engine.run(engineWith({
				partyOne = party("a", 3, { speciesId = "fast", moveIds = { "idle" } }),
				partyTwo = party("b", 3),
				seed = seed,
			})).events
		end
		expect(fullLog(1)).never.toEqual(fullLog(2))
	end)

	--[[
		Side 2 starts at 45 HP so one nuke is reliably one knockout — the nuke rolls 50 to
		59 against these stats. At 60 HP it takes two, and with only 10 PP the attacker
		runs dry one knockout short of a clean sweep and the battle stalls to the turn
		ceiling. That is a correct engine outcome and a useless test.
	]]
	it("resolves a full 6v6 to a decision", function()
		local final = Engine.run(engineWith({
			partyOne = party("a", 6, { speciesId = "fast", moveIds = { "nuke" } }),
			partyTwo = party("b", 6, { currentHp = 45 }),
			seed = 12345,
		}))
		expect(final.outcome).toBe("Side1Win")
		-- Six knockouts, so at least six turns and six Fainted events. Asserting the
		-- knockouts rather than a raw event count keeps this from being a magic number
		-- that shifts whenever the log gains a line.
		expect(final.turns).toBeGreaterThanOrEqual(6)
		expect(#Battle.eventsOfKind(final.events, "Fainted")).toBe(6)
		for _, creature in final.state.sides[2].party do
			expect(creature.currentHp).toBe(0)
		end
	end)
end)
