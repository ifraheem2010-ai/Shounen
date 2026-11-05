--!strict
--[[
	Save-format migrations.

	ABSOLUTE RULE 7: a schema change bumps CURRENT_SCHEMA_VERSION and adds a step
	here. tests/save/Migrations.spec.luau checks that the two stay in step, so the
	rule is machine-enforced rather than remembered — bumping the version without
	adding the migration goes red immediately instead of at the moment a player with
	an older save logs in.

	STEPS IS EMPTY AND THAT IS CORRECT. Version 1 is the first format that has ever
	existed and nothing has shipped, so there is no older save anywhere. The runner
	is still fully tested, because it takes its step list as an argument and the spec
	drives it with synthetic steps — the same injection the battle engine uses for
	the RNG and the dex, for the same reason: the thing under test should not have to
	wait for real content to exist.

	WHY THE RUNNER OWNS THE VERSION NUMBER. A step describes a shape change and
	nothing else; this module stamps schemaVersion after each one. If steps set it
	themselves, the one step whose author forgets leaves a profile that migrates again
	on every login, re-running a transform that is rarely idempotent.

	WHY IT WORKS ON A COPY. The input is the table ProfileStore handed over — live
	session data. A migration that fails after two of four steps must not leave that
	table in a shape no version describes, so steps run against a deep copy and the
	caller only adopts the result on success.

	WHAT IT REFUSES. All of these end the load rather than guessing, because every
	alternative writes something wrong back to disk:

	  no version        corrupt, not old — versioning has existed since v1
	  bad version       not a positive integer
	  from the future   a save upgraded by newer code, read by older code. Loading it
	                    would work and then silently drop every unknown field on the
	                    next save. A refused load costs one session; a silent
	                    downgrade costs the save.
	  no path           a gap in the step list. Detected before anything is applied.
	  duplicate step    two steps claiming the same version, so which one runs is
	                    down to list order
	  step failed       a step threw, or returned something that is not a profile
]]

local ProfileSchema = require(script.Parent.ProfileSchema)

type PlayerProfile = ProfileSchema.PlayerProfile

--[[
	Historical save data, whose exact type no longer exists in the codebase. This is
	the one place where loose typing is the correct answer rather than a shortcut: a
	migration's input is, by definition, a shape this version of the code does not
	have a type for.
]]
export type RawProfile = { [string]: unknown }

export type Step = {
	-- The version this step produces. A step to v3 upgrades a v2 profile.
	to: number,
	-- Logged by the service when the step runs, so a support question about a
	-- changed save has an answer.
	describe: string,
	apply: (RawProfile) -> RawProfile,
}

export type MigrateOk = {
	ok: true,
	-- The profile to adopt. On a no-op this is the input itself; after any step it
	-- is a fresh table.
	profile: PlayerProfile,
	from: number,
	to: number,
	-- The version each applied step produced, in the order they ran.
	applied: { number },
}

export type MigrateErr = {
	ok: false,
	code: "not-a-table"
		| "missing-version"
		| "bad-version"
		| "from-the-future"
		| "no-path"
		| "duplicate-step"
		| "step-failed",
	reason: string,
	-- The version involved in the refusal, where one is known: the stored version
	-- for from-the-future, the failing step's version for step-failed.
	from: number?,
}

export type MigrateResult = MigrateOk | MigrateErr

local function refuse(
	code: "not-a-table" | "missing-version" | "bad-version" | "from-the-future" | "no-path" | "duplicate-step" | "step-failed",
	reason: string,
	from: number?
): MigrateErr
	return { ok = false, code = code, reason = reason, from = from }
end

--[[
	Copies nested tables too. A shallow copy would hand the steps the caller's own
	inventory and party tables, so a failed migration would still have changed the
	player's items.
]]
local function deepCopy(value: unknown): unknown
	if type(value) ~= "table" then
		return value
	end

	local copy: { [unknown]: unknown } = {}
	for key, item in value :: { [unknown]: unknown } do
		copy[key] = deepCopy(item)
	end
	return copy
end

