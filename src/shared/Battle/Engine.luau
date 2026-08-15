--!strict
--[[
	The loop around TurnResolver.

	TurnResolver is a pure function of its inputs. Engine is everything that cannot be:
	asking each side what it wants, asking who to send in after a faint, deciding
	whether the battle is still going, and stopping.

	THE SPLIT, AND WHY IT IS HERE

	Asking a question is not a pure operation, so every question lives on this side of
	the line. A Controller answers two of them — what do you do this turn, and who
	comes in — and Engine never cares whether the answer came from a player, an AI, or
	three lines in a test. That is the whole reason the interface is two functions
	rather than a player object.

	CONTROLLER ANSWERS ARE VALIDATED, NOT TRUSTED

	A controller is the outside world. The outside world is where a party index of 99
	comes from, and where a client that wants to switch to a fainted creature comes
	from. Every answer is checked against the legal set before it is used — Absolute
	Rule #2 is not only about damage numbers.

	WHAT ENGINE DOES NOT DO

	No matchmaking, no AI, no persistence, no rewards. Those are Phase 2 and beyond.
	Engine drives one battle from its opening state to a terminal outcome and stops.
]]

local BattleStateModule = require(script.Parent.Parent.Types.BattleState)
local RngModule = require(script.Parent.Parent.Types.Rng)
local TurnResolver = require(script.Parent.TurnResolver)

type BattleEvent = BattleStateModule.BattleEvent
type BattleIntent = any
type BattleState = BattleStateModule.BattleState
type BattleOutcome = BattleStateModule.BattleOutcome
type Rng = RngModule.Rng
type SideState = BattleStateModule.SideState

export type Controller = {
	chooseAction: (sideId: number, state: BattleState) -> BattleIntent,
	-- Called whenever this side has to put something on the field: after a faint, or
	-- after a pivot move withdraws the active creature. `legal` is never empty.
	chooseReplacement: (sideId: number, legal: { number }, state: BattleState) -> number,
}

export type EngineConfig = {
	state: BattleState,
	dex: TurnResolver.BattleDex,
	rng: Rng,
	controllers: { [number]: Controller },
	maxTurns: number?,
}

export type Engine = {
	state: BattleState,
	dex: TurnResolver.BattleDex,
	rng: Rng,
	controllers: { [number]: Controller },
	maxTurns: number,
	turnsRun: number,
}

export type TurnReport = {
	events: { BattleEvent },
	over: boolean,
}

export type BattleReport = {
	state: BattleState,
	events: { BattleEvent },
	outcome: BattleOutcome,
	turns: number,
}

--[[
	Two walls that cannot break each other would otherwise loop until the process dies.
	On a real server that is not a hung battle, it is a hung thread, so there is always
	a ceiling and reaching it is a draw.
]]
local DEFAULT_MAX_TURNS = 1000

--[[ Reading the state ------------------------------------------------------ ]]

local function isDefeated(side: SideState): boolean
	for _, creature in side.party do
		if creature.currentHp > 0 then
			return false
		end
	end
	return true
end

local function isOver(state: BattleState): boolean
	return state.outcome ~= "InProgress"
end

local function livingReplacements(side: SideState): { number }
	local indices: { number } = {}
	for index, creature in side.party do
		if index ~= side.active.partyIndex and creature.currentHp > 0 then
			table.insert(indices, index)
		end
	end
	return indices
end

--[[
	Reads the terminal signals out of the turn's log rather than out of return values.

	The log is the record of what happened, so a battle that ends because a ball landed
	and a battle that ends because a party is empty are read the same way. It also means
	a replay of the log reaches the same conclusion the live battle did.
]]
local function outcomeFromEvents(events: { BattleEvent }): BattleOutcome?
	for _, event in events do
		if event.kind == "CaptureAttempt" and event.succeeded then
			return "Captured" :: BattleOutcome
		elseif event.kind == "FleeAttempt" and event.succeeded then
			return "Fled" :: BattleOutcome
		end
	end
	return nil
end

local function outcomeFromParties(state: BattleState): BattleOutcome?
	local oneDown = isDefeated(state.sides[1])
	local twoDown = isDefeated(state.sides[2])

	if oneDown and twoDown then
		return "Draw" :: BattleOutcome
	elseif oneDown then
		return "Side2Win" :: BattleOutcome
	elseif twoDown then
		return "Side1Win" :: BattleOutcome
	end
	return nil
end

--[[ Building ---------------------------------------------------------------- ]]

