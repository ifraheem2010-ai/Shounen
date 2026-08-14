--!strict
--[[
	The complete state of one battle, as plain data.

	Two properties this shape has to keep, because everything else depends on them:

	1. IT IS SERIALISABLE. No functions, no Instances, no metatables, no cycles. A
	   BattleState can be written to a log, diffed, replayed, or shipped to a client
	   as-is. The moment a live object reference appears in here, deterministic replay
	   dies and so does the ability to reproduce a bug from a bug report.

	2. STATE PLUS SEED PLUS INTENTS FULLY DETERMINES THE NEXT STATE. `rngState` is in
	   the struct for exactly this reason. Given the same battle state and the same
	   intents, the engine must produce the same next state on any machine, forever.

	The engine treats this as immutable-ish: it returns a new state rather than
	mutating in place, so a caller can hold onto the previous turn for comparison.
]]

local CreatureInstanceModule = require(script.Parent.CreatureInstance)
local MoveEffectModule = require(script.Parent.MoveEffect)
local StatBlockModule = require(script.Parent.StatBlock)

type CreatureInstance = CreatureInstanceModule.CreatureInstance
type FieldId = MoveEffectModule.FieldId
type HazardId = MoveEffectModule.HazardId
type SideConditionId = MoveEffectModule.SideConditionId
type StagedStat = StatBlockModule.StagedStat
type StageBlock = StatBlockModule.StageBlock
type StatusId = MoveEffectModule.StatusId
type VolatileId = MoveEffectModule.VolatileId

-- Bump on any change to the shapes in this file, and add a migration. Rule #7.
local SCHEMA_VERSION = 1

export type VolatileState = {
	turnsRemaining: number?,
	-- Substitute HP, Encore's locked move, and similar per-volatile payloads.
	magnitude: number?,
	moveId: string?,
}

--[[ Per-creature battle-only state, discarded when it leaves the field. ]]
export type ActiveState = {
	partyIndex: number,
	stages: StageBlock,
	volatiles: { [VolatileId]: VolatileState },
	turnsOnField: number,
	lastMoveId: string?,
	-- Side id of whoever is trapping this creature, if anyone.
	trappedBySideId: number?,
}

export type SideState = {
	-- 1 or 2.
	id: number,
	displayName: string,
	-- 1 to 6 creatures.
	party: { CreatureInstance },
	active: ActiveState,
	-- Hazard id to layer count.
	hazards: { [HazardId]: number },
	-- Side condition id to turns remaining.
	sideConditions: { [SideConditionId]: number },
	-- Wild creatures can be caught and cannot switch. Trainers can do neither.
	isWild: boolean,
	-- nil for AI-controlled sides.
	controllingUserId: number?,
}

export type FieldState = {
	activeField: FieldId?,
	fieldTurnsRemaining: number,
}

export type BattleOutcome =
	"InProgress"
	| "Side1Win"
	| "Side2Win"
	| "Fled"
	| "Captured"
	-- Both sides' last creatures faint on the same turn.
	| "Draw"

export type MoveFailureReason =
	"NoPp"
	| "Flinched"
	| "FullyParalysed"
	| "Asleep"
	| "Frozen"
	| "Confused"
	| "Taunted"
	| "Blocked"
	| "NoTarget"
	| "NoEffect"

--[[ Battle log ------------------------------------------------------------- ]]

--[[
	Every event carries the side and the creature uid rather than a reference, so the
	log survives serialisation and can be replayed against a fresh state. The UI in P4
	renders from this log; it never reads the state directly, which is what keeps the
	animation layer from being able to disagree with the simulation.
]]
export type BattleEvent =
	{ kind: "TurnBegin", turn: number }
	| { kind: "SwitchOut", sideId: number, creatureUid: string }
	| { kind: "SwitchIn", sideId: number, creatureUid: string, partyIndex: number }
	| { kind: "MoveUsed", sideId: number, creatureUid: string, moveId: string }
	| { kind: "MoveMissed", sideId: number, creatureUid: string, moveId: string }
	| {
		kind: "MoveFailed",
		sideId: number,
		creatureUid: string,
		moveId: string?,
		reason: MoveFailureReason,
	}
	| {
		kind: "DamageDealt",
		sideId: number,
		creatureUid: string,
		amount: number,
		remainingHp: number,
		-- Type chart multiplier for this hit, so the UI can say "it's super effective"
		-- without recomputing it and risking a different answer.
		effectiveness: number,
		isCritical: boolean,
	}
	| { kind: "Healed", sideId: number, creatureUid: string, amount: number, remainingHp: number }
	| { kind: "Fainted", sideId: number, creatureUid: string }
	| { kind: "StatusInflicted", sideId: number, creatureUid: string, status: StatusId }
	| { kind: "StatusCured", sideId: number, creatureUid: string, status: StatusId }
	| {
		kind: "StatusDamage",
		sideId: number,
		creatureUid: string,
		status: StatusId,
		amount: number,
		remainingHp: number,
	}
	| {
		kind: "StatStageChanged",
		sideId: number,
		creatureUid: string,
		stat: StagedStat,
		delta: number,
		newStage: number,
	}
	| { kind: "VolatileApplied", sideId: number, creatureUid: string, volatileId: VolatileId }
	| { kind: "VolatileRemoved", sideId: number, creatureUid: string, volatileId: VolatileId }
	| { kind: "HazardSet", sideId: number, hazard: HazardId, layers: number }
	| { kind: "HazardDamage", sideId: number, creatureUid: string, hazard: HazardId, amount: number }
	| { kind: "SideCleared", sideId: number }
	| {
		kind: "SideConditionSet",
		sideId: number,
		condition: SideConditionId,
		turnsRemaining: number,
	}
	| { kind: "SideConditionEnded", sideId: number, condition: SideConditionId }
	| { kind: "FieldSet", field: FieldId, turnsRemaining: number }
	| { kind: "FieldEnded", field: FieldId }
	| { kind: "ItemUsed", sideId: number, itemId: string }
	| { kind: "CaptureAttempt", shakes: number, succeeded: boolean }
	| { kind: "FleeAttempt", succeeded: boolean }
	| { kind: "BattleEnded", outcome: BattleOutcome }

export type BattleState = {
	schemaVersion: number,
	battleId: string,
	seed: number,
	-- Advanced by every roll. State + seed + intents determines the next state.
	rngState: number,
	turn: number,
	-- Exactly two entries, indexed by side id.
	sides: { SideState },
	field: FieldState,
	outcome: BattleOutcome,
	-- Appended to, never rewritten.
	log: { BattleEvent },
}

local MAX_PARTY_SIZE = 6
local SIDE_COUNT = 2

local function opposingSideId(sideId: number): number
	return if sideId == 1 then 2 else 1
end

local function activeCreature(side: SideState): CreatureInstance
	local creature = side.party[side.active.partyIndex]
	if creature == nil then
		error(`side {side.id} has no creature at party index {side.active.partyIndex}`)
	end
	return creature
end

local function isOver(state: BattleState): boolean
	return state.outcome ~= "InProgress"
end

return {
	SCHEMA_VERSION = SCHEMA_VERSION,
	MAX_PARTY_SIZE = MAX_PARTY_SIZE,
	SIDE_COUNT = SIDE_COUNT,
	opposingSideId = opposingSideId,
	activeCreature = activeCreature,
	isOver = isOver,
}
