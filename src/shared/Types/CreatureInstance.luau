--!strict
--[[
	A single owned or wild creature — the thing that actually appears in a battle and
	gets written to a save file.

	Species is the template; this is the instance. Anything that differs between two
	creatures of the same species belongs here, and nothing that is identical across
	all of them does.

	SCHEMA CHANGES TO THIS TYPE BUMP schemaVersion AND ADD A MIGRATION. This shape
	goes to disk through ProfileStore, so a silent field rename is a data loss bug in
	someone's save, not a refactor.

	NATURES ARE DELIBERATELY ABSENT. They are a second hidden stat modifier layered on
	top of IVs, and adding them later is a migration; adding them now is a balance
	surface nobody has designed yet. If they arrive, they arrive as a field here with
	a version bump.
]]

local MoveEffectModule = require(script.Parent.MoveEffect)
local StatBlockModule = require(script.Parent.StatBlock)

type StatBlock = StatBlockModule.StatBlock
type StatusId = MoveEffectModule.StatusId

export type MoveSlot = {
	moveId: string,
	pp: number,
	maxPp: number,
}

export type CreatureInstance = {
	-- Stable unique id for this creature, assigned by the server at creation.
	uid: string,
	speciesId: string,
	nickname: string?,
	level: number,
	exp: number,
	-- 0..31 per stat.
	ivs: StatBlock,
	-- 0..252 per stat, 510 total.
	evs: StatBlock,
	currentHp: number,
	-- At most one non-volatile status at a time.
	status: StatusId?,
	-- Counts down for Sleep; nil for statuses that do not expire.
	statusTurns: number?,
	-- 1..4 slots.
	moves: { MoveSlot },
	heldItemId: string?,
	-- Retained across trades so the origin of a creature is always knowable.
	originalOwnerUserId: number?,
	caughtAtUnix: number?,
}

local MIN_LEVEL = 1
local MAX_LEVEL = 100
local MAX_MOVE_SLOTS = 4

local function isFainted(creature: CreatureInstance): boolean
	return creature.currentHp <= 0
end

local function hasUsablePp(creature: CreatureInstance): boolean
	for _, slot in creature.moves do
		if slot.pp > 0 then
			return true
		end
	end
	return false
end

return {
	MIN_LEVEL = MIN_LEVEL,
	MAX_LEVEL = MAX_LEVEL,
	MAX_MOVE_SLOTS = MAX_MOVE_SLOTS,
	isFainted = isFainted,
	hasUsablePp = hasUsablePp,
}
