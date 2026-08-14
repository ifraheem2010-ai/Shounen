--!strict
--[[
	The move effect vocabulary — a CLOSED set of 19 primitives.

	Absolute Rule #4: moves are data interpreted by the engine. The engine branches on
	`effect.kind`; it must never branch on a move id. If a move needs behaviour this
	vocabulary cannot express, the fix is to add a primitive here — never to add
	`if moveId == "X"` to the engine. The first special case is the one that ends the
	data-driven design, because the second one is always easier to justify than the
	first.

	HOW A MOVE RESOLVES
	-------------------
	A move carries an ordered list of effects. The engine walks them in order against
	a turn-local context, so later effects can read what earlier ones produced:
	`Damage` records the damage it dealt, and `Recoil` and `Drain` are defined in terms
	of that number. This ordering is why `Damage` is a primitive rather than an
	implicit property of the move — a move that drains has to be able to say
	"hit, THEN heal for half of what that hit did".

	ITEMS SHARE THIS VOCABULARY
	---------------------------
	A potion is `Heal`. A full heal is `CureStatus`. An X-Attack is `StatStage`. A ball
	is `Capture`. The item system therefore needs zero new interpreter code, which is
	the main reason `Capture` earns a slot in a list this tight.

	EVERY EFFECT SHARES TWO OPTIONAL FIELDS
	---------------------------------------
	`target`  who it lands on; defaults per-primitive, documented on each
	`chance`  0..1 probability, defaults to 1. Rolled with the INJECTED RNG only.

	DELIBERATELY ABSENT
	-------------------
	Conditional guards ("only if the target is poisoned"). Adding a condition grammar
	is how a closed vocabulary quietly becomes a scripting language. When a real move
	needs one, add a narrow primitive instead and write down why here.
]]

local MoveEffect = {}

--[[ Closed sub-vocabularies ------------------------------------------------ ]]

export type EffectTarget =
	"Self" -- the user
	| "Target" -- the move's chosen target
	| "AllActive" -- every creature currently on the field
	| "UserSide" -- the user's side of the field (hazards, screens)
	| "TargetSide" -- the opposing side of the field
	| "UserParty" -- every creature in the user's party, fainted or not
	| "Field" -- the field itself (weather, terrain, room)

-- The five Phase 1 statuses. Non-volatile: one at a time, persists across switches.
-- Badly-poisoned is a deliberate omission; it is a ramp mechanic and belongs to a
-- later phase, if ever.
export type StatusId = "Burn" | "Poison" | "Paralysis" | "Sleep" | "Freeze"

-- Volatile conditions clear on switch out. This is the vocabulary's pressure valve,
-- so it is the list most at risk of quietly growing — additions need a real move
-- that needs them.
export type VolatileId =
	"Confusion"
	| "Flinch"
	| "Protect"
	| "Endure"
	| "Substitute"
	| "LeechSeed"
	| "Taunt"
	| "Encore"
	| "Recharge" -- must spend next turn recharging
	| "Charging" -- two-turn move, currently winding up
	| "Locked" -- locked into repeating a move
	| "Bound" -- partially trapped, chip damage each turn
	| "FocusEnergy" -- raised crit stage

-- Entry hazards. Names are original by policy (see CLAUDE.md section 9) and are the
-- one part of this file data-architect may rename freely.
export type HazardId =
	"Caltrops" -- layered flat chip on entry
	| "Sigilstones" -- chip scaled by the type chart against the entrant
	| "Miasma" -- poisons on entry
	| "Snarewire" -- drops speed on entry

export type SideConditionId =
	"Bulwark" -- halves physical damage taken
	| "Veilward" -- halves special damage taken
	| "Slipstream" -- doubles speed
	| "Sanctuary" -- blocks status
	| "Mistveil" -- blocks stat drops

export type FieldId =
	"Emberveil" -- harsh light
	| "Downpour" -- rain
	| "Whiteout" -- hail
	| "Duststorm" -- sandstorm
	| "Inversion" -- slowest acts first

export type BoostableStat = "atk" | "def" | "spa" | "spd" | "spe" | "accuracy" | "evasion"

