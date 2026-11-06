--!strict
--[[
	The only part of the save system that touches Roblox, and therefore the only part
	that cannot be tested.

	Everything with logic in it lives in ReplicatedStorage.Shared.Save and runs under
	Lune against a fake store. This file is the seam: it hands SaveSession the real
	ProfileStore and the real Players events and does nothing else. It is deliberately
	short, because every line here is a line no test will ever cover.
	-> docs/DECISIONS_P2.md P14

	If you are about to add logic to this file, add it to SaveSession instead and give
	it a test. The one thing that genuinely belongs here is translating upstream's
	behaviour into the `Store` interface, which is the `adapt` function below.

	THREE UPSTREAM BEHAVIOURS THIS DEPENDS ON, verified by reading the vendored source
	at commit 45c9847. Re-check them when vendor/ProfileStore.luau is updated:

	  1. StartSessionAsync THROWS, rather than returning nil, when the key is already
	     live on this server (ProfileStore.luau:1390). `adapt` absorbs that.
	  2. `params` is {Steal: boolean?}. There is no cancel callback — that was
	     ProfileService's API, not this one. Hence onPlayerAdded's own check below.
	  3. EndSession is asynchronous: it task.spawns the final save
	     (ProfileStore.luau:1090), so the session is not released by the time the call
	     returns, and OnSessionEnd fires later.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.Vendor.ProfileStore)
local Save = ReplicatedStorage.Shared.Save
local ProfileSchema = require(Save.ProfileSchema)
local SaveSession = require(Save.SaveSession)

type PlayerProfile = ProfileSchema.PlayerProfile

--[[
	The DataStore name. Changing it abandons every existing save, exactly like
	changing the key format does. There is no migration for this: the old store is
	still there and nothing will ever read it again.
]]
local STORE_NAME = "PlayerData"

local function log(level: SaveSession.Level, message: string)
	if level == "warn" then
		warn(`[DataService] {message}`)
	else
		print(`[DataService] {message}`)
	end
end

--[[
	Wraps the real store so it satisfies SaveSession.Store.

	Almost a pass-through: ProfileStore's own method names and shapes were used for
	that interface on purpose, so the only thing this adds is converting a thrown
	"already loaded in this session" into the nil that SaveSession already understands
	as lock-unavailable.

	That case is reachable. EndSession is asynchronous, so a player who leaves and
	rejoins the same server fast enough can call StartSessionAsync while the previous
	session is still releasing. Without this, the error propagates out of a
	PlayerAdded handler and the player sits in the game with no profile and nothing
	watching for it. With it, they get the same clean refusal as a lock held on
	another server, and can retry by rejoining.
]]
local function adapt(store: any): SaveSession.Store
	local wrapper = {
		StartSessionAsync = function(
			_self: any,
			key: string,
			params: any
		): SaveSession.StoreSession?
			local started, result = pcall(store.StartSessionAsync, store, key, params)
			if not started then
				log("warn", `StartSessionAsync refused {key}: {tostring(result)}`)
				return nil
			end
			return result
		end,
	}
	return wrapper :: any
end

local profileStore = ProfileStore.New(STORE_NAME, ProfileSchema.storeTemplate())

local service = SaveSession.new({
	store = adapt(profileStore),
	now = os.time,
	log = log,
	-- ProfileStore's params is {Steal: boolean?}. Stealing a live session is never
	-- right here: it would hand this server a profile another server is still
	-- writing to, and the later save wins.
	sessionParams = { Steal = false },
})

local function onPlayerAdded(player: Player)
	local result = service:load(player.UserId)

	if not result.ok then
		local failure = result :: SaveSession.LoadErr
		--[[
			There is no playable state without a profile, and continuing would mean
			the player collects things that are never saved. Kicking is the honest
			outcome: for a held lock it is a retry, and for a corrupt save it is what
			keeps the save intact instead of overwriting it with a guess.
		]]
		player:Kick(`Could not load your save ({failure.reason}). Please rejoin.`)
		return
	end

	--[[
		ProfileStore has no cancel callback, so the "left while the load was yielding"
		case is checked here instead. Without this the profile stays loaded and locked
		for a player who is already gone, and they wait it out on their next join.
	]]
	if player.Parent == nil then
		service:release(player.UserId)
	end
end

local function onPlayerRemoving(player: Player)
	service:release(player.UserId)
end

local function start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Players who joined before this connected. Each in its own thread, because the
	-- load yields and one slow DataStore call should not hold up the others.
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	--[[
		Hand every lock back on shutdown. Without this, a server closing mid-battle
		leaves each of its players waiting for their own session to time out on the
		next join.
	]]
	game:BindToClose(function()
		local released = service:releaseAll()
		log("info", `shutting down: released {released} session(s)`)
	end)
end

--[[
	The live profile for a player, or nil if they have none — still loading, kicked,
	or already released. Every caller has to handle nil; there is no point in the
	player's session where a profile is guaranteed.
]]
local function get(player: Player): PlayerProfile?
	return service:get(player.UserId)
end

return {
	start = start,
	get = get,
	-- Exposed for the eventual BattleService and friends. Prefer `get`.
	service = service,
}
