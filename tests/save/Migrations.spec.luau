--!strict
--[[
	The save-format migration runner.

	The real step list is empty — version 1 is the first format that has ever
	existed, so there is no v0 in the wild. A migration framework with nothing to
	migrate would normally be untested scaffolding, which is exactly the trap
	CLAUDE.md warns about. The way out is the pattern the rest of this codebase
	already uses for the RNG, the dex and the controller: the runner takes its steps
	as an argument, so these tests drive it with synthetic ones and the runner is
	fully exercised before a single real migration exists.

	Synthetic steps here are the same idea as tests/fixtures/ — a real migration
	landing must not be able to redden the runner's own suite.

	The test that will matter most is at the bottom and is five lines long:
	"the real step list forms a complete path to the current version". The day
	someone bumps CURRENT_SCHEMA_VERSION and forgets the migration, that goes red.
	That is Absolute Rule 7, machine-checked instead of remembered.
]]

local TestKit = require(script.Parent.Parent.TestKit)
local Shared = script.Parent.Parent.Parent.Shared
local Migrations = require(Shared.Save.Migrations)
local ProfileSchema = require(Shared.Save.ProfileSchema)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect
local fail = TestKit.fail

type RawProfile = Migrations.RawProfile
type Step = Migrations.Step

local USER_ID = 1234567
local NOW = 1762300000

--[[
	A step that records that it ran, so ordering can be asserted rather than assumed.
	Two steps that both produce the right answer in the wrong order is a real class of
	migration bug: the second one overwrites a field the first one needed.
]]
local function tracingStep(to: number, trace: { number }): Step
	return {
		to = to,
		describe = `synthetic step to v{to}`,
		apply = function(data: RawProfile): RawProfile
			table.insert(trace, to)
			data[`touchedBy{to}`] = true
			return data
		end,
	}
end

local function okOrFail(result: Migrations.MigrateResult): Migrations.MigrateOk
	if not result.ok then
		fail(`expected the migration to succeed, got {result.code}: {result.reason}`)
	end
	return result :: Migrations.MigrateOk
end

local function errOrFail(result: Migrations.MigrateResult): Migrations.MigrateErr
	if result.ok then
		fail("expected the migration to be refused, but it succeeded")
	end
	return result :: Migrations.MigrateErr
end