local function create(config: EngineConfig): Engine
	for _, side in config.state.sides do
		if config.controllers[side.id] == nil then
			error(`Engine: no controller supplied for side {side.id}`)
		end
	end

	return {
		state = config.state,
		dex = config.dex,
		rng = config.rng,
		controllers = config.controllers,
		maxTurns = config.maxTurns or DEFAULT_MAX_TURNS,
		turnsRun = 0,
	}
end

local function contextFor(engine: Engine): TurnResolver.TurnContext
	return {
		dex = engine.dex,
		rng = engine.rng,
		--[[
			This is the wire D20 was waiting on. A pivot move withdraws the user
			mid-turn and the replacement is the player's call, so TurnResolver reaches
			back through here rather than drawing one at random.
		]]
		chooseReplacement = function(sideId: number, legal: { number }, state: BattleState): number
			return engine.controllers[sideId].chooseReplacement(sideId, legal, state)
		end,
	}
end

--[[ Terminal state ---------------------------------------------------------- ]]

local function finish(engine: Engine, outcome: BattleOutcome, events: { BattleEvent })
	engine.state.outcome = outcome
	local terminal: BattleEvent = { kind = "BattleEnded", outcome = outcome }
	table.insert(events, terminal)
	table.insert(engine.state.log, terminal)
end

--[[
	Replaces anything that fainted, asking the controller which creature comes in.

	A side with a fainted active and nobody left is not replaced — it is simply
	defeated, and the party check downstream picks that up.
]]
local function replaceFainted(engine: Engine, events: { BattleEvent })
	for _, side in engine.state.sides do
		local active = side.party[side.active.partyIndex]
		if active ~= nil and active.currentHp <= 0 then
			local legal = livingReplacements(side)
			if #legal > 0 then
				local picked =
					engine.controllers[side.id].chooseReplacement(side.id, legal, engine.state)

				local allowed = false
				for _, index in legal do
					if index == picked then
						allowed = true
						break
					end
				end
				if not allowed then
					error(
						`Engine: side {side.id} chose replacement {tostring(picked)}, `
							.. `which is not in the legal set`
					)
				end

				local outcome =
					TurnResolver.sendIn(engine.state, side.id, picked, contextFor(engine))
				engine.state = outcome.state
				for _, event in outcome.events do
					table.insert(events, event)
				end
			end
		end
	end
end

--[[ The turn --------------------------------------------------------------- ]]

local function runTurn(engine: Engine): TurnReport
	if isOver(engine.state) then
		error("Engine: the battle is over; there is no turn to run")
	end

	local events: { BattleEvent } = {}

	--[[
		Forfeit is handled here rather than by TurnResolver because it is not a turn
		action — nothing resolves, the battle simply stops. Checking it first also means
		a forfeiting player does not get one last move in.
	]]
	local intents: { [number]: BattleIntent } = {}
	for _, side in engine.state.sides do
		local intent = engine.controllers[side.id].chooseAction(side.id, engine.state)
		if intent.kind == "Forfeit" then
			finish(
				engine,
				(if side.id == 1 then "Side2Win" else "Side1Win") :: BattleOutcome,
				events
			)
			return { events = events, over = true }
		end
		intents[side.id] = intent
	end

	local outcome = TurnResolver.resolveTurn(engine.state, intents, contextFor(engine))
	engine.state = outcome.state
	engine.turnsRun += 1
	for _, event in outcome.events do
		table.insert(events, event)
	end

	-- A capture or a successful escape ends things before anyone is replaced: there is
	-- no point sending in a fresh creature against a battle that has stopped.
	local signalled = outcomeFromEvents(outcome.events)
	if signalled ~= nil then
		finish(engine, signalled :: BattleOutcome, events)
		return { events = events, over = true }
	end

	replaceFainted(engine, events)

	local decided = outcomeFromParties(engine.state)
	if decided ~= nil then
		finish(engine, decided :: BattleOutcome, events)
		return { events = events, over = true }
	end

	return { events = events, over = false }
end

local function run(engine: Engine): BattleReport
	local events: { BattleEvent } = {}

	while not isOver(engine.state) do
		if engine.turnsRun >= engine.maxTurns then
			finish(engine, "Draw", events)
			break
		end
		for _, event in runTurn(engine).events do
			table.insert(events, event)
		end
	end

	return {
		state = engine.state,
		events = events,
		outcome = engine.state.outcome,
		turns = engine.turnsRun,
	}
end

return {
	DEFAULT_MAX_TURNS = DEFAULT_MAX_TURNS,
	create = create,
	isOver = isOver,
	isDefeated = isDefeated,
	livingReplacements = livingReplacements,
	runTurn = runTurn,
	run = run,
}
