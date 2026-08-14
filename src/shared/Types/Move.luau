--!strict
--[[
	Move data.

	A move is a name, a type, an accuracy, and an ORDERED LIST OF EFFECTS. It has no
	behaviour of its own — the engine interprets the effects. See MoveEffect.luau.

	There is deliberately no `power` field here. Power lives on the Damage effect,
	because a move can contain more than one damaging step and because two copies of
	the same number drift apart. Use displayPower() when the UI needs one number.

	DAMAGE TIERS (docs/TYPES.md section 6). Moves should sit ON a tier, not between
	them; scattered values make the game impossible to reason about.
	   40 / 100% / +1 priority ....... revenge killing, finishing
	   60 / 100% ..................... early-game STAB, coverage on walls
	   75 / 100% ..................... reliable coverage
	   90 / 100% ..................... standard STAB, the workhorse tier
	  110 /  90% ..................... high-risk STAB
	  120 / 100% / 33% recoil ........ wallbreaker STAB
	  130 /  90% / recharge or -2 SpA. nuke. MAX 4 IN THE GAME
	   25 x2-5 / 95% ................. multi-hit
]]

local MoveEffectModule = require(script.Parent.MoveEffect)
local TypeIdModule = require(script.Parent.TypeId)

type MoveEffect = MoveEffectModule.MoveEffect
type TypeId = TypeIdModule.TypeId

-- Physical and Special decide which attack/defence pair the formula uses.
-- Status moves deal no damage; a Status move containing a Damage effect is a bug the
-- data validator rejects.
export type MoveCategory = "Physical" | "Special" | "Status"

export type MoveTargeting =
	"SingleOpponent"
	| "Self"
	| "AllOpponents"
	| "AllOthers"
	| "UserSide"
	| "TargetSide"
	| "UserParty"
	| "Field"

export type Move = {
	id: string,
	name: string,
	typeId: TypeId,
	category: MoveCategory,
	-- 0..1. nil means the move cannot miss.
	accuracy: number?,
	pp: number,
	-- -7..+5. Positive moves first. See docs/TYPES.md on priority discipline.
	priority: number,
	targeting: MoveTargeting,
	effects: { MoveEffect },
	makesContact: boolean?,
	description: string,
}

local MIN_PRIORITY = -7
local MAX_PRIORITY = 5

local CATEGORIES: { MoveCategory } = { "Physical", "Special", "Status" }

local TARGETINGS: { MoveTargeting } = {
	"SingleOpponent",
	"Self",
	"AllOpponents",
	"AllOthers",
	"UserSide",
	"TargetSide",
	"UserParty",
	"Field",
}

-- The tier table above, as data, so the validator can check membership rather than
-- relying on everyone having read the comment.
local DAMAGE_TIERS: { number } = { 40, 60, 75, 90, 110, 120, 130 }

-- Sum of the move's damaging power, for UI and for sorting. Returns 0 for status.
local function displayPower(move: Move): number
	local total = 0
	for _, effect in move.effects do
		if effect.kind == "Damage" then
			local hits = effect.hits or (if effect.hitsRange then effect.hitsRange.max else 1)
			total += effect.power * hits
		end
	end
	return total
end

local function isDamaging(move: Move): boolean
	for _, effect in move.effects do
		if MoveEffectModule.isDamaging(effect) then
			return true
		end
	end
	return false
end

-- Used to enforce "Arcane gets no setup moves".
local function isSetup(move: Move): boolean
	for _, effect in move.effects do
		if MoveEffectModule.isSetup(effect) then
			return true
		end
	end
	return false
end

return {
	MIN_PRIORITY = MIN_PRIORITY,
	MAX_PRIORITY = MAX_PRIORITY,
	CATEGORIES = CATEGORIES,
	TARGETINGS = TARGETINGS,
	DAMAGE_TIERS = DAMAGE_TIERS,
	displayPower = displayPower,
	isDamaging = isDamaging,
	isSetup = isSetup,
}
