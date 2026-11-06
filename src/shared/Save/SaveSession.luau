--!strict
--[[
	Taking the lock, running the load pipeline, and letting go.

	This is all the save logic that has state, and none of the Roblox API. The store
	is injected, so the whole thing runs under Lune against a fake that can deny a
	lock or end a session on command — none of which can be provoked against a real
	DataStore. src/server/Services/ holds only the wiring that hands it the real
	ProfileStore and the real Players events.

	THE PIPELINE, in order, because the order is load-bearing:

	  1. take the session lock, or fail
	  2. migrate      — bring an old save up to this build's version
	  3. initialise   — if it is the untouched template, this player is new
	  4. check owner  — the profile must belong to the player being loaded
	  5. validate     — repair what has one correct value, refuse what is ambiguous
	  6. adopt        — copy the result INTO the table the store will save

	Step 6 is the one everything else depends on. The library saves the table it
	handed over, so if the pipeline adopted a copy, every repair and every bit of
	gameplay would land somewhere that is never written to disk — and nothing would
	look wrong until a player noticed their progress was gone.

	EVERY REFUSAL RELEASES THE LOCK. A refused load that keeps it locks the player
	out of this server and every other one, turning a bad save into a permanent
	lockout rather than a failed login they can retry. There is nothing to lose by
	letting go: a session that ends without a write leaves the save exactly as it was.

	RECONCILE IS NEVER CALLED. ProfileStore's Reconcile fills in missing template
	keys, which is exactly the silent save-format change Absolute Rule 7 forbids — a
	field appearing with no migration and no record. Migrations are the explicit
	mechanism and they are tested. Reconcile would also paper over the missing fields
	the validator exists to catch.
]]

local Migrations = require(script.Parent.Migrations)
local ProfileSchema = require(script.Parent.ProfileSchema)
local ProfileValidate = require(script.Parent.ProfileValidate)

type PlayerProfile = ProfileSchema.PlayerProfile

--[[
	The shape of ProfileStore, named here so this module never requires it.

	PascalCase because it mirrors the library rather than this codebase — the
	adapter in src/server/ passes the real object straight through, and a wrapper
	that renamed everything would be one more place for a typo to hide.
]]
export type StoreSession = {
	Data: any,
	EndSession: (StoreSession) -> (),
	AddUserId: (StoreSession, number) -> (),
	OnSessionEnd: { Connect: (any, () -> ()) -> any },
}

export type Store = {
	StartSessionAsync: (Store, string, any) -> StoreSession?,
}

export type Level = "info" | "warn"

export type Deps = {
	store: Store,
	-- Injected for the same reason the battle engine's RNG is: a module that reads
	-- the real clock cannot be replayed.
	now: () -> number,
	log: ((Level, string) -> ())?,

	--[[
		Called when the store ends a session this service still held — which means
		another server took it. Not called when we release it ourselves.

		Dropping the profile is not enough on its own: the player is still in the
		game, and from that moment nothing they do will ever be saved. Whoever owns
		the player has to be told so they can remove them. ProfileStore's waiting
		server steals after 40 seconds (SESSION_STEAL in vendor/ProfileStore.luau),
		so this is not a rare race — it is what happens every time somebody opens the
		same place twice.
	]]
	onSessionLost: ((userId: number) -> ())?,

	validateOptions: ProfileValidate.Options?,
	--[[
		Handed to StartSessionAsync untouched. ProfileStore's params is
		{Steal: boolean?} and has NO cancel callback — that was ProfileService's
		API. A player who leaves mid-load is therefore the adapter's problem to
		notice, not something that can be declared here.
	]]
	sessionParams: any?,
}

export type LoadOk = {
	ok: true,
	-- The live profile: the same table the store will save.
	profile: PlayerProfile,
	repaired: number,
}

export type LoadErr = {
	ok: false,
	reason: "lock-unavailable"
		| "already-loaded"
		| "migration-refused"
		| "validation-refused"
		| "owner-mismatch",
	detail: string,
}

export type LoadResult = LoadOk | LoadErr

export type Service = {
	load: (Service, number) -> LoadResult,
	get: (Service, number) -> PlayerProfile?,
	release: (Service, number) -> boolean,
	releaseAll: (Service) -> number,
	activeCount: (Service) -> number,
}

--[[
	Changing this orphans every existing save: the old key stays in the DataStore and
	nothing ever looks at it again. A test asserts the format so the change cannot be
	made casually.
]]
local KEY_PREFIX = "Player_"

local function keyFor(userId: number): string
	return `{KEY_PREFIX}{userId}`
end

--[[
	Copies `source` over `target`, keeping target's identity.

	Used instead of `session.Data = profile` because the library's contract is about
	the table it handed over, not about a reference it holds. Replacing the contents
	is correct whether or not a reassigned Data would be honoured, and it is one less
	thing to be wrong about in a module where being wrong means losing saves.
]]
local function replaceContents(target: { [string]: any }, source: { [string]: any })
	-- Keys are collected first rather than cleared mid-traversal. Legal either way,
	-- but this reads as what it is.
	local existing: { string } = {}
	for key in target do
		table.insert(existing, key)
	end
	for _, key in existing do
		target[key] = nil
	end
	for key, value in source do
		target[key] = value
	end
end

