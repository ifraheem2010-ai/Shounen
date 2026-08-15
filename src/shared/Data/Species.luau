--!strict
--[[
	The three starter lines. Nine species, three stages each.

	These are the first real creatures in the project — everything before this ran on
	synthetic fixtures. Encounters, save data, learnsets, evolution and the UI all point
	at this table, so its shape matters more than its contents.

	THEY ARE PEOPLE. Every entry below is a human being with a discipline or a
	relationship to an element, not a creature made of one. A person who commands fire,
	not a fire-shaped animal. That distinction is the visual premise of the whole game
	and it is easiest to lose here, in the first nine.

	Names are original constructed words. Never a real anime character, never a Pokemon,
	never a trademarked term — CLAUDE.md section 9 is why this project exists at all.

	THE MOVEPOOL PROBLEM, STATED UP FRONT
	-------------------------------------
	Moves.luau contains exactly ONE move of each starter type:

	   flame.cinderlash    130 power, 90%, recharge turn   (the nuke tier)
	   frost.rimeshard     25 x2-5, 95%                    (the multi-hit tier)
	   terra.stoneheave    110 power, 90%                  (the high-risk tier)

	Frost's is a genuine early-game move and its line carries it from level 1. The other
	two are endgame tiers and cannot be handed to a level-8 starter without making the
	damage tiers in CLAUDE.md section 6 meaningless.

	So the Flame and Terra lines have NO same-type move until level 46 and level 38.
	That is a gap in the MOVE TABLE, not in these species, and it is recorded rather
	than papered over — Species.spec asserts the exact set of species affected so the
	list cannot grow quietly. The fix is three low-tier moves (a 40 or 60 power Flame,
	Frost and Terra move each), which is a move-table change and belongs in its own
	session.
]]

local CreatureInstanceModule = require(script.Parent.Parent.Types.CreatureInstance)
local MoveModule = require(script.Parent.Parent.Types.Move)
local Moves = require(script.Parent.Moves)
local SpeciesModule = require(script.Parent.Parent.Types.Species)

type Species = SpeciesModule.Species

local function species(definition: { [string]: any }): Species
	return definition :: any
end

--[[
	Roles. One per line, carried by all three stages — a stage-1 is not a competitive
	character, but it is unambiguously an early version of one, and splitting the role
	across stages would make "what is this character for" a question with three answers.

	  Flame  SpecialSweeper  fast, fragile, ends things
	  Frost  SpecialWall     slow, immovable, outlasts        (5 resistances by design)
	  Terra  Tank            bulky offense, trades and stays  (immune to Storm)
]]

--[[ Flame — Emberlin line -------------------------------------------------- ]]

