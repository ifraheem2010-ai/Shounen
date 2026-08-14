--!strict
--[[
	SYNTHETIC BATTLE FIXTURES. NOT BALANCE DATA.

	Builders for CreatureInstance, SideState, BattleState and a BattleDex, so
	TurnResolver can be exercised before src/shared/Data/Species.luau and
	src/shared/Data/Moves.luau exist. Every stat here was picked to make a turn-order
	or damage assertion easy to read — speeds of 100 and 50 because one must clearly
	outrun the other, not because either is a sensible number for a real character.

	The real tables are @data-architect's. Neither exists yet. Nothing under
	src/shared/ may reference this file.

	WHY A DEX IS INJECTED AT ALL
	----------------------------
	TurnResolver needs a move's data and a creature's computed battle stats. Both come
	from tables that have not been authored. Rather than stall the engine on content,
	TurnResolver takes a BattleDex and asks it — so it works today against these
	fixtures and works unchanged the day the real tables land, with a thin adapter in
	between. It also means the engine never reads src/shared/Data directly, which
	keeps battle-engineer out of data-architect's files by construction.
]]

local Shared = script.Parent.Parent.Parent.Shared
local BattleState = require(Shared.Types.BattleState)
local StatBlock = require(Shared.Types.StatBlock)

local function statsWith(overrides: { [string]: number }): any
	local result: { [string]: number } =
		{ hp = 200, atk = 100, def = 100, spa = 100, spd = 100, spe = 100 }
	for key, value in overrides do
		result[key] = value
	end
	return result
end

local function perfectIvs(): any
	return { hp = 31, atk = 31, def = 31, spa = 31, spd = 31, spe = 31 }
end

export type CreatureOptions = {
	uid: string?,
	speciesId: string?,
	level: number?,
	currentHp: number?,
	status: string?,
	statusTurns: number?,
	moveIds: { string }?,
	pp: number?,
}

local function creature(options: CreatureOptions?): any
	local o: any = options or {}
	local moveIds: { string } = o.moveIds or { "fixture.physical100Martial" }
	local moves = {}
	for _, moveId in moveIds do
		table.insert(moves, { moveId = moveId, pp = o.pp or 10, maxPp = 10 })
	end

	return {
		uid = o.uid or "creature-1",
		speciesId = o.speciesId or "fixture.baseline",
		nickname = nil,
		level = o.level or 50,
		exp = 0,
		ivs = perfectIvs(),
		evs = StatBlock.zeroStats(),
		currentHp = o.currentHp or 200,
		status = o.status,
		statusTurns = o.statusTurns,
		moves = moves,
		heldItemId = nil,
		originalOwnerUserId = nil,
		caughtAtUnix = nil,
	}
end

export type SideOptions = {
	id: number,
	party: { any }?,
	activeIndex: number?,
	stages: any?,
	isWild: boolean?,
}

local function side(options: SideOptions): any
	local party = options.party or { creature({ uid = `side{options.id}-a` }) }
	return {
		id = options.id,
		displayName = `Side {options.id}`,
		party = party,
		active = {
			partyIndex = options.activeIndex or 1,
			stages = options.stages or StatBlock.zeroStages(),
			volatiles = {},
			turnsOnField = 0,
			lastMoveId = nil,
			trappedBySideId = nil,
		},
		hazards = {},
		sideConditions = {},
		isWild = options.isWild or false,
		controllingUserId = nil,
	}
end

export type StateOptions = {
	sides: { any }?,
	turn: number?,
	seed: number?,
}

local function state(options: StateOptions?): any
	local o: any = options or {}
	return {
		schemaVersion = BattleState.SCHEMA_VERSION,
		battleId = "fixture-battle",
		seed = o.seed or 12345,
		rngState = o.seed or 12345,
		turn = o.turn or 1,
		sides = o.sides or { side({ id = 1 }), side({ id = 2 }) },
		field = { activeField = nil, fieldTurnsRemaining = 0 },
		outcome = "InProgress",
		log = {},
	}
end

--[[
	A BattleDex over plain tables.

	`species` maps a speciesId to its computed battle stats and typing. Real stats are
	derived from base stats, IVs, EVs and level; here they are simply stated, because
	the point is to control the numbers a test sees, not to re-derive them.
]]
export type DexOptions = {
	species: { [string]: { stats: any, typing: { string } } }?,
	moves: { [string]: any }?,
}

local function dex(options: DexOptions?): any
	local o: any = options or {}
	local species: { [string]: any } = o.species or {}
	local moves: { [string]: any } = o.moves or {}

	if species["fixture.baseline"] == nil then
		species["fixture.baseline"] = { stats = statsWith({}), typing = { "Aqua" } }
	end

	return {
		getMove = function(moveId: string): any
			local move = moves[moveId]
			if move == nil then
				error(`SyntheticBattle dex: no move "{moveId}"`)
			end
			return move
		end,
		getStats = function(target: any): any
			local entry = species[target.speciesId]
			if entry == nil then
				error(`SyntheticBattle dex: no species "{target.speciesId}"`)
			end
			return entry.stats
		end,
		getTyping = function(target: any): any
			local entry = species[target.speciesId]
			if entry == nil then
				error(`SyntheticBattle dex: no species "{target.speciesId}"`)
			end
			return entry.typing
		end,
	}
end

-- Collects events of one kind out of a turn's log, which is how most assertions read.
local function eventsOfKind(events: { any }, kind: string): { any }
	local matching = {}
	for _, event in events do
		if event.kind == kind then
			table.insert(matching, event)
		end
	end
	return matching
end

return {
	statsWith = statsWith,
	creature = creature,
	side = side,
	state = state,
	dex = dex,
	eventsOfKind = eventsOfKind,
}
