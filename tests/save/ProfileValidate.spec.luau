--!strict
--[[
	What to do with a profile that loaded but is not sane.

	The split that matters is fatal versus repairable, and the rule is whether there
	is exactly one obviously-correct value:

	  repairable  a number outside its range, a list over its cap, a count of zero.
	              Clamping is not a guess.
	  fatal       the data is ambiguous or unidentifiable — two creatures sharing a
	              uid, a creature with no uid, a version that should already have
	              been migrated. Guessing here picks a winner and discards someone's
	              creature.

	A fatal problem refuses the load. That costs the player a session and keeps
	their save intact, which is the right way round: ProfileStore will not overwrite
	what it never released.

	The invariant worth more than any single check is "repair never deletes a
	creature". Every clamp in here is reversible annoyance; a dropped creature is
	the one thing a player will actually quit over.
]]

local serde = require("@lune/serde")

local TestKit = require(script.Parent.Parent.TestKit)
local Shared = script.Parent.Parent.Parent.Shared
local ProfileSchema = require(Shared.Save.ProfileSchema)
local ProfileValidate = require(Shared.Save.ProfileValidate)
local StatBlock = require(Shared.Types.StatBlock)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect
local fail = TestKit.fail

type PlayerProfile = ProfileSchema.PlayerProfile

local USER_ID = 1234567
local NOW = 1762300000

local function creature(uid: string, overrides: { [string]: any }?): any
	local base: { [string]: any } = {
		uid = uid,
		speciesId = "flame.emberlin",
		level = 5,
		exp = 0,
		ivs = { hp = 20, atk = 20, def = 20, spa = 20, spd = 20, spe = 20 },
		evs = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
		currentHp = 20,
		moves = { { moveId = "flame.emberwake", pp = 25, maxPp = 25 } },
	}
	for key, value in overrides or {} do
		base[key] = value
	end
	return base
end

local function profileWith(party: { any }, storage: { any }?): any
	local profile = ProfileSchema.newProfile(USER_ID, NOW) :: any
	profile.party = party
	profile.storage = storage or {}
	profile.nextCreatureSerial = 1000
	return profile
end

local function pathsOf(problems: { ProfileValidate.Problem }): { string }
	local paths = {}
	for _, problem in problems do
		table.insert(paths, problem.path)
	end
	return paths
end

local function okOrFail(report: ProfileValidate.Report): PlayerProfile
	if not report.ok or report.profile == nil then
		fail(`expected a loadable profile, got fatal: {table.concat(pathsOf(report.fatal), ", ")}`)
	end
	return report.profile :: PlayerProfile
end

local function countCreatures(profile: PlayerProfile): number
	return #profile.party + #profile.storage
end

