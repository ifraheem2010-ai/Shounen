--!strict
--[[
	Is this profile safe to put into a live session?

	Runs after Migrations, before anything reads the data. It answers with two lists
	rather than a boolean, because "bad save" is two different situations:

	  repairable  a number outside its range, a list over its cap, a count of zero.
	              There is exactly one correct value, so clamping is not a guess.
	              Repaired in place on a copy, and reported.
	  fatal       the data is ambiguous or unidentifiable. Two creatures sharing a
	              uid, a creature with no uid, a version that should already have
	              been migrated. Guessing picks a winner and discards someone's
	              creature.

	THE RULE FOR DECIDING WHICH. A wrong *type* is fatal — there is no way to clamp a
	string into a level without inventing a number. A wrong *value* of the right type
	is repairable. That line is mechanical, which is the point: the next person
	adding a field does not have to re-derive the philosophy.

	A fatal problem refuses the load, which costs the player a session and keeps
	their save intact. That is the right way round — ProfileStore will not overwrite
	a profile it never released, so a refused load loses nothing, while a guessed
	repair is written back to disk and is permanent.

	REPAIR NEVER DELETES A CREATURE. An over-sized party spills into storage; it does
	not lose the extras. Every clamp in here is reversible annoyance, and a vanished
	creature is the one thing a player will actually quit over.

	REPAIR IS A FIXED POINT. Validating a repaired profile reports nothing. Without
	that property every login repairs the same fields again and writes the same lines
	to the log forever, which is where a real bug would hide.

	WHAT IT DELIBERATELY DOES NOT CHECK:

	  The reserved fields. P12 reserves `nature` and `abilityId` and says nothing
	  reads them. Validating them would be reading them, and the spec that enforces
	  P12 would go red — correctly.

	  Whether a speciesId or moveId exists. That needs the content tables, and a save
	  must stay loadable while the content tables are being edited. A creature whose
	  species was renamed is a content migration, not a corrupt save.

	  The storage cap. The only way to repair an over-full storage is to delete
	  creatures, which this module does not do. The cap belongs at the point a
	  creature is added.
]]

local CreatureInstanceModule = require(script.Parent.Parent.Types.CreatureInstance)
local DeepCopy = require(script.Parent.DeepCopy)
local ProfileSchema = require(script.Parent.ProfileSchema)
local StatBlockModule = require(script.Parent.Parent.Types.StatBlock)

type PlayerProfile = ProfileSchema.PlayerProfile

export type Severity = "fatal" | "repairable"

export type Problem = {
	-- Where it was, in a form a log line can carry: "party[2].level".
	path: string,
	severity: Severity,
	message: string,
}

export type Options = {
	--[[
		Returns a creature's maximum HP, or nil if it cannot be worked out. Injected
		because the answer needs the species table and the stat formula, and this
		module must stay runnable without the content tables — the same reason the
		battle engine takes its dex rather than requiring it.

		Without it, current HP is only floored at zero. There is no correct ceiling to
		clamp to, and inventing one is worse than leaving the value alone.
	]]
	maxHpOf: ((any) -> number?)?,
}

export type Report = {
	ok: boolean,
	-- Non-nil exactly when ok. The repaired copy, which the caller should adopt.
	profile: PlayerProfile?,
	fatal: { Problem },
	repaired: { Problem },
}

local MIN_MOVE_SLOTS = 1

local STAT_IDS = StatBlockModule.STAT_IDS
local MAX_IV = StatBlockModule.MAX_IV
local MAX_EV_PER_STAT = StatBlockModule.MAX_EV_PER_STAT
local MAX_EV_TOTAL = StatBlockModule.MAX_EV_TOTAL

--[[ Problem collection ----------------------------------------------------- ]]

type Problems = { fatal: { Problem }, repaired: { Problem } }

local function addFatal(problems: Problems, path: string, message: string)
	table.insert(problems.fatal, { path = path, severity = "fatal" :: Severity, message = message })
