--!strict
--[[
	The persisted player profile.

	Two of these tests are worth more than the rest put together:

	  "two fresh profiles share no mutable table" — the classic ProfileStore bug is a
	  template whose nested tables are handed out by reference, so the second player to
	  join mutates the first player's party. It passes every shallow test and surfaces
	  as a bug report about items vanishing.

	  "a maxed-out profile fits in a DataStore value" — the storage cap is not a
	  taste decision, it is 4 MB divided by the size of a creature. If that arithmetic
	  is wrong the save does not get truncated, it fails to write at all, and the
	  player who hit the cap is the one who loses everything.

	The reserved-field scan at the bottom is what P12 actually asked for: it makes
	"the field exists" unable to drift into "the system exists" without a test going
	red first.
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local TestKit = require(script.Parent.Parent.TestKit)
local Shared = script.Parent.Parent.Parent.Shared
local CreatureInstance = require(Shared.Types.CreatureInstance)
local ProfileSchema = require(Shared.Save.ProfileSchema)
local StatBlock = require(Shared.Types.StatBlock)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect
local fail = TestKit.fail

type PlayerProfile = ProfileSchema.PlayerProfile
type CreatureInstance = CreatureInstance.CreatureInstance

local USER_ID = 1234567
local NOW = 1762300000

--[[
	A creature built to be as large as the schema permits: the longest legal nickname,
	a full four move slots, every optional field present, and both reserved fields
	populated. The size test is only meaningful if it measures the worst case.
]]
local function maximalCreature(uid: string): CreatureInstance
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

describe("ProfileSchema / a fresh profile", function()
	it("is stamped with the current schema version", function()
		local profile = ProfileSchema.newProfile(USER_ID, NOW)
		expect(profile.schemaVersion).toBe(ProfileSchema.CURRENT_SCHEMA_VERSION)
	end)

	it("records the owner, so a creature uid can name who minted it", function()
		local profile = ProfileSchema.newProfile(USER_ID, NOW)
		expect(profile.ownerUserId).toBe(USER_ID)
	end)

	it("starts empty: no creatures, no starter, nothing earned", function()
		local profile = ProfileSchema.newProfile(USER_ID, NOW)
		expect(#profile.party).toBe(0)
		expect(#profile.storage).toBe(0)
		expect(profile.starterSpeciesId).toBeNil()
		expect(profile.money).toBe(0)
		expect(profile.playtimeSeconds).toBe(0)
		expect(next(profile.inventory)).toBeNil()
		expect(next(profile.dexSeen)).toBeNil()
		expect(next(profile.dexCaught)).toBeNil()
		expect(next(profile.flags)).toBeNil()
	end)

	it("takes both timestamps from the clock it was handed", function()
		local profile = ProfileSchema.newProfile(USER_ID, NOW)
		expect(profile.createdAtUnix).toBe(NOW)
		expect(profile.lastLoginUnix).toBe(NOW)
	end)

	it("reads its clock from the caller and never from os.time", function()
		-- A profile that stamps itself cannot be tested and cannot be replayed. The
		-- same argument as the injected RNG, applied to time.
		local source = fs.readFile("src/shared/Save/ProfileSchema.luau")
		expect(source:match("os%.time") == nil).toBe(true)
	end)
end)

describe("ProfileSchema / template aliasing", function()
	--[[
		Every one of these is the same bug in a different field. They are listed
		separately because a loop would report "aliasing" without saying which field,
		and the field is the entire diagnostic value.
	]]
	it("gives two profiles different party tables", function()
		local first = ProfileSchema.newProfile(USER_ID, NOW)
		local second = ProfileSchema.newProfile(USER_ID + 1, NOW)

		table.insert(first.party, maximalCreature("a"))

		expect(#first.party).toBe(1)
		expect(#second.party).toBe(0)
	end)

	it("gives two profiles different storage tables", function()
		local first = ProfileSchema.newProfile(USER_ID, NOW)
		local second = ProfileSchema.newProfile(USER_ID + 1, NOW)

		table.insert(first.storage, maximalCreature("a"))

		expect(#first.storage).toBe(1)
		expect(#second.storage).toBe(0)
	end)

	it("gives two profiles different inventory, dex and flag tables", function()
		local first = ProfileSchema.newProfile(USER_ID, NOW)
		local second = ProfileSchema.newProfile(USER_ID + 1, NOW)

		first.inventory["item.ball"] = 5
		first.dexSeen["flame.emberlin"] = true
		first.dexCaught["flame.emberlin"] = true
		first.flags["metTheProfessor"] = true

		expect(next(second.inventory)).toBeNil()
		expect(next(second.dexSeen)).toBeNil()
		expect(next(second.dexCaught)).toBeNil()
		expect(next(second.flags)).toBeNil()
	end)

	it("shares no table identity at all between two fresh profiles", function()
		-- The three tests above name the fields that exist today. This one catches the
		-- field added next year by someone who did not read them.
		local first = ProfileSchema.newProfile(USER_ID, NOW)
		local second = ProfileSchema.newProfile(USER_ID + 1, NOW)

		local shared: { string } = {}
		for key, value in first :: any do
			if type(value) == "table" and (second :: any)[key] == value then
				table.insert(shared, tostring(key))
			end
		end

		if #shared > 0 then
			fail(
				"these fields are the SAME table in two profiles, so one player's writes "
					.. `land in another player's save: {table.concat(shared, ", ")}`
			)
		end
		expect(#shared).toBe(0)
	end)
end)

describe("ProfileSchema / creature uid minting", function()
	it("mints a uid that names the owner, so uids survive a trade", function()
		local profile = ProfileSchema.newProfile(USER_ID, NOW)
		local uid = ProfileSchema.nextCreatureUid(profile)
		expect(uid:match(`^{USER_ID}:`) ~= nil).toBe(true)
	end)

	it("never repeats a uid within a profile", function()
		local profile = ProfileSchema.newProfile(USER_ID, NOW)
		local seen: { [string]: boolean } = {}

		for _ = 1, 500 do
			local uid = ProfileSchema.nextCreatureUid(profile)
			if seen[uid] then
				fail(`minted the uid {uid} twice`)
			end
			seen[uid] = true
		end

		expect(profile.nextCreatureSerial).toBe(501)
	end)

	it("keeps counting from the stored serial after a reload", function()
		-- The counter is the only thing standing between a reload and two creatures
		-- with the same uid, which is a silently merged pair in storage.
		local profile = ProfileSchema.newProfile(USER_ID, NOW)
		ProfileSchema.nextCreatureUid(profile)
		ProfileSchema.nextCreatureUid(profile)

		local reloaded = serde.decode("json", serde.encode("json", profile)) :: PlayerProfile
		local afterReload = ProfileSchema.nextCreatureUid(reloaded)

		expect(afterReload).toBe(`{USER_ID}:3`)
	end)

	it("mints uids that differ between two owners", function()
		local mine = ProfileSchema.newProfile(USER_ID, NOW)
		local theirs = ProfileSchema.newProfile(USER_ID + 1, NOW)

		expect(ProfileSchema.nextCreatureUid(mine)).never.toBe(
			ProfileSchema.nextCreatureUid(theirs)
		)
	end)
end)

describe("ProfileSchema / the storage cap is arithmetic, not taste", function()
	it("fits a completely full profile inside one DataStore value", function()
		local profile = ProfileSchema.newProfile(USER_ID, NOW)
		profile.starterSpeciesId = "flame.emberlin"
		profile.money = 999999
		profile.playtimeSeconds = 10000000

		for index = 1, ProfileSchema.MAX_PARTY_SIZE do
			table.insert(profile.party, maximalCreature(`{USER_ID}:{index}`))
		end
		for index = 1, ProfileSchema.MAX_STORAGE_SIZE do
			table.insert(
				profile.storage,
				maximalCreature(`{USER_ID}:{index + ProfileSchema.MAX_PARTY_SIZE}`)
			)
		end

		-- A dex and an inventory sized for a game several times larger than the slice.
		for index = 1, 200 do
			profile.dexSeen[`species.entry{index}`] = true
			profile.dexCaught[`species.entry{index}`] = true
			profile.inventory[`item.entry{index}`] = 999
			profile.flags[`flag.entry{index}`] = true
		end

		local encoded = serde.encode("json", profile)
		local used = #encoded
		local limit = ProfileSchema.DATASTORE_VALUE_LIMIT_BYTES

		if used >= limit then
			fail(
				`a maxed profile serialises to {used} bytes, over the {limit} byte DataStore `
					.. "limit. MAX_STORAGE_SIZE is too high — the save will fail to write "
					.. "entirely, it will not truncate."
			)
		end

		-- Headroom, not just a pass: fields get added, and the first one added after
		-- this test squeaks through at 99% is the one that breaks saving.
		expect(used).toBeLessThan(limit // 2)
	end)

	it("caps the party at six", function()
		expect(ProfileSchema.MAX_PARTY_SIZE).toBe(6)
	end)

	it("states the DataStore limit as the real 4 MB, not a guess", function()
		expect(ProfileSchema.DATASTORE_VALUE_LIMIT_BYTES).toBe(4 * 1024 * 1024)
	end)
end)

describe("ProfileSchema / reserved fields stay reserved (P12)", function()
	--[[
		P12: reserve `nature` and `abilityId` now, design no content, and do not let
		"the field exists" become "the system exists". That last clause is the one a
		human cannot enforce six months from now, so it is a test.

		When natures or abilities are actually implemented, THIS TEST FAILS. That is
		correct and intended. Deleting the field from RESERVED below is the deliberate
		act of saying the system now exists.
	]]
	local RESERVED = { "nature", "abilityId" }
	local DECLARED_IN = "src/shared/Types/CreatureInstance.luau"

	local function luauFilesUnder(dir: string, out: { string })
		for _, entry in fs.readDir(dir) do
			local full = `{dir}/{entry}`
			if fs.isDir(full) then
				luauFilesUnder(full, out)
			elseif full:match("%.luau$") ~= nil then
				table.insert(out, full)
			end
		end
		return out
	end

	it("declares both reserved fields on the persisted creature type", function()
		local declaration = fs.readFile(DECLARED_IN)
		for _, field in RESERVED do
			if declaration:match(`{field}%s*:`) == nil then
				fail(`{DECLARED_IN} does not declare the reserved field {field}`)
			end
		end
	end)

	for _, field in RESERVED do
		it(`has no code in src/ that reads or writes {field}`, function()
			local reads = { `%.{field}%f[%W]`, `{field}%s*=` }
			local hits: { string } = {}

			for _, path in luauFilesUnder("src", {}) do
				if path:gsub("\\", "/") == DECLARED_IN then
					continue
				end
				local lineNumber = 0
				for line in (fs.readFile(path) .. "\n"):gmatch("([^\n]*)\n") do
					lineNumber += 1
					for _, pattern in reads do
						if line:match(pattern) ~= nil then
							table.insert(hits, `{path}:{lineNumber}  {line:match("^%s*(.-)%s*$")}`)
							break
						end
					end
				end
			end

			if #hits > 0 then
				fail(
					`{field} is a RESERVED field — P12 says the field exists and nothing `
						.. "reads it. If that changed on purpose, remove it from RESERVED in "
						.. `this spec and say so in the decision log.\n{table.concat(hits, "\n")}`
				)
			end
			expect(#hits).toBe(0)
		end)
	end

	it("designs no content for either: no nature or ability table exists", function()
		-- "Reserve the field, leave it empty, design no content." A table of natures
		-- sitting unused in Data/ is content, however inert it looks.
		expect(fs.isFile("src/shared/Data/Natures.luau")).toBe(false)
		expect(fs.isFile("src/shared/Data/Abilities.luau")).toBe(false)
	end)
end)

describe("ProfileSchema / the EV and IV ceilings come from StatBlock", function()
	it("does not restate limits that already have one home", function()
		-- A second copy of MAX_EV_TOTAL is a second thing to forget to change.
		local source = fs.readFile("src/shared/Save/ProfileSchema.luau")
		expect(source:match("510") == nil).toBe(true)
		expect(StatBlock.MAX_EV_TOTAL).toBe(510)
	end)
end)