describe("ProfileValidate / the factory's own output", function()
	it("passes clean, with nothing fatal and nothing repaired", function()
		-- Ties the three save modules together: if newProfile ever produces something
		-- its own validator objects to, that is a contradiction and not a judgement
		-- call.
		local report = ProfileValidate.validate(ProfileSchema.newProfile(USER_ID, NOW))
		expect(#report.fatal).toBe(0)
		expect(#report.repaired).toBe(0)
		expect(report.ok).toBe(true)
	end)

	it("still passes clean after a round trip through JSON", function()
		--[[
			DataStore stores JSON. An empty Lua table has no way to say whether it was
			a list or a dictionary, so it can come back as either, and code that assumed
			one of them breaks only for brand-new players.
		]]
		local encoded = serde.encode("json", ProfileSchema.newProfile(USER_ID, NOW))
		local report = ProfileValidate.validate(serde.decode("json", encoded))
		expect(#report.fatal).toBe(0)
		expect(#report.repaired).toBe(0)
	end)
end)

describe("ProfileValidate / fatal: the data is ambiguous", function()
	it("refuses two creatures sharing a uid", function()
		-- The uid is how a creature is addressed. Two of them means every later
		-- operation picks one at random, and a clamp cannot decide which.
		local report = ProfileValidate.validate(profileWith({ creature("1:1"), creature("1:1") }))
		expect(report.ok).toBe(false)
		expect(#report.fatal).toBeGreaterThan(0)
		expect(report.fatal[1].message:find("uid") ~= nil).toBe(true)
	end)

	it("refuses a uid shared across the party and storage", function()
		local report =
			ProfileValidate.validate(profileWith({ creature("1:1") }, { creature("1:1") }))
		expect(report.ok).toBe(false)
	end)

	it("refuses a creature with no uid", function()
		local nameless = creature("1:1")
		nameless.uid = nil
		expect(ProfileValidate.validate(profileWith({ nameless })).ok).toBe(false)
	end)

	it("refuses a creature with no moves at all", function()
		--[[
			Fatal rather than repairable, and the only guard here that a mutation pass
			found completely untested. A creature with an empty move list cannot take a
			turn, and there is no correct move to invent for it — picking one hands the
			player something they never taught it. A refused login beats a battle that
			errors on the first turn.
		]]
		local mute = creature("1:1")
		mute.moves = {}
		local report = ProfileValidate.validate(profileWith({ mute }))
		expect(report.ok).toBe(false)
		expect(pathsOf(report.fatal)).toContain("party[1].moves")
	end)

	it("refuses a creature with no species", function()
		local unknown = creature("1:1")
		unknown.speciesId = nil
		expect(ProfileValidate.validate(profileWith({ unknown })).ok).toBe(false)
	end)

	it("refuses a version that should already have been migrated", function()
		local stale = ProfileSchema.newProfile(USER_ID, NOW) :: any
		stale.schemaVersion = ProfileSchema.CURRENT_SCHEMA_VERSION + 1
		local report = ProfileValidate.validate(stale)
		expect(report.ok).toBe(false)
		expect(pathsOf(report.fatal)).toContain("schemaVersion")
	end)

	it("refuses something that is not a profile at all", function()
		expect(ProfileValidate.validate("nope").ok).toBe(false)
		expect(ProfileValidate.validate(nil :: any).ok).toBe(false)
		expect(ProfileValidate.validate(7).ok).toBe(false)
	end)

	it("refuses a party that is a dictionary rather than a list", function()
		--[[
			The creature under the string key is a VALID one on purpose. An earlier
			version of this test put `true` there, and it passed whether or not the
			list check existed — the value simply failed the per-creature check for not
			being a table. A mutation pass caught it.

			With a valid creature, defeating the list check loads a profile whose party
			`#` reports as empty while a creature sits inside it, which is the actual
			bug: it only shows up for the one player whose save is shaped oddly.
		]]
		local profile = ProfileSchema.newProfile(USER_ID, NOW) :: any
		profile.party = { somethingElse = creature("1:1") }
		expect(ProfileValidate.validate(profile).ok).toBe(false)
	end)

	it("refuses a party list with a hole in it", function()
		-- #party is undefined behaviour across a gap, so half the code sees one
		-- creature and half sees two.
		local profile = ProfileSchema.newProfile(USER_ID, NOW) :: any
		profile.party = { [1] = creature("1:1"), [3] = creature("1:3") }
		expect(ProfileValidate.validate(profile).ok).toBe(false)
	end)

	it("refuses a missing top-level field instead of inventing one", function()
		local profile = ProfileSchema.newProfile(USER_ID, NOW) :: any
		profile.inventory = nil
		expect(ProfileValidate.validate(profile).ok).toBe(false)
	end)
end)

describe("ProfileValidate / repairs: there is one correct value", function()
	it("clamps a level outside 1..100", function()
		local low =
			okOrFail(ProfileValidate.validate(profileWith({ creature("1:1", { level = 0 }) })))
		expect(low.party[1].level).toBe(1)

		local high =
			okOrFail(ProfileValidate.validate(profileWith({ creature("1:1", { level = 150 }) })))
		expect(high.party[1].level).toBe(100)
	end)

	it("clamps IVs into 0..31", function()
		local broken = creature("1:1", {
			ivs = { hp = 50, atk = -1, def = 31, spa = 0, spd = 20, spe = 20 },
		})
		local fixed = okOrFail(ProfileValidate.validate(profileWith({ broken })))
		expect(fixed.party[1].ivs.hp).toBe(StatBlock.MAX_IV)
		expect(fixed.party[1].ivs.atk).toBe(0)
		expect(fixed.party[1].ivs.def).toBe(31)
	end)

	it("clamps a single EV over its per-stat cap", function()
		local broken =
			creature("1:1", { evs = { hp = 400, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 } })
		local fixed = okOrFail(ProfileValidate.validate(profileWith({ broken })))
		expect(fixed.party[1].evs.hp).toBe(StatBlock.MAX_EV_PER_STAT)
	end)

	it("trims an EV total over the cap, in a stated order", function()
		--[[
			Which stat to cut is genuinely ambiguous, so the rule is deterministic
			rather than clever: walk StatBlock.STAT_IDS in order and clamp each stat so
			the running total never exceeds the cap. Earlier stats keep their value.
			Documented because "deterministic" is only useful if it is written down.
		]]
		local maxed = creature("1:1", {
			evs = { hp = 252, atk = 252, def = 252, spa = 252, spd = 252, spe = 252 },
		})
		local fixed = okOrFail(ProfileValidate.validate(profileWith({ maxed })))
		local evs = fixed.party[1].evs

		expect(StatBlock.totalOf(evs)).toBeLessThanOrEqual(StatBlock.MAX_EV_TOTAL)
		expect(evs.hp).toBe(252)
		expect(evs.atk).toBe(252)
		expect(evs.def).toBe(StatBlock.MAX_EV_TOTAL - 504)
		expect(evs.spa).toBe(0)
		expect(evs.spe).toBe(0)
	end)

	it("clamps pp above maxPp, and below zero", function()
		local broken = creature("1:1", {
			moves = {
				{ moveId = "flame.emberwake", pp = 99, maxPp = 25 },
				{ moveId = "flame.cinderspit", pp = -5, maxPp = 35 },
			},
		})
		local fixed = okOrFail(ProfileValidate.validate(profileWith({ broken })))
		expect(fixed.party[1].moves[1].pp).toBe(25)
		expect(fixed.party[1].moves[2].pp).toBe(0)
	end)

	it("trims a creature carrying more than four moves", function()
		local moves = {}
		for index = 1, 7 do
			table.insert(moves, { moveId = `flame.move{index}`, pp = 10, maxPp = 10 })
		end
		local fixed =
			okOrFail(ProfileValidate.validate(profileWith({ creature("1:1", { moves = moves }) })))
		expect(#fixed.party[1].moves).toBe(4)
	end)

	it("truncates an over-long nickname", function()
		local long = creature("1:1", { nickname = string.rep("x", 200) })
		local fixed = okOrFail(ProfileValidate.validate(profileWith({ long })))
		expect(#(fixed.party[1].nickname :: string)).toBe(ProfileSchema.MAX_NICKNAME_LENGTH)
	end)

	it("floors negative money and playtime at zero", function()
		local profile = profileWith({})
		profile.money = -500
		profile.playtimeSeconds = -1
		local fixed = okOrFail(ProfileValidate.validate(profile))
		expect(fixed.money).toBe(0)
		expect(fixed.playtimeSeconds).toBe(0)
	end)

	it("drops inventory entries that are not a positive whole count", function()
		local profile = profileWith({})
		profile.inventory = {
			["item.ball"] = 3,
			["item.zero"] = 0,
			["item.negative"] = -2,
			["item.fractional"] = 1.5,
		}
		local fixed = okOrFail(ProfileValidate.validate(profile))
		expect(fixed.inventory["item.ball"]).toBe(3)
		expect(fixed.inventory["item.zero"]).toBeNil()
		expect(fixed.inventory["item.negative"]).toBeNil()
		expect(fixed.inventory["item.fractional"]).toBeNil()
	end)

	it("moves an over-sized party into storage instead of deleting the extras", function()
		local party = {}
		for index = 1, 9 do
			table.insert(party, creature(`1:{index}`))
		end
		local report = ProfileValidate.validate(profileWith(party))
		local fixed = okOrFail(report)

		expect(#fixed.party).toBe(ProfileSchema.MAX_PARTY_SIZE)
		expect(#fixed.storage).toBe(3)
		expect(countCreatures(fixed)).toBe(9)
	end)
end)

describe("ProfileValidate / the uid counter cannot fall behind", function()
	it("bumps nextCreatureSerial past the highest serial already minted", function()
		--[[
			A counter behind the creatures that exist mints a uid that is already in
			use, and the next validate call sees a duplicate and refuses the load. The
			profile would be bricked by its own save, one creature at a time.
		]]
		local profile = profileWith({ creature(`{USER_ID}:40`), creature(`{USER_ID}:17`) })
		profile.nextCreatureSerial = 5

		local report = ProfileValidate.validate(profile)
		local fixed = okOrFail(report)

		expect(fixed.nextCreatureSerial).toBe(41)
		expect(pathsOf(report.repaired)).toContain("nextCreatureSerial")
	end)

	it("leaves a counter that is already ahead alone", function()
		local profile = profileWith({ creature(`{USER_ID}:3`) })
		profile.nextCreatureSerial = 900
		local fixed = okOrFail(ProfileValidate.validate(profile))
		expect(fixed.nextCreatureSerial).toBe(900)
	end)

	it("ignores serials from another owner when bumping", function()
		--[[
			A traded creature carries the uid it was minted with. Counting it would
			push this profile's counter somewhere arbitrary.

			The foreign owner id has the SAME NUMBER OF DIGITS as this profile's on
			purpose. An earlier version of this test used a longer one, and it passed
			whether or not the owner check existed: stripping a prefix of the wrong
			length left "9:4000", which tonumber rejects anyway. A mutation pass caught
			it. With a same-length id, dropping the check parses a real 4000 and the
			counter jumps, so the check is now the only thing making this pass.
		]]
		local sameLengthForeignOwner = 7654321
		expect(#tostring(sameLengthForeignOwner)).toBe(#tostring(USER_ID))

		local profile = profileWith({ creature(`{sameLengthForeignOwner}:4000`) })
		profile.nextCreatureSerial = 10
		local fixed = okOrFail(ProfileValidate.validate(profile))
		expect(fixed.nextCreatureSerial).toBe(10)
	end)
end)

describe("ProfileValidate / current HP needs the species table, so it is injected", function()
	it("clamps HP above the maximum when a max is supplied", function()
		local profile = profileWith({ creature("1:1", { currentHp = 9999 }) })
		local fixed = okOrFail(ProfileValidate.validate(profile, {
			maxHpOf = function(_creature): number?
				return 42
			end,
		}))
		expect(fixed.party[1].currentHp).toBe(42)
	end)

	it("floors negative HP at zero with or without a max", function()
		local profile = profileWith({ creature("1:1", { currentHp = -30 }) })
		expect(okOrFail(ProfileValidate.validate(profile)).party[1].currentHp).toBe(0)
	end)

	it("leaves HP alone when no max is available", function()
		-- Validation must not need the content tables to run. Without a max there is
		-- no correct value to clamp to, and inventing one would be worse.
		local profile = profileWith({ creature("1:1", { currentHp = 9999 }) })
		expect(okOrFail(ProfileValidate.validate(profile)).party[1].currentHp).toBe(9999)
	end)

	it("skips the clamp for a species the supplied lookup does not know", function()
		local profile = profileWith({ creature("1:1", { currentHp = 9999 }) })
		local fixed = okOrFail(ProfileValidate.validate(profile, {
			maxHpOf = function(_creature): number?
				return nil
			end,
		}))
		expect(fixed.party[1].currentHp).toBe(9999)
	end)
end)

describe("ProfileValidate / invariants across every repair", function()
	local function thoroughlyBrokenProfile(): any
		local party = {}
		for index = 1, 8 do
			table.insert(
				party,
				creature(`{USER_ID}:{index}`, {
					level = 500,
					exp = -1,
					ivs = { hp = 99, atk = -4, def = 31, spa = 0, spd = 20, spe = 20 },
					evs = { hp = 300, atk = 300, def = 300, spa = 300, spd = 300, spe = 300 },
					currentHp = -8,
					nickname = string.rep("y", 90),
					moves = {
						{ moveId = "flame.emberwake", pp = 999, maxPp = 25 },
						{ moveId = "flame.a", pp = 1, maxPp = 10 },
						{ moveId = "flame.b", pp = 1, maxPp = 10 },
						{ moveId = "flame.c", pp = 1, maxPp = 10 },
						{ moveId = "flame.d", pp = 1, maxPp = 10 },
					},
				})
			)
		end
		local profile = profileWith(party)
		profile.money = -9
		profile.playtimeSeconds = -9
		profile.nextCreatureSerial = 1
		profile.inventory = { ["item.bad"] = 0 }
		return profile
	end

	it("never deletes a creature, however much it had to fix", function()
		local fixed = okOrFail(ProfileValidate.validate(thoroughlyBrokenProfile()))
		expect(countCreatures(fixed)).toBe(8)
	end)

	it("produces a profile that validates clean on a second pass", function()
		--[[
			The property that makes repair trustworthy. If a repaired profile still has
			problems, then every login repairs it again and the log fills with the same
			lines forever, which is how a real bug hides.
		]]
		local once = okOrFail(ProfileValidate.validate(thoroughlyBrokenProfile()))
		local twice = ProfileValidate.validate(once)

		if #twice.repaired > 0 or #twice.fatal > 0 then
			fail(
				"a repaired profile still has problems, so repair is not a fixed point: "
					.. table.concat(pathsOf(twice.repaired), ", ")
					.. table.concat(pathsOf(twice.fatal), ", ")
			)
		end
		expect(twice.ok).toBe(true)
	end)

	it("reports every repair it made, with a path", function()
		local report = ProfileValidate.validate(thoroughlyBrokenProfile())
		expect(#report.repaired).toBeGreaterThan(0)
		for _, problem in report.repaired do
			if #problem.path == 0 or #problem.message == 0 then
				fail("a repair was reported with no path or no message")
			end
			expect(problem.severity).toBe("repairable")
		end
	end)

	it("does not mutate the profile it was handed", function()
		local original = thoroughlyBrokenProfile()
		ProfileValidate.validate(original)
		expect(original.party[1].level).toBe(500)
		expect(original.money).toBe(-9)
		expect(#original.party).toBe(8)
	end)
end)