--[[
	Brings `raw` up to `targetVersion` using `steps`, or refuses and says why.

	`steps` is a parameter rather than a module lookup so that the runner can be
	tested without any real migration existing, and so a real migration landing
	cannot redden the runner's own tests.
]]
local function migrate(raw: unknown, steps: { Step }, targetVersion: number): MigrateResult
	if type(raw) ~= "table" then
		return refuse("not-a-table", `a saved profile must be a table, got {type(raw)}`)
	end

	local source = raw :: RawProfile
	local storedVersion = source.schemaVersion

	if storedVersion == nil then
		return refuse(
			"missing-version",
			"this profile has no schemaVersion. Versioning has existed since the first "
				.. "format, so a profile without one is corrupt rather than old, and running "
				.. "migrations over it would turn a readable corrupt save into an unreadable one"
		)
	end

	if type(storedVersion) ~= "number" then
		return refuse("bad-version", `schemaVersion must be a number, got {type(storedVersion)}`)
	end

	local from: number = storedVersion
	if from % 1 ~= 0 or from < 1 then
		return refuse("bad-version", `schemaVersion must be a positive integer, got {from}`)
	end

	if from > targetVersion then
		return refuse(
			"from-the-future",
			`this profile is version {from} but this server only understands {targetVersion}. `
				.. "Refusing rather than loading it, because loading it would work and then "
				.. "drop every field this version does not know about on the next save",
			from
		)
	end

	-- Index first, so two steps claiming one version is caught before anything runs.
	local byVersion: { [number]: Step } = {}
	for _, step in steps do
		if byVersion[step.to] ~= nil then
			return refuse(
				"duplicate-step",
				`two migration steps both produce version {step.to}, so which one runs `
					.. "depends on the order of the list",
				step.to
			)
		end
		byVersion[step.to] = step
	end

	-- Plan the whole path before applying any of it. Finding the gap halfway through
	-- would leave a half-migrated profile.
	local plan: { Step } = {}
	for version = from + 1, targetVersion do
		local step = byVersion[version]
		if step == nil then
			return refuse(
				"no-path",
				`no migration step produces version {version}, so a version {from} profile `
					.. `cannot reach version {targetVersion}`,
				version
			)
		end
		table.insert(plan, step)
	end

	if #plan == 0 then
		-- Already current. Hand back the input rather than a copy: no step ran, so
		-- there is nothing to isolate, and copying a full profile on every login is
		-- real work for no benefit.
		return { ok = true, profile = source :: any, from = from, to = from, applied = {} }
	end

	local working = deepCopy(source) :: RawProfile
	local applied: { number } = {}

	for _, step in plan do
		local succeeded, returned = pcall(step.apply, working)
		if not succeeded then
			return refuse(
				"step-failed",
				`the migration to version {step.to} ({step.describe}) threw: {tostring(returned)}`,
				step.to
			)
		end
		if type(returned) ~= "table" then
			return refuse(
				"step-failed",
				`the migration to version {step.to} ({step.describe}) returned {type(returned)} `
					.. "instead of a profile",
				step.to
			)
		end

		working = returned :: RawProfile
		-- The runner stamps the version, never the step.
		working.schemaVersion = step.to
		table.insert(applied, step.to)
	end

	return {
		ok = true,
		profile = working :: any,
		from = from,
		to = targetVersion,
		applied = applied,
	}
end

--[[
	The real step list, in no required order — the runner sorts by version.

	EMPTY ON PURPOSE. See the header. The first real entry looks like:

	    {
	        to = 2,
	        describe = "add badgeCount, defaulting to 0",
	        apply = function(data)
	            data.badgeCount = 0
	            return data
	        end,
	    }

	Do not set schemaVersion in a step; the runner does it.
]]
local STEPS: { Step } = {}

--[[
	What the save service calls: the real steps, up to the version this build
	understands.
]]
local function migrateToCurrent(raw: unknown): MigrateResult
	return migrate(raw, STEPS, ProfileSchema.CURRENT_SCHEMA_VERSION)
end

return {
	STEPS = STEPS,
	migrate = migrate,
	migrateToCurrent = migrateToCurrent,
}
