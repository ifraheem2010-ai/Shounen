--!strict
--[[
	The reference move set: 24 moves, composed only from the 19 primitives in
	Types/MoveEffect.luau. No new primitives were added to make any of these work —
	that constraint is the whole point of the exercise, because the first move that
	needs a twentieth primitive is the move that proves the vocabulary was wrong.

	WHAT THIS SET IS FOR

	Every one of the 12 types gets at least one damaging same-type move, and every one
	of the 12 competitive roles in CLAUDE.md section 5 gets at least one move that does
	its job. It is a skeleton the roster can be built against, not a finished movepool:
	21 moves cannot make interesting choices for 24 characters. When real species
	arrive, most will want a coverage move this set does not contain.

	ARCANE HAS NO SETUP MOVES. Not "none yet" — none, by rule. Ki boosts itself and
	Arcane manipulates the opponent, and that mechanical wall is the only thing keeping
	the two types from collapsing into one. `Moves.spec` asserts isSetup() is false for
	every Arcane move in the table, so the rule is enforced rather than remembered.

	TIERS. Every damaging move sits ON a tier from CLAUDE.md section 6, never between
	two. Scattered power values make the game impossible to reason about, and a move at
	95 exists only to be slightly better than the one at 90.

	   40 / 100% / +1 priority ...... voltlance
	   60 / 100% .................... innersurge, ebbstrike,
	                                  emberwake, glasswind, gravelmaul
	   75 / 100% .................... sigilbrand, pistonram
	   90 / 100% .................... sunderpalm, wraithgrasp
	  110 /  90% .................... mindfracture, stoneheave
	  120 / 100% / 33% recoil ....... rendclaw
	  130 /  90% / recharge ......... cinderlash          (1 of a maximum 4 nukes)
	   25 x2-5 / 95% ................ rimeshard

	NAMES are original constructed compounds. Never a real anime character name, never
	a Pokemon move name, never a trademarked term. See CLAUDE.md section 9 — this is
	the rule that keeps the project from being taken down.
]]

local MoveModule = require(script.Parent.Parent.Types.Move)

type Move = MoveModule.Move

local function move(definition: { [string]: any }): Move
	return definition :: any
end

--[[ Damaging moves — one same-type move for each of the 12 types -------------- ]]

