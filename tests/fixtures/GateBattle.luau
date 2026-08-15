--!strict
--[[
	The Phase 1 gate battle, now on real data.

	Real move table, real species table, real stat formula, real engine, fixed seed.
	Nothing about the creatures in this battle is invented here any more — the roster
	names species ids and levels, and everything else is looked up.

	Both the gate demo (.lune/gate-6v6.luau) and the determinism spec build from here,
	so the battle printed to a terminal and the battle asserted in the suite are
	provably the same battle.

	WHAT IS STILL SYNTHETIC: nothing about the creatures. The `Battle.creature`,
	`Battle.side` and `Battle.state` builders from SyntheticBattle are still used to
	assemble BattleState, because that is state-shaping rather than content. The engine
	unit tests keep their synthetic species deliberately, so a balance change to
	Species.luau cannot turn the engine suite red.
]]

local Battle = require(script.Parent.SyntheticBattle)
local Shared = script.Parent.Parent.Parent.Shared
local Engine = require(Shared.Battle.Engine)
local Moves = require(Shared.Data.Moves)
local RNG = require(Shared.Battle.RNG)
local Species = require(Shared.Data.Species)
local StatCalc = require(Shared.Battle.StatCalc)

local GATE_LEVEL = 50

local function perfectIvs(): any
	return { hp = 31, atk = 31, def = 31, spa = 31, spd = 31, spe = 31 }
end

local function noEvs(): any
	return { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
end

--[[
	A BattleDex over the real tables.

	`getStats` is where Species finally reaches the engine: base stats plus level plus
	IVs and EVs through the Gen-5 formula, which is exactly what the dex interface was
	shaped for back when nothing behind it existed.

	Perfect IVs and no EVs across the board. That keeps the battle about the species
	rather than about a training spread nobody has designed yet, and it keeps the gate
	log reproducible without a second source of per-creature variation.
]]
local function realDex(): any
	return {
		getMove = Moves.getMove,
		getStats = function(creature: any): any
			local entry = Species.getSpecies(creature.speciesId)
			return StatCalc.compute(entry.baseStats, perfectIvs(), noEvs(), creature.level)
		end,
		getTyping = function(creature: any): any
			return Species.getSpecies(creature.speciesId).typing
		end,
		getCatchRate = function(creature: any): number
			return Species.getSpecies(creature.speciesId).catchRate
		end,
		getItem = function(itemId: string): any
			error(`GateBattle: no item table yet, cannot resolve "{itemId}"`)
		end,
	}
end

local function creatureFor(speciesId: string, level: number, uid: string?): any
	local entry = Species.getSpecies(speciesId)
	local stats = StatCalc.compute(entry.baseStats, perfectIvs(), noEvs(), level)
	return Battle.creature({
		uid = uid or entry.name,
		speciesId = speciesId,
		level = level,
		moveIds = Species.defaultMoveset(speciesId, level),
		currentHp = stats.hp,
		pp = 16,
	})
end

--[[
	Six a side, drawn from the six evolved forms. Stage-1 species are left out: a
	level-50 Emberlin is a punching bag, and a gate log full of one-sided knockouts
	demonstrates nothing about the engine.

	The two sides carry the same six species in different orders. That is deliberate —
	it makes the type chart the thing deciding matchups rather than a stat gap, and it
	means a divergence between runs cannot be explained away as one side being stronger.
]]
local ROSTER_ONE = {
	"flame.pyrecant",
	"terra.cragmarrow",
	"frost.glacivast",
	"flame.ashvane",
	"terra.slatewarden",
	"frost.hoarwen",
}

local ROSTER_TWO = {
	"frost.glacivast",
	"terra.slatewarden",
	"flame.pyrecant",
	"frost.hoarwen",
	"flame.ashvane",
	"terra.cragmarrow",
}

--[[
	A deterministic controller: the first move with PP left, and the first living
	replacement.

	Deliberately not an AI. The gate is about the engine resolving a battle
	reproducibly; a controller making interesting choices would make the log harder to
	read and any divergence harder to attribute.
]]
local function firstUsableController(): any
	return {
		chooseAction = function(sideId: number, state: any): any
			local side = state.sides[sideId]
			local active = side.party[side.active.partyIndex]
			for slot, entry in active.moves do
				if entry.pp > 0 then
					return { kind = "Move", slot = slot }
				end
			end
			return { kind = "Move", slot = 1 }
		end,
		chooseReplacement = function(_sideId: number, legal: { number }, _state: any): number
			return legal[1]
		end,
	}
end

local function partyFrom(roster: { string }, level: number, prefix: string): { any }
	local party = {}
	for index, speciesId in roster do
		table.insert(
			party,
			creatureFor(speciesId, level, `{prefix}{index}-{Species.getSpecies(speciesId).name}`)
		)
	end
	return party
end

local function build(seed: number): any
	local state = Battle.state({
		seed = seed,
		sides = {
			Battle.side({ id = 1, party = partyFrom(ROSTER_ONE, GATE_LEVEL, "A") }),
			Battle.side({ id = 2, party = partyFrom(ROSTER_TWO, GATE_LEVEL, "B") }),
		},
	})

	return Engine.create({
		state = state,
		dex = realDex(),
		rng = RNG.new(seed),
		controllers = { [1] = firstUsableController(), [2] = firstUsableController() },
		maxTurns = 200,
	})
end

--[[
	A small head-to-head, for asking whether the type triangle actually shows up in
	play at a given level rather than only in the chart.
]]
export type MatchupOptions = {
	seed: number,
	level: number,
	sideOne: { string },
	sideTwo: { string },
}

local function buildMatchup(options: MatchupOptions): any
	local state = Battle.state({
		seed = options.seed,
		sides = {
			Battle.side({ id = 1, party = partyFrom(options.sideOne, options.level, "A") }),
			Battle.side({ id = 2, party = partyFrom(options.sideTwo, options.level, "B") }),
		},
	})

	return Engine.create({
		state = state,
		dex = realDex(),
		rng = RNG.new(options.seed),
		controllers = { [1] = firstUsableController(), [2] = firstUsableController() },
		maxTurns = 200,
	})
end

return {
	GATE_LEVEL = GATE_LEVEL,
	ROSTER_ONE = ROSTER_ONE,
	ROSTER_TWO = ROSTER_TWO,
	realDex = realDex,
	creatureFor = creatureFor,
	build = build,
	buildMatchup = buildMatchup,
}