export type DamageClass = "Physical" | "Special"

export type EffectKind =
	"Damage"
	| "FixedDamage"
	| "Recoil"
	| "Drain"
	| "Heal"
	| "InflictStatus"
	| "CureStatus"
	| "StatStage"
	| "ResetStatStages"
	| "ApplyVolatile"
	| "RemoveVolatile"
	| "SetHazard"
	| "SetSideCondition"
	| "ClearSide"
	| "SetField"
	| "ForceSwitch"
	| "SelfSwitch"
	| "Trap"
	| "Capture"

--[[ 1. Damage -------------------------------------------------------------- ]]

-- Standard Gen-5 damage formula. Defaults to target = "Target".
export type DamageEffect = {
	kind: "Damage",
	target: EffectTarget?,
	chance: number?,
	power: number,
	damageClass: DamageClass,
	-- Exactly one of `hits` or `hitsRange`. Neither means a single hit.
	hits: number?,
	hitsRange: { min: number, max: number }?,
	-- Added to the crit stage for this move only.
	critStageBonus: number?,
	-- Ignores the target's positive defensive stat stages.
	ignoresDefenseBoosts: boolean?,
	-- Set false for typeless damage. Defaults true.
	respectsTypeChart: boolean?,
}

--[[ 2. FixedDamage --------------------------------------------------------- ]]

-- Damage that ignores the formula entirely. Defaults to target = "Target".
export type FixedDamageEffect = {
	kind: "FixedDamage",
	target: EffectTarget?,
	chance: number?,
	mode: "Flat" -- `value` HP, exactly
		| "UserLevel" -- HP equal to the user's level
		| "TargetCurrentHpFraction", -- `value` x the target's current HP
	value: number?,
}

--[[ 3. Recoil -------------------------------------------------------------- ]]

-- Self-damage. Always hits the user; `target` is ignored.
-- Exactly one of the two fractions must be set.
export type RecoilEffect = {
	kind: "Recoil",
	chance: number?,
	fractionOfDamageDealt: number?,
	fractionOfUserMaxHp: number?,
}

--[[ 4. Drain --------------------------------------------------------------- ]]

-- Heals the user for a fraction of the damage this move already dealt, so it must
-- come after a Damage effect in the list.
export type DrainEffect = {
	kind: "Drain",
	chance: number?,
	fractionOfDamageDealt: number,
}

--[[ 5. Heal ---------------------------------------------------------------- ]]

-- Defaults to target = "Self". Exactly one of the two amounts must be set.
export type HealEffect = {
	kind: "Heal",
	target: EffectTarget?,
	chance: number?,
	fractionOfMaxHp: number?,
	flat: number?,
}

--[[ 6. InflictStatus ------------------------------------------------------- ]]

-- Defaults to target = "Target".
export type InflictStatusEffect = {
	kind: "InflictStatus",
	target: EffectTarget?,
	chance: number?,
	status: StatusId,
}

--[[ 7. CureStatus ---------------------------------------------------------- ]]

-- Defaults to target = "Self". `statuses = nil` cures everything, which is how a
-- cleric move is written: target = "UserParty", statuses = nil.
export type CureStatusEffect = {
	kind: "CureStatus",
	target: EffectTarget?,
	chance: number?,
	statuses: { StatusId }?,
}

--[[ 8. StatStage ----------------------------------------------------------- ]]

-- The single primitive behind both setup and debuffs. Stages clamp to -6..+6.
-- `delta` must be non-zero.
--
-- ARCANE MAY NOT USE THIS AS SETUP. Arcane boosting itself is the mechanical wall
-- between Arcane and Ki; without it the two types collapse into one within twenty
-- characters. isSetup() below exists so the data validator can enforce that instead
-- of trusting everyone to remember it.
export type StatStageEffect = {
	kind: "StatStage",
	target: EffectTarget?,
	chance: number?,
	stat: BoostableStat,
	delta: number,
}

--[[ 9. ResetStatStages ----------------------------------------------------- ]]

-- Defaults to target = "AllActive". Setting neither flag clears every stage.
export type ResetStatStagesEffect = {
	kind: "ResetStatStages",
	target: EffectTarget?,
	chance: number?,
	onlyPositive: boolean?,
	onlyNegative: boolean?,
}