local FLAME_LINE: { Species } = {
	species({
		id = "flame.emberlin",
		name = "Emberlin",
		typing = { "Flame" },
		role = "SpecialSweeper",
		stage = 1,
		-- 304. Speed 65 sits at the bottom of the slow band and climbs from there.
		baseStats = { hp = 45, atk = 38, def = 42, spa = 68, spd = 46, spe = 65 },
		catchRate = 45,
		baseExpYield = 62,
		growthRate = "MediumSlow",
		learnset = {
			{ level = 1, moveId = "ki.innersurge" },
			{ level = 10, moveId = "psyche.mindsharpen" },
			{ level = 18, moveId = "arcane.sigilbrand" },
			{ level = 28, moveId = "psyche.mindfracture" },
			{ level = 46, moveId = "flame.cinderlash" },
		},
		evolutions = { { kind = "Level", level = 16, into = "flame.ashvane" } },
		flavorText = "A lamplighter's apprentice who keeps one coal alive in her cupped hands and will not explain why.",
	}),

	species({
		id = "flame.ashvane",
		name = "Ashvane",
		typing = { "Flame" },
		role = "SpecialSweeper",
		stage = 2,
		-- 423. Speed 95 lands in the mid band; the sweeper speed arrives at stage 3.
		baseStats = { hp = 62, atk = 48, def = 58, spa = 100, spd = 60, spe = 95 },
		catchRate = 45,
		baseExpYield = 142,
		growthRate = "MediumSlow",
		learnset = {
			{ level = 1, moveId = "ki.innersurge" },
			{ level = 10, moveId = "psyche.mindsharpen" },
			{ level = 18, moveId = "arcane.sigilbrand" },
			{ level = 24, moveId = "aqua.ebbstrike" },
			{ level = 28, moveId = "psyche.mindfracture" },
			{ level = 46, moveId = "flame.cinderlash" },
		},
		evolutions = { { kind = "Level", level = 36, into = "flame.pyrecant" } },
		flavorText = "Older and much quieter, and the coal is something she carries in her chest now rather than her hands.",
	}),

	species({
		id = "flame.pyrecant",
		name = "Pyrecant",
		typing = { "Flame" },
		role = "SpecialSweeper",
		stage = 3,
		-- 515. Speed 120 is the fast-sweeper floor, deliberately clear of the banned
		-- 126-129 creep window.
		baseStats = { hp = 72, atk = 55, def = 68, spa = 128, spd = 72, spe = 120 },
		catchRate = 45,
		baseExpYield = 240,
		growthRate = "MediumSlow",
		learnset = {
			{ level = 1, moveId = "ki.innersurge" },
			{ level = 10, moveId = "psyche.mindsharpen" },
			{ level = 18, moveId = "arcane.sigilbrand" },
			{ level = 24, moveId = "aqua.ebbstrike" },
			{ level = 28, moveId = "psyche.mindfracture" },
			{ level = 40, moveId = "storm.voltlance" },
			{ level = 46, moveId = "flame.cinderlash" },
		},
		evolutions = {},
		flavorText = "She speaks and the air ahead of her catches; the words matter far less than the certainty behind them.",
	}),
}

--[[ Frost — Rimeling line -------------------------------------------------- ]]

local FROST_LINE: { Species } = {
	species({
		id = "frost.rimeling",
		name = "Rimeling",
		typing = { "Frost" },
		role = "SpecialWall",
		stage = 1,
		-- 305. Speed 40 is the floor of the wall band and stays there for the whole
		-- line; this is a character who was never going to outrun anything.
		baseStats = { hp = 60, atk = 36, def = 52, spa = 45, spd = 72, spe = 40 },
		catchRate = 45,
		baseExpYield = 62,
		growthRate = "MediumSlow",
		learnset = {
			{ level = 1, moveId = "frost.rimeshard" },
			{ level = 12, moveId = "forge.bulwarkveil" },
			{ level = 22, moveId = "forge.replate" },
		},
		evolutions = { { kind = "Level", level = 16, into = "frost.hoarwen" } },
		flavorText = "A boy who woke one winter unable to feel the cold, and has been quietly grateful ever since.",
	}),

	species({
		id = "frost.hoarwen",
		name = "Hoarwen",
		typing = { "Frost" },
		role = "SpecialWall",
		stage = 2,
		-- 420.
		baseStats = { hp = 88, atk = 50, def = 74, spa = 58, spd = 108, spe = 42 },
		catchRate = 45,
		baseExpYield = 142,
		growthRate = "MediumSlow",
		learnset = {
			{ level = 1, moveId = "frost.rimeshard" },
			{ level = 12, moveId = "forge.bulwarkveil" },
			{ level = 22, moveId = "forge.replate" },
			{ level = 30, moveId = "aqua.cleansewell" },
		},
		evolutions = { { kind = "Level", level = 36, into = "frost.glacivast" } },
		flavorText = "He has worked out that stillness is a weapon, and practises it with unsettling patience.",
	}),

	species({
		id = "frost.glacivast",
		name = "Glacivast",
		typing = { "Frost" },
		role = "SpecialWall",
		stage = 3,
		-- 520. Frost keeps five resistances by design; this line is built to use them
		-- rather than to hit hard.
		baseStats = { hp = 110, atk = 58, def = 92, spa = 70, spd = 140, spe = 50 },
		catchRate = 45,
		baseExpYield = 240,
		growthRate = "MediumSlow",
		learnset = {
			{ level = 1, moveId = "frost.rimeshard" },
			{ level = 12, moveId = "forge.bulwarkveil" },
			{ level = 22, moveId = "forge.replate" },
			{ level = 30, moveId = "aqua.cleansewell" },
			{ level = 38, moveId = "psyche.mindfracture" },
			{ level = 44, moveId = "forge.scatterbarb" },
		},
		evolutions = {},
		flavorText = "Nothing reaches him any more, and the frost he commands has become the argument he makes instead of speaking.",
	}),
}