describe("Migrations / a profile already at the target version", function()
	it("is returned unchanged, with no steps applied", function()
		local profile = ProfileSchema.newProfile(USER_ID, NOW)
		local trace: { number } = {}
		local result = okOrFail(Migrations.migrate(profile, { tracingStep(2, trace) }, 1))

		expect(#result.applied).toBe(0)
		expect(result.from).toBe(1)
		expect(result.to).toBe(1)
		expect(#trace).toBe(0)
	end)
end)

describe("Migrations / running a path", function()
	it("applies every step from the stored version to the target", function()
		local trace: { number } = {}
		local steps = { tracingStep(2, trace), tracingStep(3, trace), tracingStep(4, trace) }
		local result = okOrFail(Migrations.migrate({ schemaVersion = 1 }, steps, 4))

		expect(result.applied).toEqual({ 2, 3, 4 })
		expect(trace).toEqual({ 2, 3, 4 })
		expect(result.profile.schemaVersion).toBe(4)
	end)

	it("runs steps in version order even when the list is not sorted", function()
		-- A step list is hand-maintained. Depending on its order being correct is
		-- depending on nobody ever appending to the middle of it.
		local trace: { number } = {}
		local steps = { tracingStep(3, trace), tracingStep(2, trace) }
		okOrFail(Migrations.migrate({ schemaVersion = 1 }, steps, 3))

		expect(trace).toEqual({ 2, 3 })
	end)

	it("starts from the stored version, not from the beginning", function()
		local trace: { number } = {}
		local steps = { tracingStep(2, trace), tracingStep(3, trace), tracingStep(4, trace) }
		local result = okOrFail(Migrations.migrate({ schemaVersion = 3 }, steps, 4))

		expect(result.applied).toEqual({ 4 })
		expect(trace).toEqual({ 4 })
	end)

	it("loads a realistic old profile through a real-shaped step", function()
		--[[
			The thing BUILD_PLAN asks for: an old profile, loaded through a migration,
			asserted on the far side. The step is synthetic but the shape is not — a v1
			profile that predates a field, and a step that backfills it.
		]]
		local stored = ProfileSchema.newProfile(USER_ID, NOW) :: any
		stored.money = 4200
		stored.inventory = { ["item.ball"] = 7 }
		stored.badgeCount = nil

		local addBadges: Step = {
			to = 2,
			describe = "backfill badgeCount for profiles that predate badges",
			apply = function(data: RawProfile): RawProfile
				data.badgeCount = 0
				return data
			end,
		}

		local result = okOrFail(Migrations.migrate(stored, { addBadges }, 2))
		local migrated = result.profile :: any

		expect(migrated.badgeCount).toBe(0)
		expect(migrated.schemaVersion).toBe(2)
		-- Everything the step did not touch has to survive it. A migration that
		-- resets money is worse than one that fails.
		expect(migrated.money).toBe(4200)
		expect(migrated.inventory["item.ball"]).toBe(7)
		expect(migrated.ownerUserId).toBe(USER_ID)
		expect(migrated.createdAtUnix).toBe(NOW)
	end)
end)

describe("Migrations / the runner owns the version number", function()
	it("stamps the new version itself, so a step cannot forget to", function()
		-- Steps change shape. If each step also had to set schemaVersion, then the
		-- one step whose author forgot would leave a profile that migrates again on
		-- every single login, re-running a transform that is rarely idempotent.
		local forgetful: Step = {
			to = 2,
			describe = "a step that never touches schemaVersion",
			apply = function(data: RawProfile): RawProfile
				return data
			end,
		}

		local result = okOrFail(Migrations.migrate({ schemaVersion = 1 }, { forgetful }, 2))
		expect(result.profile.schemaVersion).toBe(2)
	end)

	it("overrides a step that sets the wrong version", function()
		local wrong: Step = {
			to = 2,
			describe = "a step that sets a version it has no business setting",
			apply = function(data: RawProfile): RawProfile
				data.schemaVersion = 99
				return data
			end,
		}

		local result = okOrFail(Migrations.migrate({ schemaVersion = 1 }, { wrong }, 2))
		expect(result.profile.schemaVersion).toBe(2)
	end)
end)

describe("Migrations / refusals", function()
	it("refuses a value that is not a table", function()
		expect(errOrFail(Migrations.migrate("not a profile", {}, 1)).code).toBe("not-a-table")
		expect(errOrFail(Migrations.migrate(42, {}, 1)).code).toBe("not-a-table")
		expect(errOrFail(Migrations.migrate(nil :: any, {}, 1)).code).toBe("not-a-table")
	end)

	it("refuses a profile with no version rather than assuming it is v1", function()
		--[[
			Versioning has existed since the first format, so a profile without a
			version is corrupt, not old. Treating it as v1 would run every migration
			over a blob of unknown shape and then save the result, which converts a
			readable corrupt save into an unreadable one.
		]]
		local result = errOrFail(Migrations.migrate({ money = 100 }, {}, 1))
		expect(result.code).toBe("missing-version")
	end)

	it("refuses a version that is not a positive integer", function()
		expect(errOrFail(Migrations.migrate({ schemaVersion = "1" }, {}, 1)).code).toBe(
			"bad-version"
		)
		expect(errOrFail(Migrations.migrate({ schemaVersion = 1.5 }, {}, 2)).code).toBe(
			"bad-version"
		)
		expect(errOrFail(Migrations.migrate({ schemaVersion = 0 }, {}, 1)).code).toBe("bad-version")
		expect(errOrFail(Migrations.migrate({ schemaVersion = -3 }, {}, 1)).code).toBe(
			"bad-version"
		)
	end)

	it("refuses a profile from the future instead of silently downgrading it", function()
		--[[
			THE DANGEROUS ONE. A player whose save was upgraded by a new server, then
			joining an older server during a staged rollout or a rollback. Loading it
			as-is would work perfectly and then drop every field the old code does not
			know about on the next save. A refused load costs that player one session.
			A silent downgrade costs them the save.
		]]
		local result = errOrFail(Migrations.migrate({ schemaVersion = 9 }, {}, 4))
		expect(result.code).toBe("from-the-future")
		expect(result.from).toBe(9)
	end)

	it("refuses a path with a gap, and applies nothing on the way to finding out", function()
		local trace: { number } = {}
		-- Has 2 and 4, needs 2, 3, 4. Running 2 and then discovering 3 is missing
		-- would leave a half-migrated profile.
		local steps = { tracingStep(2, trace), tracingStep(4, trace) }
		local result = errOrFail(Migrations.migrate({ schemaVersion = 1 }, steps, 4))

		expect(result.code).toBe("no-path")
		expect(#trace).toBe(0)
	end)

	it("refuses two steps claiming the same version", function()
		local trace: { number } = {}
		local steps = { tracingStep(2, trace), tracingStep(2, trace) }
		local result = errOrFail(Migrations.migrate({ schemaVersion = 1 }, steps, 2))

		expect(result.code).toBe("duplicate-step")
		expect(#trace).toBe(0)
	end)

	it("reports a step that throws, naming the version that failed", function()
		local trace: { number } = {}
		local exploding: Step = {
			to = 3,
			describe = "a step that throws",
			apply = function(_data: RawProfile): RawProfile
				error("the field I expected was not there")
			end,
		}
		local steps = { tracingStep(2, trace), exploding }
		local result = errOrFail(Migrations.migrate({ schemaVersion = 1 }, steps, 3))

		expect(result.code).toBe("step-failed")
		expect(result.from).toBe(3)
		expect(result.reason:find("the field I expected was not there") ~= nil).toBe(true)
	end)

	it("refuses a step that returns something that is not a table", function()
		local sloppy: Step = {
			to = 2,
			describe = "a step that forgets to return the profile",
			apply = function(_data: RawProfile): RawProfile
				return nil :: any
			end,
		}
		local result = errOrFail(Migrations.migrate({ schemaVersion = 1 }, { sloppy }, 2))
		expect(result.code).toBe("step-failed")
	end)
end)

describe("Migrations / the caller's data is never left half-migrated", function()
	it("does not mutate the input when a step throws midway", function()
		--[[
			The input is the table ProfileStore handed over, which is live session
			data. A failed migration that has already run two of four steps must not
			leave that table in a shape no version describes.
		]]
		local stored = { schemaVersion = 1, money = 500 } :: any
		local trace: { number } = {}
		local exploding: Step = {
			to = 3,
			describe = "a step that throws after an earlier one succeeded",
			apply = function(_data: RawProfile): RawProfile
				error("boom")
			end,
		}

		errOrFail(Migrations.migrate(stored, { tracingStep(2, trace), exploding }, 3))

		expect(stored.schemaVersion).toBe(1)
		expect(stored.money).toBe(500)
		expect(stored.touchedBy2).toBeNil()
	end)

	it("does not mutate the input on success either", function()
		local stored = { schemaVersion = 1, money = 500 } :: any
		local trace: { number } = {}

		local result = okOrFail(Migrations.migrate(stored, { tracingStep(2, trace) }, 2))

		expect(stored.schemaVersion).toBe(1)
		expect(stored.touchedBy2).toBeNil()
		expect((result.profile :: any).touchedBy2).toBe(true)
	end)

	it("copies nested tables, not just the top level", function()
		-- A shallow copy would hand the steps the caller's own inventory table, and
		-- a failed migration would leave the player's items changed.
		local stored = { schemaVersion = 1, inventory = { ["item.ball"] = 3 } } :: any
		local clearing: Step = {
			to = 2,
			describe = "a step that empties a nested table",
			apply = function(data: RawProfile): RawProfile
				local inventory = data.inventory :: any
				inventory["item.ball"] = nil
				return data
			end,
		}

		okOrFail(Migrations.migrate(stored, { clearing }, 2))
		expect(stored.inventory["item.ball"]).toBe(3)
	end)
end)

describe("Migrations / Absolute Rule 7, machine-checked", function()
	it("has a complete step path from version 1 to the current version", function()
		--[[
			This is the test the whole module exists for. Rule 7 says a schema change
			bumps the version and adds a migration. Bumping without the migration is
			the failure a code review misses, and it does not surface until a player
			with an old save logs in.
		]]
		local target = ProfileSchema.CURRENT_SCHEMA_VERSION
		local byVersion: { [number]: boolean } = {}
		for _, step in Migrations.STEPS do
			byVersion[step.to] = true
		end

		local missing: { number } = {}
		for version = 2, target do
			if not byVersion[version] then
				table.insert(missing, version)
			end
		end

		if #missing > 0 then
			fail(
				`CURRENT_SCHEMA_VERSION is {target} but Migrations.STEPS has no step producing `
					.. `version {table.concat(missing, ", ")}. A player with an older save `
					.. "cannot load. Absolute Rule 7: a schema change bumps the version AND "
					.. "adds a migration."
			)
		end
		expect(#missing).toBe(0)
	end)

	it("has no step for a version beyond the current one", function()
		for _, step in Migrations.STEPS do
			if step.to > ProfileSchema.CURRENT_SCHEMA_VERSION then
				fail(
					`there is a migration to version {step.to} but CURRENT_SCHEMA_VERSION is `
						.. `{ProfileSchema.CURRENT_SCHEMA_VERSION}. One of the two was not updated.`
				)
			end
		end
		expect(true).toBe(true)
	end)

	it("gives every real step a description, because the service logs it", function()
		for index, step in Migrations.STEPS do
			if step.describe == nil or #step.describe == 0 then
				fail(`step {index} (to v{step.to}) has no description`)
			end
		end
		expect(true).toBe(true)
	end)

	it("migrates a profile at the current version through the real step list", function()
		-- The real list, the real version, the real factory. Today this is a no-op and
		-- it should stay passing when it stops being one.
		local profile = ProfileSchema.newProfile(USER_ID, NOW)
		local result = okOrFail(
			Migrations.migrate(profile, Migrations.STEPS, ProfileSchema.CURRENT_SCHEMA_VERSION)
		)
		expect(result.profile.schemaVersion).toBe(ProfileSchema.CURRENT_SCHEMA_VERSION)
	end)

	it("ships no steps at all while version 1 is the only format", function()
		--[[
			Deliberately asserted so that the first real migration has to come here and
			delete this test. That is the moment to check the three above are still the
			right checks.
		]]
		expect(#Migrations.STEPS).toBe(0)
		expect(ProfileSchema.CURRENT_SCHEMA_VERSION).toBe(1)
	end)
end)
