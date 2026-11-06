--!strict
--[[
	The session layer: taking the lock, running the load pipeline, and letting go.

	The store is injected, so every one of these runs against a fake that can be made
	to fail on command. That is the only way to test the paths that matter — a lock
	held by another server, a save that refuses to migrate, the library ending a
	session underneath us — because none of them can be provoked on demand against a
	real DataStore.

	The test that matters most is "the adopted profile is the table the store will
	save". Everything else in the save system is theatre if the repaired data sits in
	a copy that never reaches disk.
]]

local TestKit = require(script.Parent.Parent.TestKit)
local Shared = script.Parent.Parent.Parent.Shared
local ProfileSchema = require(Shared.Save.ProfileSchema)
local SaveSession = require(Shared.Save.SaveSession)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect
local fail = TestKit.fail

local USER_ID = 1234567
local OTHER_USER_ID = 7654321
local NOW = 1762300000

--[[ A fake ProfileStore ---------------------------------------------------- ]]

type FakeSession = {
	Data: any,
	ended: boolean,
	addedUserIds: { number },
	reconciled: number,
	EndSession: (FakeSession) -> (),
	AddUserId: (FakeSession, number) -> (),
	Reconcile: (FakeSession) -> (),
	OnSessionEnd: any,
	fireSessionEnd: (FakeSession) -> (),
}

type FakeStore = {
	saved: { [string]: any },
	-- Set to deny the lock, the way a session held on another server does.
	lockHeld: boolean,
	keysAsked: { string },
	sessions: { [string]: FakeSession },
	StartSessionAsync: (FakeStore, string, any) -> FakeSession?,
}

local function newFakeSession(data: any): FakeSession
	local listeners: { () -> () } = {}
	local session: FakeSession

	local function fire()
		for _, callback in listeners do
			callback()
		end
	end

	session = {
		Data = data,
		ended = false,
		addedUserIds = {},
		reconciled = 0,
		--[[
			A real EndSession fires OnSessionEnd. The fake does too, because a fake
			that is gentler than the library it stands in for hides exactly the bugs
			it was built to catch — here, the ordering inside release().
		]]
		EndSession = function(self: FakeSession)
			if self.ended then
				return
			end
			self.ended = true
			fire()
		end,
		AddUserId = function(self: FakeSession, userId: number)
			table.insert(self.addedUserIds, userId)
		end,
		Reconcile = function(self: FakeSession)
			self.reconciled += 1
		end,
		OnSessionEnd = {
			Connect = function(_self: any, callback: () -> ())
				table.insert(listeners, callback)
				return { Disconnect = function() end }
			end,
		},
		-- Unconditional on purpose: this is the test's way of saying "the store ended
		-- it", which can happen after our own release and must still be survivable.
		fireSessionEnd = function(self: FakeSession)
			self.ended = true
			fire()
		end,
	}
	return session
end

local function newFakeStore(saved: { [string]: any }?): FakeStore
	local store: FakeStore

	store = {
		saved = saved or {},
		lockHeld = false,
		keysAsked = {},
		sessions = {},
		StartSessionAsync = function(self: FakeStore, key: string, _params: any): FakeSession?
			table.insert(self.keysAsked, key)
			if self.lockHeld then
				return nil
			end
			-- No save for this key means a brand-new player, which the real library
			-- represents by handing back a deep copy of the template.
			local data = self.saved[key]
			if data == nil then
				data = ProfileSchema.storeTemplate()
			end
			local session = newFakeSession(data)
			self.sessions[key] = session
			return session
		end,
	}
	return store
end

local function fixedClock(): () -> number
	return function(): number
		return NOW
	end
end

local function newService(store: FakeStore, log: { string }?): SaveSession.Service
	return SaveSession.new({
		store = store :: any,
		now = fixedClock(),
		log = if log ~= nil
			then function(_level, message: string)
				table.insert(log :: { string }, message)
			end
			else nil,
	})
end

local function loadedOrFail(result: SaveSession.LoadResult): ProfileSchema.PlayerProfile
	if not result.ok then
		fail(`expected the load to succeed, got {(result :: any).reason}: {(result :: any).detail}`)
	end
	return (result :: any).profile
end