--[[ Terra — Cairnling line ------------------------------------------------- ]]

local TERRA_LINE: { Species } = {
	species({
		id = "terra.cairnling",
		name = "Cairnling",
		typing = { "Terra" },
		role = "Tank",
		stage = 1,
		-- 308.
		baseStats = { hp = 58, atk = 60, def = 58, spa = 38, spd = 52, spe = 42 },
		catchRate = 45,
		baseExpYield = 62,
		growthRate = "MediumSlow",
		learnset = {
			{ level = 1, moveId = "storm.voltlance" },
			{ level = 14, moveId = "forge.pistonram" },
			{ level = 24, moveId = "forge.replate" },
			{ level = 38, moveId = "terra.stoneheave" },
		},
		evolutions = { { kind = "Level", level = 16, into = "terra.slatewarden" } },
		flavorText = "A quarry-hand's daughter who stacks stones taller than she is and refuses every offer of help.",
	}),

	species({
		id = "terra.slatewarden",
		name = "Slatewarden",
		typing = { "Terra" },
		role = "Tank",
		stage = 2,
		-- 442.
		baseStats = { hp = 85, atk = 88, def = 86, spa = 52, spd = 76, spe = 55 },
		catchRate = 45,
		baseExpYield = 142,
		growthRate = "MediumSlow",
		learnset = {
			{ level = 1, moveId = "storm.voltlance" },
			{ level = 14, moveId = "forge.pistonram" },
			{ level = 24, moveId = "forge.replate" },
			{ level = 32, moveId = "martial.sunderpalm" },
			{ level = 38, moveId = "terra.stoneheave" },
		},
		evolutions = { { kind = "Level", level = 36, into = "terra.cragmarrow" } },
		flavorText = "She has stopped stacking and started holding; the ground behind her does not move without her say.",
	}),

	species({
		id = "terra.cragmarrow",
		name = "Cragmarrow",
		typing = { "Terra" },
		role = "Tank",
		stage = 3,
		-- 550. Speed 68 is the slow band, which is where a tank belongs: it is not
		-- outrunning anything, it is still standing afterwards.
		baseStats = { hp = 105, atk = 112, def = 108, spa = 62, spd = 95, spe = 68 },
		catchRate = 45,
		baseExpYield = 240,
		growthRate = "MediumSlow",
		learnset = {
			{ level = 1, moveId = "storm.voltlance" },
			{ level = 14, moveId = "forge.pistonram" },
			{ level = 24, moveId = "forge.replate" },
			{ level = 32, moveId = "martial.sunderpalm" },
			{ level = 38, moveId = "terra.stoneheave" },
			{ level = 44, moveId = "forge.bulwarkveil" },
		},
		evolutions = {},
		flavorText = "Weathered past the point of caring, and the mountain behind her has started to agree with whatever she decides.",
	}),
}

--[[ Indexing --------------------------------------------------------------- ]]

local SPECIES_LIST: { Species } = {}
for _, line in { FLAME_LINE, FROST_LINE, TERRA_LINE } do
	for _, entry in line do
		table.insert(SPECIES_LIST, entry)
	end
end

local SPECIES: { [string]: Species } = {}
local SPECIES_IDS: { string } = {}

for _, entry in SPECIES_LIST do
	if SPECIES[entry.id] ~= nil then
		error(`Species: duplicate species id "{entry.id}"`)
	end
	SPECIES[entry.id] = entry
	table.insert(SPECIES_IDS, entry.id)