--[[ 10. ApplyVolatile ------------------------------------------------------ ]]

-- Defaults to target = "Target". `duration = nil` means the volatile's own default.
export type ApplyVolatileEffect = {
	kind: "ApplyVolatile",
	target: EffectTarget?,
	chance: number?,
	volatile: VolatileId,
	duration: number?,
}

--[[ 11. RemoveVolatile ----------------------------------------------------- ]]

export type RemoveVolatileEffect = {
	kind: "RemoveVolatile",
	target: EffectTarget?,
	chance: number?,
	volatile: VolatileId,
}

--[[ 12. SetHazard ---------------------------------------------------------- ]]

-- Defaults to target = "TargetSide". `layers` defaults to 1 and only matters for
-- hazards that stack.
export type SetHazardEffect = {
	kind: "SetHazard",
	target: EffectTarget?,
	chance: number?,
	hazard: HazardId,
	layers: number?,
}

--[[ 13. SetSideCondition --------------------------------------------------- ]]

-- Defaults to target = "UserSide". Screens and speed control live here.
export type SetSideConditionEffect = {
	kind: "SetSideCondition",
	target: EffectTarget?,
	chance: number?,
	condition: SideConditionId,
	duration: number,
}

--[[ 14. ClearSide ---------------------------------------------------------- ]]

-- Defaults to target = "UserSide". At least one flag must be true.
export type ClearSideEffect = {
	kind: "ClearSide",
	target: EffectTarget?,
	chance: number?,
	hazards: boolean?,
	sideConditions: boolean?,
}

--[[ 15. SetField ----------------------------------------------------------- ]]

-- Always hits the field; `target` is ignored.
export type SetFieldEffect = {
	kind: "SetField",
	chance: number?,
	field: FieldId,
	duration: number,
}

--[[ 16. ForceSwitch -------------------------------------------------------- ]]

-- Phazing. Defaults to target = "Target"; the replacement is chosen with the
-- injected RNG.
export type ForceSwitchEffect = {
	kind: "ForceSwitch",
	target: EffectTarget?,
	chance: number?,
}

--[[ 17. SelfSwitch --------------------------------------------------------- ]]

-- Pivoting. The user withdraws after the rest of the move resolves.
-- `passBoosts` carries stat stages to the replacement.
export type SelfSwitchEffect = {
	kind: "SelfSwitch",
	chance: number?,
	passBoosts: boolean?,
}

--[[ 18. Trap --------------------------------------------------------------- ]]

-- Defaults to target = "Target". Blocks switching while the user stays in.
-- Every trapper needs counterplay; a trapper without an out is a design bug, not a
-- strong character.
export type TrapEffect = {
	kind: "Trap",
	target: EffectTarget?,
	chance: number?,
	duration: number?,
}

--[[ 19. Capture ------------------------------------------------------------ ]]

-- Only legal from an item, and only against a wild creature. Defaults to
-- target = "Target". The server decides the outcome; the client is told.
export type CaptureEffect = {
	kind: "Capture",
	target: EffectTarget?,
	ballMultiplier: number,
	guaranteed: boolean?,
}

--[[ The union -------------------------------------------------------------- ]]

export type MoveEffect =
	DamageEffect
	| FixedDamageEffect
	| RecoilEffect
	| DrainEffect
	| HealEffect
	| InflictStatusEffect
	| CureStatusEffect
	| StatStageEffect
	| ResetStatStagesEffect
	| ApplyVolatileEffect
	| RemoveVolatileEffect
	| SetHazardEffect
	| SetSideConditionEffect
	| ClearSideEffect
	| SetFieldEffect
	| ForceSwitchEffect
	| SelfSwitchEffect
	| TrapEffect
	| CaptureEffect

--[[ Runtime constants ------------------------------------------------------ ]]