local function new(deps: Deps): Service
	local store = deps.store
	local now = deps.now

	local sessions: { [number]: StoreSession } = {}
	local active = 0

	local function report(level: Level, message: string)
		local log = deps.log
		if log ~= nil then
			log(level, message)
		end
	end

	local function forget(userId: number)
		if sessions[userId] ~= nil then
			sessions[userId] = nil
			active -= 1
		end
	end

	local function load(_self: Service, userId: number): LoadResult
		if sessions[userId] ~= nil then
			return {
				ok = false,
				reason = "already-loaded",
				detail = `{userId} already has a loaded profile on this server`,
			}
		end

		local session = store:StartSessionAsync(keyFor(userId), deps.sessionParams)
		if session == nil then
			--[[
				Another server holds the lock, or the DataStore refused. Not retried
				here: the caller knows whether the player is still around, and a retry
				loop inside the load is a retry loop nobody can cancel.
			]]
			return {
				ok = false,
				reason = "lock-unavailable",
				detail = `could not take the session lock for {userId}`,
			}
		end

		local function abandon(
			reason: "migration-refused" | "validation-refused" | "owner-mismatch",
			detail: string
		): LoadResult
			-- Let go of the lock before anything else. Nothing has been written, so
			-- the save is exactly as it was found.
			session:EndSession()
			report("warn", detail)
			return { ok = false, reason = reason, detail = detail }
		end

		local migrated = Migrations.migrateToCurrent(session.Data)
		if not migrated.ok then
			local failure = migrated :: Migrations.MigrateErr
			return abandon(
				"migration-refused",
				`refusing {userId}: {failure.code} — {failure.reason}`
			)
		end

		local upgraded = migrated :: Migrations.MigrateOk
		if #upgraded.applied > 0 then
			report(
				"info",
				`profile {userId}: migrated v{upgraded.from} to v{upgraded.to} (`
					.. `{#upgraded.applied} step(s))`
			)
		end

		local candidate: any = upgraded.profile

		-- A profile still carrying the template's sentinel owner has never been
		-- saved by anyone, so this is a first login.
		if candidate.ownerUserId == ProfileSchema.FRESH_TEMPLATE_OWNER_ID then
			candidate = ProfileSchema.newProfile(userId, now())
		end

		if candidate.ownerUserId ~= userId then
			--[[
				The worst thing a load can return. A key collision or a mis-keyed write
				would otherwise hand this player someone else's creatures and then save
				the result under their own key, destroying both profiles.
			]]
			return abandon(
				"owner-mismatch",
				`refusing {userId}: this profile says it belongs to `
					.. `{tostring(candidate.ownerUserId)}`
			)
		end

		local verdict = ProfileValidate.validate(candidate, deps.validateOptions)
		local repairedProfile = verdict.profile
		if not verdict.ok or repairedProfile == nil then
			local paths: { string } = {}
			for _, problem in verdict.fatal do
				table.insert(paths, `{problem.path}: {problem.message}`)
			end
			return abandon("validation-refused", `refusing {userId}: {table.concat(paths, "; ")}`)
		end

		repairedProfile.lastLoginUnix = now()

		-- Adopt into the store's own table. From here on, the returned profile and
		-- the table the store saves are the same object.
		replaceContents(session.Data, repairedProfile :: any)
		local live = session.Data :: PlayerProfile

		session:AddUserId(userId)

		--[[
			The library can end a session without being asked — that is what happens
			when the same player joins another server.

			The callback checks that the session it is reporting on is still the
			registered one. Without that, a late callback from a session the player
			already left would drop the profile they are currently using: leave,
			rejoin the same server, and every subsequent write goes to a table nothing
			will save.
		]]
		session.OnSessionEnd:Connect(function()
			if sessions[userId] ~= session then
				return
			end

			forget(userId)
			report("warn", `profile {userId}: the store ended the session`)

			local onSessionLost = deps.onSessionLost
			if onSessionLost ~= nil then
				onSessionLost(userId)
			end
		end)

		sessions[userId] = session
		active += 1

		for _, problem in verdict.repaired do
			report("info", `profile {userId}: repaired {problem.path} — {problem.message}`)
		end

		return { ok = true, profile = live, repaired = #verdict.repaired }
	end

	local function get(_self: Service, userId: number): PlayerProfile?
		local session = sessions[userId]
		if session == nil then
			return nil
		end
		return session.Data :: PlayerProfile
	end

	local function release(_self: Service, userId: number): boolean
		local session = sessions[userId]
		if session == nil then
			return false
		end

		-- Forget first. EndSession fires OnSessionEnd, and the callback should find
		-- nothing left to do rather than race with this.
		forget(userId)
		session:EndSession()
		return true
	end

	local function releaseAll(self: Service): number
		local userIds: { number } = {}
		for userId in sessions do
			table.insert(userIds, userId)
		end

		local released = 0
		for _, userId in userIds do
			if release(self, userId) then
				released += 1
			end
		end
		return released
	end

	local function activeCount(_self: Service): number
		return active
	end

	return {
		load = load,
		get = get,
		release = release,
		releaseAll = releaseAll,
		activeCount = activeCount,
	}
end

return {
	KEY_PREFIX = KEY_PREFIX,
	keyFor = keyFor,
	new = new,
}
