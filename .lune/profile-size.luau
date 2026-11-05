--!strict
--[[
	How close does a full save get to the DataStore ceiling?

	tests/save/ProfileSchema.spec.luau asserts that a maxed profile fits with headroom.
	That test answers yes or no. This prints the actual numbers, because the useful
	question is not "does it fit" but "how much room is left for the fields Phase 3
	has not added yet".

	A DataStore value is capped at 4 MB. Going over does not truncate the save — the
	write fails outright, and it fails for the player who has collected the most.

	Not part of the suite. Run with `lune run profile-size`.
]]

local serde = require("@lune/serde")
local shim = require("./roblox_require")

local root = shim.mount({ Shared = "src/shared", Tests = "tests" })
local CreatureInstance = shim.import(root, "Shared/Types/CreatureInstance")
local ProfileSchema = shim.import(root, "Shared/Save/ProfileSchema")

local USER_ID = 1234567
local NOW = 1762300000

local function maximalCreature(uid: string): any
	local moves = {}
	for index = 1, CreatureInstance.MAX_MOVE_SLOTS do
		table.insert(moves, {
			moveId = `discipline.averagelengthmoveid{index}`,
			pp = 99,
			maxPp = 99,
		})
	end

	return {
		uid = uid,
		speciesId = "flame.averagelengthspeciesid",
		nickname = string.rep("N", ProfileSchema.MAX_NICKNAME_LENGTH),
		level = CreatureInstance.MAX_LEVEL,
		exp = 1250000,
		ivs = { hp = 31, atk = 31, def = 31, spa = 31, spd = 31, spe = 31 },
		evs = { hp = 252, atk = 252, def = 6, spa = 0, spd = 0, spe = 0 },
		currentHp = 404,
		status = "burn",
		statusTurns = 5,
		moves = moves,
		heldItemId = "item.averagelengthitemid",
		originalOwnerUserId = USER_ID,
		caughtAtUnix = NOW,
		nature = "reserved",
		abilityId = "reserved",
	}
end

local function sizeOf(value: any): number
	return #serde.encode("json", value)
end

local function kb(bytes: number): string
	return string.format("%.1f KB", bytes / 1024)
end

print("")
print("profile size against the 4 MB DataStore limit")
print("")

local limit = ProfileSchema.DATASTORE_VALUE_LIMIT_BYTES

local empty = ProfileSchema.newProfile(USER_ID, NOW)
print(`  empty profile ................ {sizeOf(empty)} bytes`)
print(`  one maximal creature ......... {sizeOf(maximalCreature("1234567:1"))} bytes`)
print("")

local full = ProfileSchema.newProfile(USER_ID, NOW)
full.starterSpeciesId = "flame.emberlin"
full.money = 999999
full.playtimeSeconds = 10000000

for index = 1, ProfileSchema.MAX_PARTY_SIZE do
	table.insert(full.party, maximalCreature(`{USER_ID}:{index}`))
end
for index = 1, ProfileSchema.MAX_STORAGE_SIZE do
	table.insert(full.storage, maximalCreature(`{USER_ID}:{index + ProfileSchema.MAX_PARTY_SIZE}`))
end
for index = 1, 200 do
	full.dexSeen[`species.entry{index}`] = true
	full.dexCaught[`species.entry{index}`] = true
	full.inventory[`item.entry{index}`] = 999
	full.flags[`flag.entry{index}`] = true
end

local used = sizeOf(full)
local creatures = ProfileSchema.MAX_PARTY_SIZE + ProfileSchema.MAX_STORAGE_SIZE

print(`  party cap .................... {ProfileSchema.MAX_PARTY_SIZE}`)
print(`  storage cap .................. {ProfileSchema.MAX_STORAGE_SIZE}`)
print(`  dex / inventory / flags ...... 200 entries each`)
print("")
print(`  a completely full profile .... {kb(used)}  ({used} bytes)`)
print(`  the limit .................... {kb(limit)}`)
print(`  used ......................... {string.format("%.2f%%", used / limit * 100)}`)
print(`  headroom ..................... {kb(limit - used)}`)
print("")
print(
	`  at this creature size, the limit is reached at about {limit // sizeOf(maximalCreature("1234567:1"))} creatures,`
)
print(`  so the {creatures} the schema allows leaves the margin above.`)
print("")
