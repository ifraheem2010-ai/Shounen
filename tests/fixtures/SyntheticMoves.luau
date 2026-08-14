--!strict
--[[
	SYNTHETIC NUMERIC FIXTURES FOR FORMULA VERIFICATION. NOT BALANCE DATA.

	Every number in this file was chosen to make an arithmetic property easy to check
	by hand — 100 base power against 100 attack and 100 defence at level 50 gives a
	round 46, so a broken truncation shows up immediately. None of it was chosen
	because it would make a good move. Do not read a design intent into any of it,
	do not cite it in a balance discussion, and do not copy it into the real table.

	THE REAL MOVE TABLE IS @data-architect's AND DOES NOT EXIST YET. There is no
	src/shared/Data/Moves.luau. When it lands it will be authored against the damage
	tiers in CLAUDE.md section 6, reviewed for the Arcane-no-setup rule, and validated
	by the data suite — none of which applies to anything here.

	This file lives in tests/ and must stay there. Nothing under src/shared/Data/ may
	ever reference it.

	WHY THESE ARE REAL Move VALUES RATHER THAN LOOSE NUMBERS
	-------------------------------------------------------
	DamageCalc takes a properly typed Move from Types/Move.luau. It would be easier to
	pass it a bare power number, and it would also be a lie: the signature would then
	have to change the day real moves arrive, and the tests written against the easy
	signature would all need rewriting at exactly the moment they matter most. These
	are Move-shaped values with arbitrary numbers in them, so the signature is already
	the final one.
]]

local Shared = script.Parent.Parent.Parent.Shared
local MoveModule = require(Shared.Types.Move)

type Move = MoveModule.Move

--[[
	Builds an arbitrary Move-shaped value.

	`effectExtra` lands on the Damage effect (power modifiers, hitsRange, opt-outs);
	`moveExtra` lands on the move itself (priority, accuracy). Exported because
	TurnResolver's tests need moves this file has no reason to name — a move that
	exists only to be slower than another one is not a fixture worth a constant.
]]
local function damagingMove(
	id: string,
	typeId: string,
	damageClass: string,
	power: number,
	effectExtra: { [string]: any }?,
	moveExtra: { [string]: any }?
): Move
	local effect: { [string]: any } = {
		kind = "Damage",
		power = power,
		damageClass = damageClass,
	}
	if effectExtra ~= nil then
		for key, value in effectExtra do
			effect[key] = value
		end
	end

	local move: { [string]: any } = {
		id = id,
		name = id,
		typeId = typeId,
		category = damageClass,
		accuracy = 1,
		pp = 10,
		priority = 0,
		targeting = "SingleOpponent",
		effects = { effect },
		makesContact = damageClass == "Physical",
		description = "Synthetic fixture. Not balance data.",
	}
	if moveExtra ~= nil then
		for key, value in moveExtra do
			move[key] = value
		end
	end

	return move :: any
end

--[[
	The workhorses. 100 power at level 50 with 100 attack into 100 defence produces a
	base of exactly 46, which is the number the three hand-verification cases are
	built on.
]]
local PHYSICAL_100_MARTIAL = damagingMove("fixture.physical100Martial", "Martial", "Physical", 100)
local SPECIAL_100_MARTIAL = damagingMove("fixture.special100Martial", "Martial", "Special", 100)

-- A Storm move exists solely to exercise the Storm -> Terra immunity.
local PHYSICAL_100_STORM = damagingMove("fixture.physical100Storm", "Storm", "Physical", 100)

-- Level 30 / 40 power / 50 attack / 100 defence gives a base of 7, the smallest
-- value where applying STAB before type effectiveness and applying it after produce
-- different answers. That makes it the only useful probe for ordering.
local PHYSICAL_40_MARTIAL = damagingMove("fixture.physical40Martial", "Martial", "Physical", 40)

-- Small enough that a resisted hit truncates to zero, which is what the
-- minimum-one-damage clamp is for.
local PHYSICAL_10_MARTIAL = damagingMove("fixture.physical10Martial", "Martial", "Physical", 10)

local TYPELESS_100_MARTIAL =
	damagingMove("fixture.typeless100", "Martial", "Physical", 100, { respectsTypeChart = false })

local IGNORES_BOOSTS_100_MARTIAL = damagingMove(
	"fixture.ignoresBoosts100",
	"Martial",
	"Physical",
	100,
	{ ignoresDefenseBoosts = true }
)

-- A move with no Damage effect at all, for the rejection path.
local STATUS_ONLY: Move = {
	id = "fixture.statusOnly",
	name = "fixture.statusOnly",
	typeId = "Arcane",
	category = "Status",
	accuracy = 1,
	pp = 10,
	priority = 0,
	targeting = "SingleOpponent",
	effects = { { kind = "InflictStatus", status = "Burn" } },
	makesContact = false,
	description = "Synthetic fixture. Not balance data.",
}

return {
	build = damagingMove,
	PHYSICAL_100_MARTIAL = PHYSICAL_100_MARTIAL,
	SPECIAL_100_MARTIAL = SPECIAL_100_MARTIAL,
	PHYSICAL_100_STORM = PHYSICAL_100_STORM,
	PHYSICAL_40_MARTIAL = PHYSICAL_40_MARTIAL,
	PHYSICAL_10_MARTIAL = PHYSICAL_10_MARTIAL,
	TYPELESS_100_MARTIAL = TYPELESS_100_MARTIAL,
	IGNORES_BOOSTS_100_MARTIAL = IGNORES_BOOSTS_100_MARTIAL,
	STATUS_ONLY = STATUS_ONLY,
}
