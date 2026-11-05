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

	NATURES AND ABILITIES ARE RESERVED FIELDS, NOT IMPLEMENTED SYSTEMS. Both are
	confirmed to be coming (DECISIONS_P2.md P12). The fields exist from the first
	version of this schema so that their arrival is a backfill of something that was
	always absent, rather than a migration that retroactively assigns hidden stats to
	creatures people have already raised — which would silently change their numbers
	on next login with no in-game event to explain it.

	Nothing reads either field, no content is designed for either, and
	tests/save/ProfileSchema.spec.luau fails if any code in src/ starts touching them.
	That test is how "the field exists" is prevented from drifting into "the system
	exists". Implementing either means removing it from that spec's RESERVED list on
	purpose, and saying so in the decision log.
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

	--[[
		RESERVED (P12). Always nil today. See the header: these are fields without
		systems, and a test enforces that nothing reads them.
	]]
	nature: string?,
	abilityId: string?,
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