end

--[[
	The three starter lines, in triangle order: Flame beats Frost beats Terra beats
	Flame. Encounter tables and the starter-choice screen both want this.
]]
local STARTER_LINES: { { string } } = {
	{ "flame.emberlin", "flame.ashvane", "flame.pyrecant" },
	{ "frost.rimeling", "frost.hoarwen", "frost.glacivast" },
	{ "terra.cairnling", "terra.slatewarden", "terra.cragmarrow" },
}

--[[
	Species with no same-type move before level 10, and why.

	This is not a property of these characters — it is the move table having exactly one
	move per starter type, at the 130 and 110 tiers. Species.spec asserts this set
	EXACTLY, so a new species cannot join it silently and a fixed line cannot linger on
	it. Add a low-tier Flame or Terra move and the corresponding entries come out.
]]
local NO_EARLY_STAB: { [string]: string } = {
	["flame.emberlin"] = "the only Flame move is the 130-power nuke, learned at 46",
	["flame.ashvane"] = "the only Flame move is the 130-power nuke, learned at 46",
	["flame.pyrecant"] = "the only Flame move is the 130-power nuke, learned at 46",
	["terra.cairnling"] = "the only Terra move is the 110-power tier, learned at 38",
	["terra.slatewarden"] = "the only Terra move is the 110-power tier, learned at 38",
	["terra.cragmarrow"] = "the only Terra move is the 110-power tier, learned at 38",
}

--[[ Lookup ---------------------------------------------------------------- ]]

local function getSpecies(speciesId: string): Species
	local entry = SPECIES[speciesId]
	if entry == nil then
		error(`Species: no species with id "{speciesId}"`)
	end
	return entry
end

local function has(speciesId: string): boolean
	return SPECIES[speciesId] ~= nil
end

-- Moves this species knows at a given level, in learn order.
local function movesAtLevel(speciesId: string, level: number): { string }
	local known: { string } = {}
	for _, entry in getSpecies(speciesId).learnset do
		if entry.level <= level then
			table.insert(known, entry.moveId)
		end
	end
	return known
end

--[[
	The four a creature would actually be carrying: the last four it learned, EXCEPT that
	a same-type damaging move is always kept if the species has one.

	The plain last-four rule looks right and is not. Glacivast learns its only Frost move
	at level 1 and four other things afterwards, so at level 50 the naive rule hands back
	a wall with no same-type move at all — which is not a moveset any player would build
	and not one a wild encounter should have either.
]]
local function defaultMoveset(speciesId: string, level: number): { string }
	local known = movesAtLevel(speciesId, level)
	local slots = CreatureInstanceModule.MAX_MOVE_SLOTS
	if #known <= slots then
		return known
	end

	local recent: { string } = {}
	for index = #known - slots + 1, #known do
		table.insert(recent, known[index])
	end

	local typing = getSpecies(speciesId).typing[1]
	local function isSameTypeAttack(moveId: string): boolean
		local move = Moves.getMove(moveId)
		return move.typeId == typing and MoveModule.isDamaging(move)
	end

	for _, moveId in recent do
		if isSameTypeAttack(moveId) then
			return recent
		end
	end

	-- Nothing same-type survived the cut. Put the latest one back, over the oldest slot.
	local latestStab: string? = nil
	for _, moveId in known do
		if isSameTypeAttack(moveId) then
			latestStab = moveId
		end
	end
	if latestStab ~= nil then
		recent[1] = latestStab
	end
	return recent
end

return {
	SPECIES = SPECIES,
	SPECIES_IDS = SPECIES_IDS,
	SPECIES_LIST = SPECIES_LIST,
	STARTER_LINES = STARTER_LINES,
	NO_EARLY_STAB = NO_EARLY_STAB,
	getSpecies = getSpecies,
	has = has,
	movesAtLevel = movesAtLevel,
	defaultMoveset = defaultMoveset,
}
