--!strict
--[[
	The server's entry point.

	A Script, not a module, so Roblox actually runs it. Everything else under
	src/server/ is a module that does nothing until started from here, which keeps the
	order services come up in explicit and in one place.

	Deliberately bare. Phase 2's only service is the save system; BattleService,
	EncounterService and the rest are P3 and P4 and are not stubbed here. An empty
	line waiting for a service that does not exist reads like an oversight later.
]]

local DataService = require(script.Parent.Services.DataService)

DataService.start()

print("[Bootstrap] server up: DataService started")