local EFFECT_KINDS: { EffectKind } = {
	"Damage",
	"FixedDamage",
	"Recoil",
	"Drain",
	"Heal",
	"InflictStatus",
	"CureStatus",
	"StatStage",
	"ResetStatStages",
	"ApplyVolatile",
	"RemoveVolatile",
	"SetHazard",
	"SetSideCondition",
	"ClearSide",
	"SetField",
	"ForceSwitch",
	"SelfSwitch",
	"Trap",
	"Capture",
}

local EFFECT_TARGETS: { EffectTarget } =
	{ "Self", "Target", "AllActive", "UserSide", "TargetSide", "UserParty", "Field" }

local STATUS_IDS: { StatusId } = { "Burn", "Poison", "Paralysis", "Sleep", "Freeze" }

local VOLATILE_IDS: { VolatileId } = {
	"Confusion",
	"Flinch",
	"Protect",
	"Endure",
	"Substitute",
	"LeechSeed",
	"Taunt",
	"Encore",
	"Recharge",
	"Charging",
	"Locked",
	"Bound",
	"FocusEnergy",
}

local HAZARD_IDS: { HazardId } = { "Caltrops", "Sigilstones", "Miasma", "Snarewire" }

local SIDE_CONDITION_IDS: { SideConditionId } =
	{ "Bulwark", "Veilward", "Slipstream", "Sanctuary", "Mistveil" }

local FIELD_IDS: { FieldId } = { "Emberveil", "Downpour", "Whiteout", "Duststorm", "Inversion" }

local BOOSTABLE_STATS: { BoostableStat } =
	{ "atk", "def", "spa", "spd", "spe", "accuracy", "evasion" }

-- Where each primitive lands when the move does not say.
local DEFAULT_TARGETS: { [EffectKind]: EffectTarget } = {
	Damage = "Target",
	FixedDamage = "Target",
	Recoil = "Self",
	Drain = "Self",
	Heal = "Self",
	InflictStatus = "Target",
	CureStatus = "Self",
	StatStage = "Target",
	ResetStatStages = "AllActive",
	ApplyVolatile = "Target",
	RemoveVolatile = "Target",
	SetHazard = "TargetSide",
	SetSideCondition = "UserSide",
	ClearSide = "UserSide",
	SetField = "Field",
	ForceSwitch = "Target",
	SelfSwitch = "Self",
	Trap = "Target",
	Capture = "Target",
}

local MAX_STAT_STAGE = 6
local MIN_STAT_STAGE = -6

--[[ Helpers ---------------------------------------------------------------- ]]

local KIND_SET: { [string]: boolean } = {}
for _, kind in EFFECT_KINDS do
	KIND_SET[kind] = true
end

local TARGET_SET: { [string]: boolean } = {}
for _, target in EFFECT_TARGETS do
	TARGET_SET[target] = true
end

local function targetOf(effect: MoveEffect): EffectTarget
	local explicit = (effect :: any).target
	if explicit ~= nil then
		return explicit
	end
	return DEFAULT_TARGETS[effect.kind]
end

local function chanceOf(effect: MoveEffect): number
	local explicit = (effect :: any).chance
	return if explicit == nil then 1 else explicit
end

--[[
	True when this effect boosts the user's own stats — i.e. it is setup.

	The data validator uses this to enforce "Arcane gets no setup moves", which is a
	mechanical wall and not a flavour preference. Ki boosts itself; Arcane manipulates
	the opponent. Delete the wall and the two types are the same type.
]]
local function isSetup(effect: MoveEffect): boolean
	if effect.kind ~= "StatStage" then
		return false
	end
	local target = targetOf(effect)
	return effect.delta > 0 and (target == "Self" or target == "UserSide")
end

local function isDamaging(effect: MoveEffect): boolean
	return effect.kind == "Damage" or effect.kind == "FixedDamage"
end