local MOVE_LIST: { Move } = {
	move({
		id = "martial.sunderpalm",
		name = "Sunderpalm",
		typeId = "Martial",
		category = "Physical",
		accuracy = 1,
		pp = 15,
		priority = 0,
		targeting = "SingleOpponent",
		makesContact = true,
		effects = { { kind = "Damage", power = 90, damageClass = "Physical" } },
		description = "A driving open-hand strike that splits guard and stance together.",
	}),

	move({
		id = "ki.innersurge",
		name = "Innersurge",
		typeId = "Ki",
		category = "Special",
		accuracy = 1,
		pp = 25,
		priority = 0,
		targeting = "SingleOpponent",
		makesContact = false,
		effects = { { kind = "Damage", power = 60, damageClass = "Special" } },
		description = "Cultivated force released outward in a single pulse.",
	}),

	--[[
		Arcane's lean is status and control, so its reference move carries a secondary
		poison rather than raw power. Note what it is NOT: there is no StatStage on the
		user anywhere in it, and there never will be on an Arcane move.
	]]
	move({
		id = "arcane.sigilbrand",
		name = "Sigilbrand",
		typeId = "Arcane",
		category = "Special",
		accuracy = 1,
		pp = 20,
		priority = 0,
		targeting = "SingleOpponent",
		makesContact = false,
		effects = {
			{ kind = "Damage", power = 75, damageClass = "Special" },
			{ kind = "InflictStatus", status = "Poison", chance = 0.3 },
		} :: { any },
		description = "A burning mark set into the air that festers where it lands.",
	}),

	move({
		id = "psyche.mindfracture",
		name = "Mindfracture",
		typeId = "Psyche",
		category = "Special",
		accuracy = 0.9,
		pp = 10,
		priority = 0,
		targeting = "SingleOpponent",
		makesContact = false,
		effects = { { kind = "Damage", power = 110, damageClass = "Special" } },
		description = "Nothing visible happens. The opponent simply staggers.",
	}),

	move({
		id = "spirit.wraithgrasp",
		name = "Wraithgrasp",
		typeId = "Spirit",
		category = "Physical",
		accuracy = 1,
		pp = 15,
		priority = 0,
		targeting = "SingleOpponent",
		makesContact = true,
		effects = { { kind = "Damage", power = 90, damageClass = "Physical" } },
		description = "A cold hand closes on something under the skin.",
	}),

	-- The wallbreaker tier: enormous, and it costs you a third of what it deals.
	move({
		id = "feral.rendclaw",
		name = "Rendclaw",
		typeId = "Feral",
		category = "Physical",
		accuracy = 1,
		pp = 10,
		priority = 0,
		targeting = "SingleOpponent",
		makesContact = true,
		effects = {
			{ kind = "Damage", power = 120, damageClass = "Physical" },
			{ kind = "Recoil", fractionOfDamageDealt = 0.33 },
		} :: { any },
		description = "A committed lunge that tears the attacker as much as the target.",
	}),

	move({
		id = "forge.pistonram",
		name = "Pistonram",
		typeId = "Forge",
		category = "Physical",
		accuracy = 1,
		pp = 20,
		priority = 0,
		targeting = "SingleOpponent",
		makesContact = true,
		effects = { { kind = "Damage", power = 75, damageClass = "Physical" } },
		description = "Hydraulics fire once, hard, and reset.",
	}),

	--[[
		THE STARTER BASELINE, one of three.

		The 60 tier is what CLAUDE.md section 6 calls early-game STAB, and until these
		three landed the starter types had nothing there: the only Flame move was the
		130 nuke and the only Terra move was the 110 tier, so the Flame and Terra lines
		carried no same-type move until level 46 and 38. That is what emptied
		Species.NO_EARLY_STAB.

		They are deliberately plain. No secondary status, no priority, no drawback — a
		60-power move that also does something is not the 60 tier, it is an undeclared
		tier between two declared ones, and the whole point of the table is that a
		player can reason about power by looking at it.
	]]
	move({
		id = "flame.emberwake",
		name = "Emberwake",
		typeId = "Flame",
		category = "Special",
		accuracy = 1,
		pp = 25,
		priority = 0,
		targeting = "SingleOpponent",
		makesContact = false,
		effects = { { kind = "Damage", power = 60, damageClass = "Special" } },
		description = "A low line of heat pushed out ahead of the user and left burning where it stops.",
	}),

	--[[
		The nuke tier. CLAUDE.md allows at most four of these in the entire game and
		this is the first. The cost is a recharge turn, expressed as the Recharge
		volatile on the user rather than as a special case in the engine.
	]]
	move({
		id = "flame.cinderlash",
		name = "Cinderlash",
		typeId = "Flame",
		category = "Special",
		accuracy = 0.9,
		pp = 5,
		priority = 0,
		targeting = "SingleOpponent",
		makesContact = false,
		effects = {
			{ kind = "Damage", power = 130, damageClass = "Special" },
			{ kind = "ApplyVolatile", volatile = "Recharge", target = "Self" },
		} :: { any },
		description = "Everything the user has, spent at once. Nothing is left for the next turn.",
	}),

	--[[
		The starter baseline, two of three. Frost already had an early-game move in
		rimeshard; this exists so all three starter types have the same 60-tier floor for
		the roster to build against.

		NO SPECIES LEARNS THIS, DELIBERATELY. It is not an unfinished job — adding it to
		the Frost line would replace rimeshard (expected power ~87.5) with a 60 in
		Glacivast's level-50 set, via defaultMoveset's latest-STAB fallback, and quietly
		worsen a matchup that is under a hold. Read DECISIONS_P2 P10 before changing this.
	]]
	move({
		id = "frost.glasswind",
		name = "Glasswind",
		typeId = "Frost",
		category = "Special",
		accuracy = 1,
		pp = 25,
		priority = 0,
		targeting = "SingleOpponent",
		makesContact = false,
		effects = { { kind = "Damage", power = 60, damageClass = "Special" } },
		description = "Air drawn thin and cold enough that crossing it costs something.",
	}),

	move({
		id = "frost.rimeshard",
		name = "Rimeshard",
		typeId = "Frost",
		category = "Special",
		accuracy = 0.95,
		pp = 20,
		priority = 0,
		targeting = "SingleOpponent",
		makesContact = false,
		effects = {
			{
				kind = "Damage",
				power = 25,
				damageClass = "Special",
				hitsRange = { min = 2, max = 5 },
			},
		},
		description = "A scatter of ice splinters, two to five of which find their mark.",
	}),

	-- The revenge killer's tool: weak, fast, and it goes first.
	move({
		id = "storm.voltlance",
		name = "Voltlance",
		typeId = "Storm",
		category = "Physical",
		accuracy = 1,
		pp = 30,
		priority = 1,
		targeting = "SingleOpponent",
		makesContact = false,
		effects = { { kind = "Damage", power = 40, damageClass = "Physical" } },
		description = "A thrown spear of charge that arrives before the thought behind it.",
	}),

	-- The starter baseline, three of three. Physical, because the Terra line is a Tank
	-- built on attack and its endgame move is physical too.
	move({
		id = "terra.gravelmaul",
		name = "Gravelmaul",
		typeId = "Terra",
		category = "Physical",
		accuracy = 1,
		pp = 25,
		priority = 0,
		targeting = "SingleOpponent",
		makesContact = true,
		effects = { { kind = "Damage", power = 60, damageClass = "Physical" } },
		description = "A fistful of loose ground swung with the arm still attached to it.",
	}),

	move({
		id = "terra.stoneheave",
		name = "Stoneheave",
		typeId = "Terra",
		category = "Physical",
		accuracy = 0.9,
		pp = 10,
		priority = 0,
		targeting = "SingleOpponent",
		makesContact = false,
		effects = { { kind = "Damage", power = 110, damageClass = "Physical" } },
		description = "The ground is lifted and dropped somewhere it was not.",
	}),

	-- The pivot: hit, then leave. Momentum is the point, not the damage.
	move({
		id = "aqua.ebbstrike",
		name = "Ebbstrike",
		typeId = "Aqua",
		category = "Physical",
		accuracy = 1,
		pp = 25,
		priority = 0,
		targeting = "SingleOpponent",
		makesContact = true,
		effects = {
			{ kind = "Damage", power = 60, damageClass = "Physical" },
			{ kind = "SelfSwitch" },
		} :: { any },
		description = "Strike on the surge, withdraw on the pull.",
	}),

	--[[ Utility ------------------------------------------------------------- ]]

	-- Setup, physical. Ki is the type that boosts itself; this is why.
	move({
		id = "ki.kindlecore",
		name = "Kindlecore",
		typeId = "Ki",
		category = "Status",
		accuracy = nil,
		pp = 20,
		priority = 0,
		targeting = "Self",
		makesContact = false,
		effects = { { kind = "StatStage", stat = "atk", delta = 2, target = "Self" } },
		description = "The user banks its own force and holds it.",
	}),

	-- Setup, special.
	move({
		id = "psyche.mindsharpen",
		name = "Mindsharpen",
		typeId = "Psyche",
		category = "Status",
		accuracy = nil,
		pp = 20,
		priority = 0,
		targeting = "Self",
		makesContact = false,
		effects = { { kind = "StatStage", stat = "spa", delta = 2, target = "Self" } },
		description = "Attention narrows to a single point.",
	}),

	-- Recovery, the thing that makes a wall a wall rather than a large target.
	move({
		id = "forge.replate",
		name = "Replate",
		typeId = "Forge",
		category = "Status",
		accuracy = nil,
		pp = 10,
		priority = 0,
		targeting = "Self",
		makesContact = false,
		effects = { { kind = "Heal", fractionOfMaxHp = 0.5, target = "Self" } },
		description = "Damaged plating is stripped and replaced mid-fight.",
	}),

	-- The cleric move: clears status from the whole party, not just the active.
	move({
		id = "aqua.cleansewell",
		name = "Cleansewell",
		typeId = "Aqua",
		category = "Status",
		accuracy = nil,
		pp = 10,
		priority = 0,
		targeting = "UserParty",
		makesContact = false,
		effects = { { kind = "CureStatus", target = "UserParty" } },
		description = "Clean water drawn up for everyone still standing behind you.",
	}),

	move({
		id = "forge.scatterbarb",
		name = "Scatterbarb",
		typeId = "Forge",
		category = "Status",
		accuracy = nil,
		pp = 20,
		priority = 0,
		targeting = "TargetSide",
		makesContact = false,
		effects = { { kind = "SetHazard", hazard = "Caltrops", layers = 1, target = "TargetSide" } },
		description = "Barbed scrap thrown across the ground they have to come back to.",
	}),

	move({
		id = "forge.bulwarkveil",
		name = "Bulwarkveil",
		typeId = "Forge",
		category = "Status",
		accuracy = nil,
		pp = 20,
		priority = 0,
		targeting = "UserSide",
		makesContact = false,
		effects = {
			{ kind = "SetSideCondition", condition = "Bulwark", duration = 5, target = "UserSide" },
		},
		description = "A braced screen that blunts everything physical for a while.",
	}),

	-- The trapper's tool. Trapping without counterplay is a design bug, so this is
	-- a status move: spending the turn is the counterplay window.
	move({
		id = "spirit.soulbind",
		name = "Soulbind",
		typeId = "Spirit",
		category = "Status",
		accuracy = 1,
		pp = 15,
		priority = 0,
		targeting = "SingleOpponent",
		makesContact = false,
		effects = { { kind = "Trap", target = "Target" } },
		description = "Something takes hold that does not let go while the user watches.",
	}),

	--[[
		Phazing. Negative priority is the cost: it always goes last, so it undoes a
		setup sweeper only after that sweeper has already had its turn.
	]]
	move({
		id = "spirit.hollowcall",
		name = "Hollowcall",
		typeId = "Spirit",
		category = "Status",
		accuracy = 1,
		pp = 20,
		priority = -6,
		targeting = "SingleOpponent",
		makesContact = false,
		effects = { { kind = "ForceSwitch", target = "Target" } },
		description = "A voice from nowhere that nothing wants to stay and hear.",
	}),

	move({
		id = "storm.sweepwind",
		name = "Sweepwind",
		typeId = "Storm",
		category = "Status",
		accuracy = nil,
		pp = 15,
		priority = 0,
		targeting = "UserSide",
		makesContact = false,
		effects = {
			{ kind = "ClearSide", hazards = true, sideConditions = true, target = "UserSide" },
		},
		description = "One hard gust and the ground in front of you is clean again.",
	}),
}