local function savedProfileFor(userId: number, mutate: ((any) -> ())?): { [string]: any }
	local profile = ProfileSchema.newProfile(userId, NOW - 10000) :: any
	profile.money = 777
	profile.party = {
		{
			uid = `{userId}:1`,
			speciesId = "flame.emberlin",
			level = 7,
			exp = 120,
			ivs = { hp = 20, atk = 20, def = 20, spa = 20, spd = 20, spe = 20 },
			evs = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
			currentHp = 24,
			moves = { { moveId = "flame.emberwake", pp = 25, maxPp = 25 } },
		},
	}
	profile.nextCreatureSerial = 2
	if mutate ~= nil then
		mutate(profile)
	end
	return profile
end

describe("SaveSession / the storage key is a one-way door", function()
	it("asks for a key built from the user id", function()
		--[[
			Changing this format later orphans every existing save — the old key is
			still in the DataStore and nothing ever looks at it again. Asserted so the
			change cannot be made casually.
		]]
		local store = newFakeStore()
		newService(store):load(USER_ID)
		expect(store.keysAsked).toEqual({ `Player_{USER_ID}` })
	end)
end)

describe("SaveSession / a first-time player", function()
	it("gets a profile stamped with their own id, not the template's", function()
		--[[
			The template is static and shared, so it cannot know whose it is. It carries
			owner 0, which no real Roblox account has, and that is the sentinel for "has
			never been saved". Getting this wrong hands every new player a profile that
			mints uids under owner 0 and collides with every other new player's.
		]]
		local profile = loadedOrFail(newService(newFakeStore()):load(USER_ID))
		expect(profile.ownerUserId).toBe(USER_ID)
		expect(profile.createdAtUnix).toBe(NOW)
		expect(profile.lastLoginUnix).toBe(NOW)
		expect(#profile.party).toBe(0)
	end)

	it("does not leave the template's sentinel owner in a live profile", function()
		local profile = loadedOrFail(newService(newFakeStore()):load(USER_ID))
		expect(profile.ownerUserId).never.toBe(ProfileSchema.FRESH_TEMPLATE_OWNER_ID)
	end)

	it("tags the save with the owner's id for Roblox's own data tooling", function()
		local store = newFakeStore()
		newService(store):load(USER_ID)
		expect(store.sessions[`Player_{USER_ID}`].addedUserIds).toEqual({ USER_ID })
	end)
end)

describe("SaveSession / a returning player", function()
	it("loads what was saved rather than a fresh profile", function()
		local store = newFakeStore({ [`Player_{USER_ID}`] = savedProfileFor(USER_ID) })
		local profile = loadedOrFail(newService(store):load(USER_ID))

		expect(profile.money).toBe(777)
		expect(#profile.party).toBe(1)
		expect(profile.party[1].level).toBe(7)
	end)

	it("keeps the original creation time and stamps a new login time", function()
		local store = newFakeStore({ [`Player_{USER_ID}`] = savedProfileFor(USER_ID) })
		local profile = loadedOrFail(newService(store):load(USER_ID))

		expect(profile.createdAtUnix).toBe(NOW - 10000)
		expect(profile.lastLoginUnix).toBe(NOW)
	end)
end)

describe("SaveSession / the adopted profile is the one that gets saved", function()
	it("writes through to the table the store holds", function()
		--[[
			THE TEST THE REST OF THE SAVE SYSTEM DEPENDS ON. The library saves the
			table it handed over. If the load pipeline adopts a copy, every repair and
			every bit of gameplay lands somewhere that is never written to disk, and
			nothing about it looks wrong until a player notices their progress is gone.
		]]
		local store = newFakeStore({ [`Player_{USER_ID}`] = savedProfileFor(USER_ID) })
		local service = newService(store)
		local profile = loadedOrFail(service:load(USER_ID))

		profile.money = 31337
		expect(store.sessions[`Player_{USER_ID}`].Data.money).toBe(31337)
	end)

	it("lands a repair in the store's table too, not just the returned one", function()
		local store = newFakeStore({
			[`Player_{USER_ID}`] = savedProfileFor(USER_ID, function(profile)
				profile.money = -4000
			end),
		})
		newService(store):load(USER_ID)
		expect(store.sessions[`Player_{USER_ID}`].Data.money).toBe(0)
	end)

	it("never calls Reconcile", function()
		--[[
			Reconcile silently fills in missing template keys. That is precisely the
			silent save-format change Absolute Rule 7 forbids: a field that appears
			without a migration, with no record that it did. Migrations are the
			explicit mechanism and they are tested; Reconcile would quietly make them
			look unnecessary while also papering over the corruption the validator is
			there to catch.
		]]
		local store = newFakeStore({ [`Player_{USER_ID}`] = savedProfileFor(USER_ID) })
		newService(store):load(USER_ID)
		expect(store.sessions[`Player_{USER_ID}`].reconciled).toBe(0)
	end)
end)

describe("SaveSession / the lock is held somewhere else", function()
	it("fails the load instead of waiting or guessing", function()
		local store = newFakeStore()
		store.lockHeld = true

		local result = newService(store):load(USER_ID)
		expect(result.ok).toBe(false)
		expect((result :: any).reason).toBe("lock-unavailable")
	end)

	it("registers nothing, so a later get finds no profile", function()
		local store = newFakeStore()
		store.lockHeld = true

		local service = newService(store)
		service:load(USER_ID)
		expect(service:get(USER_ID)).toBeNil()
	end)
end)

describe("SaveSession / a bad save ends the session instead of holding it", function()
	--[[
		Every refusal here must release the lock. A refused load that keeps the lock
		means the player cannot get in on this server OR any other one — the bad save
		becomes a permanent lockout rather than a failed login they can retry.
	]]
	local function refusedLoad(mutate: (any) -> ()): (SaveSession.LoadResult, FakeSession)
		local saved = savedProfileFor(USER_ID)
		mutate(saved)
		local store = newFakeStore({ [`Player_{USER_ID}`] = saved })
		local result = newService(store):load(USER_ID)
		return result, store.sessions[`Player_{USER_ID}`]
	end

	it("refuses a save with no schema version, and releases the lock", function()
		local result, session = refusedLoad(function(profile)
			profile.schemaVersion = nil
		end)
		expect((result :: any).reason).toBe("migration-refused")
		expect(session.ended).toBe(true)
	end)

	it("refuses a save from a newer build, and releases the lock", function()
		local result, session = refusedLoad(function(profile)
			profile.schemaVersion = ProfileSchema.CURRENT_SCHEMA_VERSION + 5
		end)
		expect((result :: any).reason).toBe("migration-refused")
		expect(session.ended).toBe(true)
	end)

	it("refuses two creatures sharing a uid, and releases the lock", function()
		local result, session = refusedLoad(function(profile)
			profile.party[2] = {
				uid = profile.party[1].uid,
				speciesId = "frost.rimeling",
				level = 7,
				exp = 0,
				ivs = { hp = 20, atk = 20, def = 20, spa = 20, spd = 20, spe = 20 },
				evs = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
				currentHp = 24,
				moves = { { moveId = "frost.glasswind", pp = 25, maxPp = 25 } },
			}
		end)
		expect((result :: any).reason).toBe("validation-refused")
		expect(session.ended).toBe(true)
	end)

	it("refuses somebody else's profile, and releases the lock", function()
		--[[
			The worst thing that can come back from a load. A key collision or a
			mis-keyed write would otherwise hand this player another person's
			creatures, and then save the result under their own key.
		]]
		local result, session = refusedLoad(function(profile)
			profile.ownerUserId = OTHER_USER_ID
		end)
		expect((result :: any).reason).toBe("owner-mismatch")
		expect(session.ended).toBe(true)
	end)

	it("says which profile it was in the detail, so the log is actionable", function()
		local result = (
			refusedLoad(function(profile)
				profile.ownerUserId = OTHER_USER_ID
			end)
		) :: any
		expect(result.detail:find(tostring(OTHER_USER_ID)) ~= nil).toBe(true)
	end)
end)

describe("SaveSession / repairs are reported, not swallowed", function()
	it("loads a repairable save and logs what it changed", function()
		local log: { string } = {}
		local store = newFakeStore({
			[`Player_{USER_ID}`] = savedProfileFor(USER_ID, function(profile)
				profile.party[1].level = 9999
				profile.money = -1
			end),
		})

		local profile = loadedOrFail(newService(store, log):load(USER_ID))
		expect(profile.party[1].level).toBe(100)
		expect(profile.money).toBe(0)

		local mentionsLevel = false
		for _, line in log do
			if line:find("level") ~= nil then
				mentionsLevel = true
			end
		end
		if not mentionsLevel then
			fail(`a repair was applied but never logged. log was:\n{table.concat(log, "\n")}`)
		end
	end)

	it("reports how many repairs ran on the result", function()
		local store = newFakeStore({
			[`Player_{USER_ID}`] = savedProfileFor(USER_ID, function(profile)
				profile.money = -1
				profile.playtimeSeconds = -1
			end),
		})
		local result = newService(store):load(USER_ID) :: any
		expect(result.repaired).toBe(2)
	end)

	it("logs nothing for a clean save", function()
		local log: { string } = {}
		local store = newFakeStore({ [`Player_{USER_ID}`] = savedProfileFor(USER_ID) })
		newService(store, log):load(USER_ID)
		expect(#log).toBe(0)
	end)
end)

describe("SaveSession / loading twice", function()
	it("refuses the second load rather than taking a second lock", function()
		local store = newFakeStore()
		local service = newService(store)
		service:load(USER_ID)

		local second = service:load(USER_ID)
		expect(second.ok).toBe(false)
		expect((second :: any).reason).toBe("already-loaded")
		expect(#store.keysAsked).toBe(1)
	end)

	it("allows a load again after a release", function()
		-- The rejoin case BUILD_PLAN warns about: leave and come back inside one
		-- server's lifetime.
		local store = newFakeStore()
		local service = newService(store)
		service:load(USER_ID)
		service:release(USER_ID)

		expect(service:load(USER_ID).ok).toBe(true)
	end)
end)

describe("SaveSession / releasing", function()
	it("ends the store session and forgets the profile", function()
		local store = newFakeStore()
		local service = newService(store)
		service:load(USER_ID)

		expect(service:release(USER_ID)).toBe(true)
		expect(store.sessions[`Player_{USER_ID}`].ended).toBe(true)
		expect(service:get(USER_ID)).toBeNil()
	end)

	it("does not log as if the store ended a session we ended ourselves", function()
		--[[
			EndSession fires OnSessionEnd, so a release that forgets the profile AFTER
			ending it hands its own callback a session that still looks registered. The
			callback then warns that the store ended the session, which is a log line
			blaming the library for something this code did on purpose — and the next
			person reading it goes looking for a cross-server lock problem that does
			not exist.
		]]
		local log: { string } = {}
		local service = newService(newFakeStore(), log)
		service:load(USER_ID)
		service:release(USER_ID)

		for _, line in log do
			if line:find("the store ended the session") ~= nil then
				fail(`release() logged a store-initiated end:\n{table.concat(log, "\n")}`)
			end
		end
		expect(#log).toBe(0)
	end)

	it("is safe to call for someone who was never loaded", function()
		expect(newService(newFakeStore()):release(USER_ID)).toBe(false)
	end)

	it("is safe to call twice", function()
		local service = newService(newFakeStore())
		service:load(USER_ID)
		service:release(USER_ID)
		expect(service:release(USER_ID)).toBe(false)
	end)

	it("releases everyone on shutdown", function()
		-- The server shutting down mid-battle. Whatever the battle was doing, the
		-- lock has to be handed back or the player waits it out on their next join.
		local store = newFakeStore()
		local service = newService(store)
		service:load(USER_ID)
		service:load(OTHER_USER_ID)

		expect(service:releaseAll()).toBe(2)
		expect(store.sessions[`Player_{USER_ID}`].ended).toBe(true)
		expect(store.sessions[`Player_{OTHER_USER_ID}`].ended).toBe(true)
		expect(service:activeCount()).toBe(0)
	end)
end)

describe("SaveSession / the store ends a session underneath us", function()
	it("forgets the profile when another server takes the lock", function()
		--[[
			The library can end a session without being asked — that is what happens
			when the same player joins a different server. Anything still holding the
			old profile is writing to a table nobody will ever save, so the registry
			has to drop it the moment it hears.
		]]
		local store = newFakeStore()
		local service = newService(store)
		service:load(USER_ID)

		store.sessions[`Player_{USER_ID}`]:fireSessionEnd()

		expect(service:get(USER_ID)).toBeNil()
		expect(service:activeCount()).toBe(0)
	end)

	it("lets the player load again afterwards", function()
		local store = newFakeStore()
		local service = newService(store)
		service:load(USER_ID)
		store.sessions[`Player_{USER_ID}`]:fireSessionEnd()

		expect(service:load(USER_ID).ok).toBe(true)
	end)

	it("does not end a session it has already released", function()
		local service = newService(newFakeStore())
		service:load(USER_ID)
		service:release(USER_ID)
		-- Firing afterwards must not resurrect or double-handle anything.
		expect(service:activeCount()).toBe(0)
	end)

	it("ignores a stale callback from a session that has been replaced", function()
		--[[
			The rejoin race. Leave, come back on the same server, and the first
			session's end callback fires late — a real EndSession does fire it. If the
			callback only knows the user id, it drops the profile the player is
			currently using, and from then on every write goes to a table nothing
			saves. Nothing about it looks wrong until their progress is gone.

			So the callback has to recognise its own session, not just its player.
		]]
		local store = newFakeStore()
		local service = newService(store)
		service:load(USER_ID)
		local firstSession = store.sessions[`Player_{USER_ID}`]

		service:release(USER_ID)
		service:load(USER_ID)
		local secondSession = store.sessions[`Player_{USER_ID}`]
		if firstSession == secondSession then
			fail("the fake store reused a session object, so this test proves nothing")
		end

		firstSession:fireSessionEnd()

		expect(service:get(USER_ID)).never.toBeNil()
		expect(service:activeCount()).toBe(1)
	end)
end)

describe("SaveSession / losing a session is reported to the caller", function()
	--[[
		When another server steals the session, SaveSession drops the profile. That is
		not enough on its own: whoever owns the player has to be told, because the
		player is still in the game and nothing they do from that point will ever be
		saved.

		ProfileStore's waiting server steals after SESSION_STEAL = 40 seconds, so this
		is not a rare race. It is what happens every time somebody opens the same
		place twice.
	]]
	local function serviceWithLossTracking(store: FakeStore, lost: { number }): SaveSession.Service
		return SaveSession.new({
			store = store :: any,
			now = fixedClock(),
			onSessionLost = function(userId: number)
				table.insert(lost, userId)
			end,
		})
	end

	it("calls onSessionLost when the store ends a live session", function()
		local store = newFakeStore()
		local lost: { number } = {}
		local service = serviceWithLossTracking(store, lost)
		service:load(USER_ID)

		store.sessions[`Player_{USER_ID}`]:fireSessionEnd()

		expect(lost).toEqual({ USER_ID })
	end)

	it("does not call it when we released the session ourselves", function()
		-- We ended it on purpose, because the player left. Reporting that as a loss
		-- would mean kicking a player who has already gone, and warning about a
		-- cross-server conflict that never happened.
		local store = newFakeStore()
		local lost: { number } = {}
		local service = serviceWithLossTracking(store, lost)
		service:load(USER_ID)
		service:release(USER_ID)

		expect(#lost).toBe(0)
	end)

	it("does not report a loss for a session that has already been replaced", function()
		local store = newFakeStore()
		local lost: { number } = {}
		local service = serviceWithLossTracking(store, lost)
		service:load(USER_ID)
		local firstSession = store.sessions[`Player_{USER_ID}`]
		service:release(USER_ID)
		service:load(USER_ID)

		firstSession:fireSessionEnd()

		expect(#lost).toBe(0)
		expect(service:activeCount()).toBe(1)
	end)

	it("is optional", function()
		-- Nothing is obliged to care. The service must not assume a handler exists.
		local store = newFakeStore()
		local service = newService(store)
		service:load(USER_ID)
		store.sessions[`Player_{USER_ID}`]:fireSessionEnd()
		expect(service:activeCount()).toBe(0)
	end)
end)

describe("SaveSession / two players at once", function()
	it("keeps their profiles apart", function()
		local store = newFakeStore({
			[`Player_{USER_ID}`] = savedProfileFor(USER_ID),
			[`Player_{OTHER_USER_ID}`] = savedProfileFor(OTHER_USER_ID, function(profile)
				profile.money = 11
			end),
		})
		local service = newService(store)
		local mine = loadedOrFail(service:load(USER_ID))
		local theirs = loadedOrFail(service:load(OTHER_USER_ID))

		expect(mine.money).toBe(777)
		expect(theirs.money).toBe(11)
		expect(service:activeCount()).toBe(2)

		mine.money = 1
		expect(theirs.money).toBe(11)
	end)
end)
