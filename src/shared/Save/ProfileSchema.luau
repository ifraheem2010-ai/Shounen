--!strict
--[[
	The shape that goes to disk.

	This module is deliberately inert: a type, some constants, and a factory. It
	performs no I/O, knows nothing about ProfileStore, and takes its clock from the
	caller. That is what makes the save format testable without a DataStore, and it
	is the same argument as the injected RNG in the battle engine — a module that
	reads the real clock cannot be replayed.

	ABSOLUTE RULE 7 LIVES HERE. Any change to `PlayerProfile` — a new field, a
	renamed field, a changed meaning for an existing field — bumps
	CURRENT_SCHEMA_VERSION and adds a step to Save/Migrations.luau. There is no
	version of this project where a silent save-format change is acceptable, because
	a field rename without a migration is not a refactor, it is data loss in a real
	person's save.

	The caps are not taste. MAX_STORAGE_SIZE exists because a DataStore value is
	capped at 4 MB and a full profile has to fit inside one with room to spare;
	tests/save/ProfileSchema.spec.luau does that arithmetic rather than trusting this
	comment. Raising a cap is not a schema change and needs no migration — the field
	already holds a list. Lowering one is, because it orphans creatures.
]]

local CreatureInstanceModule = require(script.Parent.Parent.Types.CreatureInstance)

type CreatureInstance = CreatureInstanceModule.CreatureInstance

--[[
	Version 1 is the first format that has ever existed. Nothing has shipped, so
	there is no v0 in the wild and Migrations.luau ships with an empty step list.
	That is not an untested framework: the runner is driven by injected steps and
	tests/save/Migrations.spec.luau exercises it with synthetic ones.
]]
local CURRENT_SCHEMA_VERSION = 1

local MAX_PARTY_SIZE = 6
local MAX_STORAGE_SIZE = 300
local MAX_NICKNAME_LENGTH = 20

-- Roblox's per-value DataStore limit. Stated here as the real number so the size
-- test measures against the constraint rather than against a round number someone
-- liked.
local DATASTORE_VALUE_LIMIT_BYTES = 4 * 1024 * 1024

export type PlayerProfile = {
	schemaVersion: number,

	--[[
		The owner is stored even though ProfileStore already keys by it, because a
		creature uid is minted from it. A profile that does not know whose it is mints
		uids that collide after a trade.
	]]
	ownerUserId: number,

	createdAtUnix: number,
	lastLoginUnix: number,
	playtimeSeconds: number,

	-- nil until the player picks one. The absence is the "new game" signal; a
	-- separate boolean flag for it would be a second source of truth.
	starterSpeciesId: string?,
	money: number,

	party: { CreatureInstance },
	storage: { CreatureInstance },

	--[[
		Monotonic, never reused, persisted. This counter is the only thing standing
		between a reload and two creatures sharing a uid, which presents as a pair in
		storage silently merging into one.
	]]
	nextCreatureSerial: number,

	dexSeen: { [string]: boolean },
	dexCaught: { [string]: boolean },

	-- itemId -> count. An absent key means zero; a key with 0 is a validation
	-- problem, not a quantity.
	inventory: { [string]: number },

	-- Open-ended progression switches. Deliberately untyped: story flags are
	-- content, and a closed enum of them would have to be edited by every quest.
	flags: { [string]: boolean },
}

--[[
	Every call builds its nested tables fresh.

	This function must never return a value that shares a table with anything,
	including a module-level template. ProfileStore deep-copies its own template, but
	this factory is also called directly, and a shared nested table means the second
	player to join writes into the first player's party. The spec asserts the absence
	of shared identity across every field, not just the ones that exist today.
]]
local function newProfile(ownerUserId: number, nowUnix: number): PlayerProfile
	return {
		schemaVersion = CURRENT_SCHEMA_VERSION,
		ownerUserId = ownerUserId,
		createdAtUnix = nowUnix,
		lastLoginUnix = nowUnix,
		playtimeSeconds = 0,
		starterSpeciesId = nil,
		money = 0,
		party = {},
		storage = {},
		nextCreatureSerial = 1,
		dexSeen = {},
		dexCaught = {},
		inventory = {},
		flags = {},
	}
end

--[[
	Mints the next creature uid and advances the counter.

	The owner id is part of the uid so that two creatures minted by two players can
	never collide, which matters the moment one is traded into the other's storage.
	The serial alone would collide immediately.
]]
local function nextCreatureUid(profile: PlayerProfile): string
	local serial = profile.nextCreatureSerial
	profile.nextCreatureSerial = serial + 1
	return `{profile.ownerUserId}:{serial}`
end

return {
	CURRENT_SCHEMA_VERSION = CURRENT_SCHEMA_VERSION,
	MAX_PARTY_SIZE = MAX_PARTY_SIZE,
	MAX_STORAGE_SIZE = MAX_STORAGE_SIZE,
	MAX_NICKNAME_LENGTH = MAX_NICKNAME_LENGTH,
	DATASTORE_VALUE_LIMIT_BYTES = DATASTORE_VALUE_LIMIT_BYTES,
	newProfile = newProfile,
	nextCreatureUid = nextCreatureUid,
}