--[[ Indexing -------------------------------------------------------------- ]]

local MOVES: { [string]: Move } = {}
local MOVE_IDS: { string } = {}

for _, entry in MOVE_LIST do
	if MOVES[entry.id] ~= nil then
		error(`Moves: duplicate move id "{entry.id}"`)
	end
	MOVES[entry.id] = entry
	table.insert(MOVE_IDS, entry.id)
end

--[[
	Which move demonstrates which competitive role.

	This is a reference map, not a constraint on the move itself — a move is data and
	has no opinion about who uses it. It exists so the data validator can assert that
	no role was left without a tool, which is the check that actually matters: a role
	with nothing to do is a role that gets ignored, and roles are how a player
	understands what a character is for.
]]
local ROLE_REFERENCE: { [string]: { string } } = {
	PhysicalSweeper = { "martial.sunderpalm", "spirit.wraithgrasp" },
	SpecialSweeper = { "psyche.mindfracture", "flame.cinderlash" },
	SetupSweeper = { "ki.kindlecore", "psyche.mindsharpen" },
	Wallbreaker = { "feral.rendclaw" },
	PhysicalWall = { "forge.replate", "forge.bulwarkveil" },
	SpecialWall = { "forge.replate", "aqua.cleansewell" },
	Pivot = { "aqua.ebbstrike" },
	RevengeKiller = { "storm.voltlance" },
	Tank = { "forge.replate", "terra.stoneheave" },
	Support = { "aqua.cleansewell", "forge.bulwarkveil", "storm.sweepwind" },
	HazardSetter = { "forge.scatterbarb" },
	Trapper = { "spirit.soulbind", "spirit.hollowcall" },
}

--[[ Lookup ---------------------------------------------------------------- ]]

--[[
	Signature-compatible with BattleDex.getMove in Battle/TurnResolver.luau, which is
	how the real table reaches the engine without the engine importing this file.
	Errors rather than returning nil: a move id that does not resolve is a data bug,
	and the only useful moment to find out is immediately.
]]
local function getMove(moveId: string): Move
	local entry = MOVES[moveId]
	if entry == nil then
		error(`Moves: no move with id "{moveId}"`)
	end
	return entry
end

local function has(moveId: string): boolean
	return MOVES[moveId] ~= nil
end

return {
	MOVES = MOVES,
	MOVE_IDS = MOVE_IDS,
	MOVE_LIST = MOVE_LIST,
	ROLE_REFERENCE = ROLE_REFERENCE,
	getMove = getMove,
	has = has,
}