--[[
	Structural validation of a single effect. Returns a list of problems; empty means
	the effect is well-formed. This checks SHAPE, not balance — a 999-power move
	passes here and gets rejected by the data validator.
]]
local function validate(effect: MoveEffect): { string }
	local problems: { string } = {}

	local function require_(condition: boolean, message: string)
		if not condition then
			table.insert(problems, message)
		end
	end

	if not KIND_SET[effect.kind] then
		return { `unknown effect kind "{tostring(effect.kind)}"` }
	end

	local rawTarget = (effect :: any).target
	if rawTarget ~= nil and not TARGET_SET[rawTarget] then
		table.insert(problems, `unknown target "{tostring(rawTarget)}"`)
	end

	local chance = chanceOf(effect)
	require_(chance > 0 and chance <= 1, `chance must be in (0, 1], got {chance}`)

	if effect.kind == "Damage" then
		require_(effect.power > 0, `Damage.power must be positive, got {effect.power}`)
		require_(
			effect.hits == nil or effect.hitsRange == nil,
			"Damage cannot set both hits and hitsRange"
		)
		if effect.hitsRange ~= nil then
			require_(
				effect.hitsRange.min >= 1 and effect.hitsRange.max >= effect.hitsRange.min,
				"Damage.hitsRange must satisfy 1 <= min <= max"
			)
		end
	elseif effect.kind == "FixedDamage" then
		if effect.mode == "UserLevel" then
			require_(effect.value == nil, "FixedDamage mode UserLevel takes no value")
		else
			require_(effect.value ~= nil, `FixedDamage mode {effect.mode} requires a value`)
		end
	elseif effect.kind == "Recoil" then
		local a = effect.fractionOfDamageDealt ~= nil
		local b = effect.fractionOfUserMaxHp ~= nil
		require_(
			(a or b) and not (a and b),
			"Recoil needs exactly one of fractionOfDamageDealt or fractionOfUserMaxHp"
		)
	elseif effect.kind == "Drain" then
		require_(effect.fractionOfDamageDealt > 0, "Drain.fractionOfDamageDealt must be positive")
	elseif effect.kind == "Heal" then
		local a = effect.fractionOfMaxHp ~= nil
		local b = effect.flat ~= nil
		require_((a or b) and not (a and b), "Heal needs exactly one of fractionOfMaxHp or flat")
	elseif effect.kind == "StatStage" then
		require_(effect.delta ~= 0, "StatStage.delta must be non-zero")
		require_(
			effect.delta >= MIN_STAT_STAGE and effect.delta <= MAX_STAT_STAGE,
			`StatStage.delta must be within {MIN_STAT_STAGE}..{MAX_STAT_STAGE}, got {effect.delta}`
		)
	elseif effect.kind == "ResetStatStages" then
		require_(
			not (effect.onlyPositive == true and effect.onlyNegative == true),
			"ResetStatStages cannot set both onlyPositive and onlyNegative"
		)
	elseif effect.kind == "SetSideCondition" then
		require_(effect.duration > 0, "SetSideCondition.duration must be positive")
	elseif effect.kind == "ClearSide" then
		require_(
			effect.hazards == true or effect.sideConditions == true,
			"ClearSide must clear hazards, side conditions, or both"
		)
	elseif effect.kind == "SetField" then
		require_(effect.duration > 0, "SetField.duration must be positive")
	elseif effect.kind == "Capture" then
		require_(effect.ballMultiplier > 0, "Capture.ballMultiplier must be positive")
	end

	return problems
end

MoveEffect.EFFECT_KINDS = EFFECT_KINDS
MoveEffect.EFFECT_TARGETS = EFFECT_TARGETS
MoveEffect.STATUS_IDS = STATUS_IDS
MoveEffect.VOLATILE_IDS = VOLATILE_IDS
MoveEffect.HAZARD_IDS = HAZARD_IDS
MoveEffect.SIDE_CONDITION_IDS = SIDE_CONDITION_IDS
MoveEffect.FIELD_IDS = FIELD_IDS
MoveEffect.BOOSTABLE_STATS = BOOSTABLE_STATS
MoveEffect.DEFAULT_TARGETS = DEFAULT_TARGETS
MoveEffect.MAX_STAT_STAGE = MAX_STAT_STAGE
MoveEffect.MIN_STAT_STAGE = MIN_STAT_STAGE

MoveEffect.targetOf = targetOf
MoveEffect.chanceOf = chanceOf
MoveEffect.isSetup = isSetup
MoveEffect.isDamaging = isDamaging
MoveEffect.validate = validate

return MoveEffect