end

local function addRepair(problems: Problems, path: string, message: string)
	table.insert(
		problems.repaired,
		{ path = path, severity = "repairable" :: Severity, message = message }
	)
end

--[[ Shape helpers ---------------------------------------------------------- ]]

--[[
	A contiguous 1..n table. Matters because DataStore round-trips through JSON,
	where an empty table loses the distinction between a list and a dictionary, and
	because a party that arrived as a dictionary breaks every `#` and `ipairs` that
	touches it later — silently, and only for the player whose save is odd.
]]
local function isArray(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end

	local asTable = value :: { [unknown]: unknown }
	local count = 0
	for _ in asTable do
		count += 1
	end
	for index = 1, count do
		if asTable[index] == nil then
			return false
		end
	end
	return true
end

local function isStatBlock(value: unknown): boolean
	if type(value) ~= "table" then
		return false
	end

	local asTable = value :: { [string]: unknown }
	for _, statId in STAT_IDS do
		if type(asTable[statId]) ~= "number" then
			return false
		end
	end
	return true
end

--[[
	Clamps `owner[key]` into range, reporting if it moved. Assumes the value is
	already known to be a number — a wrong type is fatal and handled before this.
]]
local function clampNumber(
	owner: { [string]: any },
	key: string,
	path: string,
	min: number,
	max: number?,
	problems: Problems
)
	local value = owner[key] :: number
	local clamped = math.max(value, min)
	if max ~= nil then
		clamped = math.min(clamped, max)
	end

	if clamped ~= value then
		owner[key] = clamped
		addRepair(problems, path, `was {value}, clamped to {clamped}`)
	end
end

--[[ Creature validation ---------------------------------------------------- ]]

local function validateStatSpread(
	creature: { [string]: any },
	key: string,
	path: string,
	maxPerStat: number,
	problems: Problems
)
	local spread = creature[key] :: { [string]: number }
	for _, statId in STAT_IDS do
		clampNumber(spread, statId, `{path}.{statId}`, 0, maxPerStat, problems)
	end
end

--[[
	Brings an EV spread under the total cap.

	Which stat to cut is genuinely ambiguous, so the rule is deterministic rather
	than clever: walk the stats in their canonical order and clamp each so the
	running total never passes the cap. Earlier stats keep what they have. Stated
	here because "deterministic" is only useful if it is written down somewhere a
	bug report can be checked against.
]]
local function capEvTotal(creature: { [string]: any }, path: string, problems: Problems)
	local evs = creature.evs :: { [string]: number }
	if StatBlockModule.totalOf(evs :: any) <= MAX_EV_TOTAL then
		return
	end

	local remaining = MAX_EV_TOTAL
	for _, statId in STAT_IDS do
		local value = evs[statId]
		local allowed = math.min(value, remaining)
		if allowed ~= value then
			evs[statId] = allowed
			addRepair(
				problems,
				`{path}.{statId}`,
				`was {value}, cut to {allowed} to fit the EV total`
			)
		end
		remaining -= allowed
	end
end

local function validateMoves(creature: { [string]: any }, path: string, problems: Problems): boolean
	if not isArray(creature.moves) then
		addFatal(problems, `{path}.moves`, "the move list is not a list")
		return false
	end

	local moves = creature.moves :: { { [string]: any } }

	if #moves < MIN_MOVE_SLOTS then
		--[[
			Fatal, not repairable. A creature with no moves cannot take a turn, and
			there is no correct move to invent for it — picking one would hand the
			player something they never taught it. A refused login is better than a
			battle that errors.
		]]
		addFatal(problems, `{path}.moves`, "a creature has no moves, so it cannot take a turn")
		return false
	end

	if #moves > CreatureInstanceModule.MAX_MOVE_SLOTS then
		local had = #moves
		for index = had, CreatureInstanceModule.MAX_MOVE_SLOTS + 1, -1 do
			moves[index] = nil
		end
		addRepair(
			problems,
			`{path}.moves`,
			`had {had} move slots, trimmed to {CreatureInstanceModule.MAX_MOVE_SLOTS}`
		)
	end

	for index, slot in moves do
		local slotPath = `{path}.moves[{index}]`
		if type(slot) ~= "table" then
			addFatal(problems, slotPath, "a move slot is not a table")
			return false
		end
		if type(slot.moveId) ~= "string" or #slot.moveId == 0 then
			addFatal(problems, slotPath, "a move slot has no moveId")
			return false
		end
		if type(slot.maxPp) ~= "number" or type(slot.pp) ~= "number" then
			addFatal(problems, slotPath, "a move slot has a non-numeric pp or maxPp")
			return false
		end

		clampNumber(slot, "maxPp", `{slotPath}.maxPp`, 0, nil, problems)
		clampNumber(slot, "pp", `{slotPath}.pp`, 0, slot.maxPp :: number, problems)
	end

	return true
end

local function validateCreature(
	creature: unknown,
	path: string,
	options: Options,
	problems: Problems
): boolean
	if type(creature) ~= "table" then
		addFatal(problems, path, `a creature must be a table, got {type(creature)}`)
		return false
	end

	local fields = creature :: { [string]: any }

	-- Identity first. A creature that cannot be named cannot be reported on, and
	-- every message below would say "a creature somewhere".
	if type(fields.uid) ~= "string" or #fields.uid == 0 then
		addFatal(problems, `{path}.uid`, "a creature has no uid, so it cannot be addressed")
		return false
	end
	if type(fields.speciesId) ~= "string" or #fields.speciesId == 0 then
		addFatal(problems, `{path}.speciesId`, "a creature has no speciesId")
		return false
	end

	for _, key in { "level", "exp", "currentHp" } do
		if type(fields[key]) ~= "number" then
			addFatal(problems, `{path}.{key}`, `{key} must be a number, got {type(fields[key])}`)
			return false
		end
	end

	if not isStatBlock(fields.ivs) then
		addFatal(problems, `{path}.ivs`, "the IV spread is missing a stat or has a non-number")
		return false
	end
	if not isStatBlock(fields.evs) then
		addFatal(problems, `{path}.evs`, "the EV spread is missing a stat or has a non-number")
		return false
	end

	if fields.nickname ~= nil and type(fields.nickname) ~= "string" then
		addFatal(problems, `{path}.nickname`, "a nickname that is not a string")
		return false
	end

	if not validateMoves(fields, path, problems) then
		return false
	end

	clampNumber(
		fields,
		"level",
		`{path}.level`,
		CreatureInstanceModule.MIN_LEVEL,
		CreatureInstanceModule.MAX_LEVEL,
		problems
	)
	clampNumber(fields, "exp", `{path}.exp`, 0, nil, problems)

	validateStatSpread(fields, "ivs", `{path}.ivs`, MAX_IV, problems)
	validateStatSpread(fields, "evs", `{path}.evs`, MAX_EV_PER_STAT, problems)
	capEvTotal(fields, `{path}.evs`, problems)

	local maxHpOf = options.maxHpOf
	local maxHp = if maxHpOf ~= nil then maxHpOf(fields) else nil
	clampNumber(fields, "currentHp", `{path}.currentHp`, 0, maxHp, problems)

	if fields.nickname ~= nil then
		local nickname = fields.nickname :: string
		if #nickname > ProfileSchema.MAX_NICKNAME_LENGTH then
			fields.nickname = nickname:sub(1, ProfileSchema.MAX_NICKNAME_LENGTH)
			addRepair(
				problems,
				`{path}.nickname`,
				`was {#nickname} characters, truncated to {ProfileSchema.MAX_NICKNAME_LENGTH}`
			)
		end
	end

	return true
end

--[[ Top level -------------------------------------------------------------- ]]

local NUMBER_FIELDS = {
	"ownerUserId",
	"createdAtUnix",
	"lastLoginUnix",
	"playtimeSeconds",
	"money",
	"nextCreatureSerial",
}

local MAP_FIELDS = { "inventory", "dexSeen", "dexCaught", "flags" }

local function validateTopLevelShape(profile: { [string]: any }, problems: Problems): boolean
	local storedVersion = profile.schemaVersion
	if storedVersion ~= ProfileSchema.CURRENT_SCHEMA_VERSION then
		--[[
			Fatal in both directions. Higher means this build is older than the save.
			Lower means migration did not run, and validating a stale shape against
			today's rules would "repair" fields that were correct for their version.
		]]
		addFatal(
			problems,
			"schemaVersion",
			`this profile is version {tostring(storedVersion)} but the current version is `
				.. `{ProfileSchema.CURRENT_SCHEMA_VERSION}. Migration should have run first.`
		)
		return false
	end

	for _, field in NUMBER_FIELDS do
		if type(profile[field]) ~= "number" then
			addFatal(problems, field, `{field} must be a number, got {type(profile[field])}`)
			return false
		end
	end

	for _, field in { "party", "storage" } do
		if not isArray(profile[field]) then
			addFatal(problems, field, `{field} is not a list`)
			return false
		end
	end

	for _, field in MAP_FIELDS do
		if type(profile[field]) ~= "table" then
			addFatal(problems, field, `{field} must be a table, got {type(profile[field])}`)
			return false
		end
	end

	if profile.starterSpeciesId ~= nil and type(profile.starterSpeciesId) ~= "string" then
		addFatal(problems, "starterSpeciesId", "a starter species that is not a string")
		return false
	end

	return true
end

--[[
	Moves the overflow out of the party and into storage.

	Not a deletion, and the order is preserved: the first six stay in the party, the
	rest go to the front of storage so they are easy to find rather than buried.
]]
local function spillOversizedParty(profile: { [string]: any }, problems: Problems)
	local party = profile.party :: { any }
	if #party <= ProfileSchema.MAX_PARTY_SIZE then
		return
	end

	local storage = profile.storage :: { any }
	local had = #party
	local spilled = 0

	for index = had, ProfileSchema.MAX_PARTY_SIZE + 1, -1 do
		table.insert(storage, 1, party[index])
		party[index] = nil
		spilled += 1
	end

	addRepair(
		problems,
		"party",
		`held {had} creatures, moved {spilled} into storage rather than losing them`
	)
end

--[[
	Drops entries that are not a positive whole count.

	A zero-count item is not a quantity, it is a leftover, and leaving it means the
	UI shows an item the player does not have.
]]
local function pruneInventory(profile: { [string]: any }, problems: Problems)
	local inventory = profile.inventory :: { [string]: any }
	local bad: { string } = {}

	for itemId, count in inventory do
		if type(itemId) ~= "string" or type(count) ~= "number" or count < 1 or count % 1 ~= 0 then
			table.insert(bad, tostring(itemId))
		end
	end

	for _, itemId in bad do
		inventory[itemId] = nil
		addRepair(problems, `inventory.{itemId}`, "was not a positive whole count, dropped")
	end
end

--[[
	Normalises the boolean-set fields. An entry that is not `true` carries no
	information a missing key does not, and keeping it means two shapes mean the same
	thing — which is the kind of thing one caller checks with `~= nil` and another
	with `== true`.
]]
local function pruneFlagSets(profile: { [string]: any }, problems: Problems)
	for _, field in MAP_FIELDS do
		if field == "inventory" then
			continue
		end

		local set = profile[field] :: { [string]: any }
		local bad: { string } = {}
		for key, value in set do
			if type(key) ~= "string" or value ~= true then
				table.insert(bad, tostring(key))
			end
		end
		for _, key in bad do
			set[key] = nil
			addRepair(problems, `{field}.{key}`, "was not set to true, dropped")
		end
	end
end

--[[
	The uid counter must never be behind the creatures that exist.

	If it is, the next mint produces a uid that is already in use, the duplicate is
	fatal on the following load, and the profile is bricked by its own save one
	creature at a time.

	Only this owner's serials count. A traded creature keeps the uid it was minted
	with, and counting it would push this profile's counter somewhere arbitrary.
]]
local function advanceUidCounter(profile: { [string]: any }, problems: Problems)
	local prefix = `{profile.ownerUserId}:`
	local highest = 0

	for _, list in { profile.party, profile.storage } do
		for _, creature in list :: { any } do
			local uid = creature.uid :: string
			if uid:sub(1, #prefix) == prefix then
				local serial = tonumber(uid:sub(#prefix + 1))
				if serial ~= nil and serial > highest then
					highest = serial
				end
			end
		end
	end

	local required = highest + 1
	if (profile.nextCreatureSerial :: number) < required then
		local was = profile.nextCreatureSerial
		profile.nextCreatureSerial = required
		addRepair(
			problems,
			"nextCreatureSerial",
			`was {was}, behind the highest minted serial {highest} — advanced to {required} so `
				.. "the next creature cannot reuse a uid"
		)
	end
end

local function findDuplicateUids(profile: { [string]: any }, problems: Problems)
	local seen: { [string]: string } = {}

	for _, listName in { "party", "storage" } do
		for index, creature in profile[listName] :: { any } do
			local uid = creature.uid :: string
			local firstSeenAt = seen[uid]
			if firstSeenAt ~= nil then
				addFatal(
					problems,
					`{listName}[{index}].uid`,
					`the uid {uid} is used by two creatures ({firstSeenAt} and `
						.. `{listName}[{index}]). Which one is which cannot be worked out here, `
						.. "and picking one would discard the other."
				)
			else
				seen[uid] = `{listName}[{index}]`
			end
		end
	end
end

--[[
	Validates and repairs a candidate profile, on a copy.

	The input is never modified, so a fatal verdict leaves the caller's data exactly
	as ProfileStore handed it over.
]]
local function validate(candidate: unknown, options: Options?): Report
	local problems: Problems = { fatal = {}, repaired = {} }
	local resolved: Options = options or {}

	if type(candidate) ~= "table" then
		addFatal(problems, "<root>", `a profile must be a table, got {type(candidate)}`)
		return { ok = false, profile = nil, fatal = problems.fatal, repaired = problems.repaired }
	end

	local profile = DeepCopy.copy(candidate) :: { [string]: any }

	local function refused(): Report
		return { ok = false, profile = nil, fatal = problems.fatal, repaired = problems.repaired }
	end

	if not validateTopLevelShape(profile, problems) then
		return refused()
	end

	for _, listName in { "party", "storage" } do
		for index, creature in profile[listName] :: { any } do
			if not validateCreature(creature, `{listName}[{index}]`, resolved, problems) then
				return refused()
			end
		end
	end

	-- After the per-creature pass, so every uid is known to be a usable string.
	findDuplicateUids(profile, problems)
	if #problems.fatal > 0 then
		return refused()
	end

	clampNumber(profile, "money", "money", 0, nil, problems)
	clampNumber(profile, "playtimeSeconds", "playtimeSeconds", 0, nil, problems)
	clampNumber(profile, "nextCreatureSerial", "nextCreatureSerial", 1, nil, problems)

	spillOversizedParty(profile, problems)
	pruneInventory(profile, problems)
	pruneFlagSets(profile, problems)
	advanceUidCounter(profile, problems)

	return {
		ok = true,
		profile = profile :: any,
		fatal = problems.fatal,
		repaired = problems.repaired,
	}
end

return {
	MIN_MOVE_SLOTS = MIN_MOVE_SLOTS,
	validate = validate,
}
