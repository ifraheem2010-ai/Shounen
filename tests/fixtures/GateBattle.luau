--!strict
--[[
	The Phase 1 gate battle.

	One 6v6 built from the REAL move table in src/shared/Data/Moves.luau, driven by the
	real Engine, resolving from a fixed seed. Both the gate demo (.lune/gate-6v6.luau)
	and the determinism spec build it from here, so the battle printed to a terminal and
	the battle asserted in the suite are provably the same battle.

	SPECIES ARE STILL SYNTHETIC. src/shared/Data/Species.luau does not exist — that is
	@data-architect's and is Phase 2 work. The stats and typings below were chosen to
	produce a battle worth reading: a speed spread so turn order matters, typings that
	give the type chart something to say, and HP low enough that six knockouts fit in a
	log a person can actually scan.

	Move data is real. Species data is not. Nothing here is balance data.
]]

local Battle = require(script.Parent.SyntheticBattle)
local Shared = script.Parent.Parent.Parent.Shared
local Engine = require(Shared.Battle.Engine)
local Moves = require(Shared.Data.Moves)
local RNG = require(Shared.Battle.RNG)

--[[
	Twelve synthetic species. Names are deliberately marked as fixtures so nobody
	mistakes them for the roster — real names are original constructed words and are
	@data-architect's to invent.
]]
local SPECIES: { [string]: any } = {
	-- Side one: a fast opener, two attackers, a wall, a pivot, a closer.
	gate1 = {
		stats = Battle.statsWith({ hp = 130, spe = 125, atk = 115 }),
		typing = { "Storm" },
		catchRate = 45,
	},
	gate2 = {
		stats = Battle.statsWith({ hp = 150, spe = 70, atk = 130 }),
		typing = { "Feral" },
		catchRate = 45,
	},
	gate3 = {
		stats = Battle.statsWith({ hp = 140, spe = 95, spa = 120 }),
		typing = { "Flame" },
		catchRate = 45,
	},
	gate4 = {
		stats = Battle.statsWith({ hp = 180, spe = 45, def = 135 }),
		typing = { "Forge" },
		catchRate = 45,
	},
	gate5 = {
		stats = Battle.statsWith({ hp = 140, spe = 100, atk = 95 }),
		typing = { "Aqua" },
		catchRate = 45,
	},
	gate6 = {
		stats = Battle.statsWith({ hp = 135, spe = 110, atk = 110 }),
		typing = { "Martial" },
		catchRate = 45,
	},

	-- Side two: mirrors the shape with different typings, so the chart matters.
	foe1 = {
		stats = Battle.statsWith({ hp = 135, spe = 115, spa = 110 }),
		typing = { "Psyche" },
		catchRate = 45,
	},
	foe2 = {
		stats = Battle.statsWith({ hp = 155, spe = 65, atk = 125 }),
		typing = { "Terra" },
		catchRate = 45,
	},
	foe3 = {
		stats = Battle.statsWith({ hp = 140, spe = 90, spa = 115 }),
		typing = { "Frost" },
		catchRate = 45,
	},
	foe4 = {
		stats = Battle.statsWith({ hp = 175, spe = 50, spd = 130 }),
		typing = { "Spirit" },
		catchRate = 45,
	},
	foe5 = {
		stats = Battle.statsWith({ hp = 145, spe = 105, spa = 100 }),
		typing = { "Arcane" },
		catchRate = 45,
	},
	foe6 = {
		stats = Battle.statsWith({ hp = 130, spe = 120, spa = 105 }),
		typing = { "Ki" },
		catchRate = 45,
	},
}

--[[
	Each creature carries a same-type move plus one utility or coverage move, so the log
	shows more than six creatures hitting each other with the same attack.
]]
local ROSTER_ONE = {
	{ uid = "Stormcaller", speciesId = "gate1", moves = { "storm.voltlance", "storm.sweepwind" } },
	{ uid = "Feralborn", speciesId = "gate2", moves = { "feral.rendclaw", "martial.sunderpalm" } },
	{ uid = "Emberwright", speciesId = "gate3", moves = { "flame.cinderlash", "ki.innersurge" } },
	{ uid = "Ironward", speciesId = "gate4", moves = { "forge.pistonram", "forge.replate" } },
	{ uid = "Tidewalker", speciesId = "gate5", moves = { "aqua.ebbstrike", "aqua.cleansewell" } },
	{ uid = "Palmbreaker", speciesId = "gate6", moves = { "martial.sunderpalm", "ki.kindlecore" } },
}

local ROSTER_TWO = {
	{
		uid = "Mindshear",
		speciesId = "foe1",
		moves = { "psyche.mindfracture", "psyche.mindsharpen" },
	},
	{ uid = "Stonewake", speciesId = "foe2", moves = { "terra.stoneheave", "forge.scatterbarb" } },
	{ uid = "Rimecaller", speciesId = "foe3", moves = { "frost.rimeshard", "forge.bulwarkveil" } },
	{ uid = "Hollowmark", speciesId = "foe4", moves = { "spirit.wraithgrasp", "spirit.soulbind" } },
	{
		uid = "Sigilbearer",
		speciesId = "foe5",
		moves = { "arcane.sigilbrand", "spirit.hollowcall" },
	},
	{ uid = "Corepulse", speciesId = "foe6", moves = { "ki.innersurge", "ki.kindlecore" } },
}

local function buildParty(roster: { any }): { any }
	local party = {}
	for _, entry in roster do
		table.insert(
			party,
			Battle.creature({
				uid = entry.uid,
				speciesId = entry.speciesId,
				moveIds = entry.moves,
				currentHp = SPECIES[entry.speciesId].stats.hp,
				pp = 16,
			})
		)
	end
	return party
end

--[[
	A deterministic controller: the first move with PP left, and the first living
	replacement.

	Deliberately not an AI. The gate is about the engine resolving a battle
	reproducibly, and a controller that made interesting choices would make the log
	harder to read and the determinism harder to attribute.
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

local function build(seed: number): any
	local state = Battle.state({
		seed = seed,
		sides = {
			Battle.side({ id = 1, party = buildParty(ROSTER_ONE) }),
			Battle.side({ id = 2, party = buildParty(ROSTER_TWO) }),
		},
	})

	return Engine.create({
		state = state,
		dex = Battle.dex({ species = SPECIES, moves = Moves.MOVES, items = {} }),
		rng = RNG.new(seed),
		controllers = { [1] = firstUsableController(), [2] = firstUsableController() },
		maxTurns = 200,
	})
end

return {
	SPECIES = SPECIES,
	ROSTER_ONE = ROSTER_ONE,
	ROSTER_TWO = ROSTER_TWO,
	build = build,
}
