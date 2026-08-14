--!strict
--[[
	Resolves one turn: order the actions, run them, then tick the end of turn.

	THE SHAPE OF A TURN, AND WHY IT IS THIS SHAPE

	A turn is built in one pass and executed in another, and everything between those
	two passes can invalidate what the first one decided. Speed is read once, when the
	queue is built — that is correct, because a speed drop landing mid-turn does not
	retroactively change who moved first. But whether a creature is still *alive* is
	re-checked immediately before its action runs, because a fainted creature acting
	is the single most visible bug a turn resolver can have.

	So: decide order from a snapshot, then re-validate liveness at execution time.

	WHY A DEX IS INJECTED

	This module needs a move's data and a creature's computed battle stats. Both live
	in tables that do not exist yet (src/shared/Data/Moves.luau and Species.luau are
	@data-architect's). Taking a BattleDex instead of importing them means the engine
	works today against synthetic fixtures, works unchanged when the real tables land,
	and never reads src/shared/Data directly — which keeps this file out of another
	agent's territory by construction rather than by discipline.

	SCOPE

	Move and Switch intents. Item, Run and Forfeit raise rather than silently doing
	nothing — the Engine owns those, and it is not built yet.

	Of the 19 effect primitives, this interprets Damage, InflictStatus and StatStage:
	exactly the three the modules built so far can support. The other sixteen raise a
	clear "not implemented in this phase" rather than no-op, because a move that
	silently does nothing is far harder to notice than one that stops the test run.
]]

local DamageCalc = require(script.Parent.DamageCalc)
local StatStages = require(script.Parent.StatStages)
local StatusEffects = require(script.Parent.StatusEffects)
local BattleStateModule = require(script.Parent.Parent.Types.BattleState)
local CreatureInstanceModule = require(script.Parent.Parent.Types.CreatureInstance)
local MoveEffectModule = require(script.Parent.Parent.Types.MoveEffect)
local MoveModule = require(script.Parent.Parent.Types.Move)
local RngModule = require(script.Parent.Parent.Types.Rng)
local StatBlockModule = require(script.Parent.Parent.Types.StatBlock)
local TypeIdModule = require(script.Parent.Parent.Types.TypeId)

type BattleEvent = BattleStateModule.BattleEvent
type BattleIntent = any
type BattleState = BattleStateModule.BattleState
type CreatureInstance = CreatureInstanceModule.CreatureInstance
type Move = MoveModule.Move
type MoveEffect = MoveEffectModule.MoveEffect
type Rng = RngModule.Rng
type SideState = BattleStateModule.SideState
type StageBlock = StatBlockModule.StageBlock
type StatBlock = StatBlockModule.StatBlock
type StatusId = MoveEffectModule.StatusId
type TypeId = TypeIdModule.TypeId

export type BattleDex = {
	getMove: (moveId: string) -> Move,
	-- Computed battle stats, with level, IVs and EVs already folded in.
	getStats: (creature: CreatureInstance) -> StatBlock,
	getTyping: (creature: CreatureInstance) -> { TypeId },
}

export type TurnContext = {
	dex: BattleDex,
	rng: Rng,
}

export type ActionEntry = {
	sideId: number,
	kind: string,
	priority: number,
	speed: number,
}

export type TurnOutcome = {
	state: BattleState,
	events: { BattleEvent },
}

type TurnRun = {
	state: BattleState,
	events: { BattleEvent },
	dex: BattleDex,
	rng: Rng,
}

--[[
	Switching resolves before every move regardless of speed and regardless of move
	priority. A player who switches must eat the incoming hit on the replacement —
	that is the entire cost of the decision, and letting a fast switcher dodge it
	would remove the risk that makes switching interesting.
]]
local ACTION_RANK: { [string]: number } = {
	Switch = 2,
	Move = 1,
}

--[[ Utilities -------------------------------------------------------------- ]]

-- BattleState is guaranteed plain, acyclic and function-free, so this is total.
local function deepClone(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy: { [any]: any } = {}
	for key, entry in value do
		copy[key] = deepClone(entry)
	end
	return copy
end

local function sideById(state: BattleState, sideId: number): SideState
	for _, side in state.sides do
		if side.id == sideId then
			return side
		end
	end
	error(`TurnResolver: no side with id {sideId}`)
end

local function activeOf(side: SideState): CreatureInstance
	return BattleStateModule.activeCreature(side)
end

local function emit(run: TurnRun, event: BattleEvent)
	table.insert(run.events, event)
end

--[[ Speed ------------------------------------------------------------------ ]]

--[[
	Stages first, then the paralysis cut, then a floor of 1.

	The order matters once truncation bites, and Gen 5 applies the status multiplier
	to the already-staged value. The floor of 1 stops a fully debuffed, paralysed
	creature from reaching speed 0, where ordering stops meaning anything.
]]
local function effectiveSpeed(stats: StatBlock, stages: StageBlock, status: StatusId?): number
	local speed = StatStages.applyToStat(stats.spe, stages.spe)
	speed = math.floor(speed * StatusEffects.speedMultiplier(status))
	return math.max(1, speed)
end

--[[ Ordering -------------------------------------------------------------- ]]

--[[
	Action class, then priority, then effective speed, then a coin flip.

	A tiebreak is drawn for every entry, not only for the entries that turn out to be
	tied. That costs a couple of draws a turn and buys something worth much more: the
	number of values consumed from the stream depends only on how many actions there
	are, never on how they compared. Drawing lazily would make the RNG stream depend
	on the speeds, and a battle would stop replaying the moment a stat changed.
]]
local function orderActions(entries: { ActionEntry }, rng: Rng): { ActionEntry }
	local bySide = table.clone(entries)
	table.sort(bySide, function(a, b)
		return a.sideId < b.sideId
	end)

	local decorated = {}
	for _, entry in bySide do
		table.insert(decorated, { entry = entry, tiebreak = rng:nextNumber() })
	end

	table.sort(decorated, function(a, b): boolean
		local rankA = ACTION_RANK[a.entry.kind] or 1
		local rankB = ACTION_RANK[b.entry.kind] or 1
		if rankA ~= rankB then
			return rankA > rankB
		end
		if a.entry.priority ~= b.entry.priority then
			return a.entry.priority > b.entry.priority
		end
		if a.entry.speed ~= b.entry.speed then
			return a.entry.speed > b.entry.speed
		end
		if a.tiebreak ~= b.tiebreak then
			return a.tiebreak < b.tiebreak
		end
		-- Guarantees a total order so table.sort can never see an inconsistent
		-- comparator, however improbable an exact tiebreak collision is.
		return a.entry.sideId < b.entry.sideId
	end)

	local ordered = {}
	for _, item in decorated do
		table.insert(ordered, item.entry)
	end
	return ordered
end

--[[ Effects ---------------------------------------------------------------- ]]

--[[
	Gen 5 does not roll a flat 2-5 for the canonical multi-hit family: it weights two
	and three hits at 3/8 each and four and five at 1/8 each, so the average lands
	near three rather than three and a half. The weighting is specific to that range,
	which is why it is keyed on it.
]]
local function resolveHitCount(effect: any, rng: Rng): number
	if effect.hits ~= nil then
		return effect.hits
	end
	local range = effect.hitsRange
	if range == nil then
		return 1
	end
	if range.min == 2 and range.max == 5 then
		local roll = rng:nextInteger(1, 8)
		if roll <= 3 then
			return 2
		elseif roll <= 6 then
			return 3
		elseif roll == 7 then
			return 4
		end
		return 5
	end
	return rng:nextInteger(range.min, range.max)
end

local function combatantOf(run: TurnRun, side: SideState): any
	local creature = activeOf(side)
	return {
		level = creature.level,
		stats = run.dex.getStats(creature),
		stages = side.active.stages,
		typing = run.dex.getTyping(creature),
		status = creature.status,
	}
end

local function applyDamageEffect(
	run: TurnRun,
	effect: any,
	move: Move,
	attackerSide: SideState,
	defenderSide: SideState
)
	local attacker = activeOf(attackerSide)
	local defender = activeOf(defenderSide)

	local input: any = {
		attacker = combatantOf(run, attackerSide),
		defender = combatantOf(run, defenderSide),
		move = move,
		effect = effect,
		isCritical = false,
	}

	--[[
		Immunity is checked once, before any hit, and cancels the whole move. This
		reuses DamageCalc rather than reading TypeChart directly so that the effect's
		respectsTypeChart opt-out is honoured in exactly one place. computeWithRoll
		consumes no randomness, so probing costs nothing from the stream.
	]]
	local probe = DamageCalc.computeWithRoll(input, DamageCalc.MAX_RANDOM_FACTOR)
	if probe.effectiveness == 0 then
		emit(run, {
			kind = "MoveFailed",
			sideId = attackerSide.id,
			creatureUid = attacker.uid,
			moveId = move.id,
			reason = "NoEffect",
		})
		return
	end

	local hits = resolveHitCount(effect, run.rng)
	for _ = 1, hits do
		if defender.currentHp <= 0 then
			break
		end

		input.isCritical = DamageCalc.rollCritical(effect.critStageBonus or 0, run.rng)
		local result = DamageCalc.compute(input, run.rng)

		local applied = math.min(result.damage, defender.currentHp)
		defender.currentHp -= applied

		emit(run, {
			kind = "DamageDealt",
			sideId = defenderSide.id,
			creatureUid = defender.uid,
			amount = applied,
			remainingHp = defender.currentHp,
			effectiveness = result.effectiveness,
			isCritical = result.isCritical,
		})

		if defender.currentHp <= 0 then
			emit(run, { kind = "Fainted", sideId = defenderSide.id, creatureUid = defender.uid })
			break
		end
	end
end

local function applyInflictStatus(
	run: TurnRun,
	effect: any,
	attackerSide: SideState,
	defenderSide: SideState
)
	local target = if MoveEffectModule.targetOf(effect) == "Self"
		then activeOf(attackerSide)
		else activeOf(defenderSide)
	local targetSide = if MoveEffectModule.targetOf(effect) == "Self"
		then attackerSide
		else defenderSide

	if not StatusEffects.canApply(target.status, effect.status) then
		return
	end
	if not run.rng:nextBoolean(MoveEffectModule.chanceOf(effect)) then
		return
	end

	target.status = effect.status
	target.statusTurns = StatusEffects.initialDuration(effect.status, run.rng)
	emit(run, {
		kind = "StatusInflicted",
		sideId = targetSide.id,
		creatureUid = target.uid,
		status = effect.status,
	})
end

local function applyStatStageEffect(
	run: TurnRun,
	effect: any,
	attackerSide: SideState,
	defenderSide: SideState
)
	local side = if MoveEffectModule.targetOf(effect) == "Self" then attackerSide else defenderSide
	if not run.rng:nextBoolean(MoveEffectModule.chanceOf(effect)) then
		return
	end

	local change = StatStages.change(side.active.stages, effect.stat, effect.delta)
	side.active.stages = change.stages
	if change.applied == 0 then
		return
	end

	emit(run, {
		kind = "StatStageChanged",
		sideId = side.id,
		creatureUid = activeOf(side).uid,
		stat = effect.stat,
		delta = change.applied,
		newStage = change.newStage,
	})
end

local function applyEffect(
	run: TurnRun,
	effect: MoveEffect,
	move: Move,
	attackerSide: SideState,
	defenderSide: SideState
)
	if effect.kind == "Damage" then
		applyDamageEffect(run, effect, move, attackerSide, defenderSide)
	elseif effect.kind == "InflictStatus" then
		applyInflictStatus(run, effect, attackerSide, defenderSide)
	elseif effect.kind == "StatStage" then
		applyStatStageEffect(run, effect, attackerSide, defenderSide)
	else
		error(
			`TurnResolver: effect "{effect.kind}" is not implemented in this phase. `
				.. `Implemented: Damage, InflictStatus, StatStage.`
		)
	end
end

--[[ Actions ---------------------------------------------------------------- ]]

local function performSwitch(run: TurnRun, side: SideState, intent: any)
	local partyIndex = intent.partyIndex
	local incoming = side.party[partyIndex]

	if incoming == nil then
		error(`TurnResolver: side {side.id} has no party member at index {tostring(partyIndex)}`)
	end
	if partyIndex == side.active.partyIndex then
		error(`TurnResolver: "{incoming.uid}" is already active and cannot switch in`)
	end
	if incoming.currentHp <= 0 then
		error(`TurnResolver: cannot switch to "{incoming.uid}", which has fainted`)
	end

	local outgoing = activeOf(side)
	emit(run, { kind = "SwitchOut", sideId = side.id, creatureUid = outgoing.uid })

	-- Everything battle-only is left behind. Stat stages surviving a switch is what
	-- would make setup risk-free.
	side.active.partyIndex = partyIndex
	side.active.stages = StatBlockModule.zeroStages()
	side.active.volatiles = {}
	side.active.turnsOnField = 0
	side.active.lastMoveId = nil
	side.active.trappedBySideId = nil

	emit(run, {
		kind = "SwitchIn",
		sideId = side.id,
		creatureUid = incoming.uid,
		partyIndex = partyIndex,
	})
end

--[[
	Accuracy uses the attacker's accuracy stage against the defender's evasion stage
	as a single combined stage, which is why they cancel exactly. A move that cannot
	miss consumes no randomness — rolling a dice you already know the answer to would
	shift every later draw in the battle for nothing.
]]
local function rollsHit(
	run: TurnRun,
	move: Move,
	attackerSide: SideState,
	defenderSide: SideState
): boolean
	if move.accuracy == nil then
		return true
	end
	local combinedStage =
		StatStages.clamp(attackerSide.active.stages.accuracy - defenderSide.active.stages.evasion)
	local chance = move.accuracy * StatStages.accuracyMultiplier(combinedStage)
	if chance >= 1 then
		return true
	end
	return run.rng:nextBoolean(math.clamp(chance, 0, 1))
end

local function performMove(run: TurnRun, side: SideState, intent: any)
	local attacker = activeOf(side)
	local slot = attacker.moves[intent.slot]
	if slot == nil then
		error(`TurnResolver: "{attacker.uid}" has no move in slot {tostring(intent.slot)}`)
	end

	--[[
		The status gate runs before the PP check on purpose: a turn lost to sleep or
		paralysis does not also cost the move a PP, because the move was never used.
	]]
	local check = StatusEffects.checkAction(attacker.status, attacker.statusTurns, run.rng)
	if check.clearStatus then
		local cured = attacker.status
		attacker.status = nil
		attacker.statusTurns = nil
		emit(run, {
			kind = "StatusCured",
			sideId = side.id,
			creatureUid = attacker.uid,
			status = cured :: StatusId,
		})
	else
		attacker.statusTurns = check.turnsRemaining
	end

	if not check.canAct then
		emit(run, {
			kind = "MoveFailed",
			sideId = side.id,
			creatureUid = attacker.uid,
			moveId = slot.moveId,
			reason = check.reason :: any,
		})
		return
	end

	if slot.pp <= 0 then
		emit(run, {
			kind = "MoveFailed",
			sideId = side.id,
			creatureUid = attacker.uid,
			moveId = slot.moveId,
			reason = "NoPp",
		})
		return
	end

	local move = run.dex.getMove(slot.moveId)
	slot.pp -= 1
	side.active.lastMoveId = move.id
	emit(run, { kind = "MoveUsed", sideId = side.id, creatureUid = attacker.uid, moveId = move.id })

	local defenderSide = sideById(run.state, BattleStateModule.opposingSideId(side.id))
	if activeOf(defenderSide).currentHp <= 0 then
		emit(run, {
			kind = "MoveFailed",
			sideId = side.id,
			creatureUid = attacker.uid,
			moveId = move.id,
			reason = "NoTarget",
		})
		return
	end

	if not rollsHit(run, move, side, defenderSide) then
		emit(run, {
			kind = "MoveMissed",
			sideId = side.id,
			creatureUid = attacker.uid,
			moveId = move.id,
		})
		return
	end

	for _, effect in move.effects do
		applyEffect(run, effect, move, side, defenderSide)
	end
end

--[[ End of turn ------------------------------------------------------------ ]]

local function runEndOfTurn(run: TurnRun)
	local order = {}
	for _, side in run.state.sides do
		local creature = activeOf(side)
		table.insert(order, {
			side = side,
			speed = effectiveSpeed(run.dex.getStats(creature), side.active.stages, creature.status),
		})
	end
	table.sort(order, function(a, b): boolean
		if a.speed ~= b.speed then
			return a.speed > b.speed
		end
		return a.side.id < b.side.id
	end)

	for _, item in order do
		local side = item.side
		local creature = activeOf(side)
		if creature.currentHp > 0 and creature.status ~= nil then
			local maxHp = run.dex.getStats(creature).hp
			local damage = StatusEffects.endOfTurnDamage(creature.status, maxHp)
			if damage > 0 then
				local applied = math.min(damage, creature.currentHp)
				creature.currentHp -= applied
				emit(run, {
					kind = "StatusDamage",
					sideId = side.id,
					creatureUid = creature.uid,
					status = creature.status,
					amount = applied,
					remainingHp = creature.currentHp,
				})
				if creature.currentHp <= 0 then
					emit(run, { kind = "Fainted", sideId = side.id, creatureUid = creature.uid })
				end
			end
		end
	end
end

--[[ The turn --------------------------------------------------------------- ]]

local function resolveTurn(
	state: BattleState,
	intents: { [number]: BattleIntent },
	context: TurnContext
): TurnOutcome
	local run: TurnRun = {
		state = deepClone(state),
		events = {},
		dex = context.dex,
		rng = context.rng,
	}

	emit(run, { kind = "TurnBegin", turn = run.state.turn })

	-- Snapshot pass: speed and priority are read once, here.
	local entries: { ActionEntry } = {}
	for _, side in run.state.sides do
		local intent = intents[side.id]
		if intent ~= nil then
			local creature = activeOf(side)
			local priority = 0
			if intent.kind == "Move" then
				local slot = creature.moves[intent.slot]
				if slot ~= nil then
					priority = run.dex.getMove(slot.moveId).priority
				end
			end
			table.insert(entries, {
				sideId = side.id,
				kind = intent.kind,
				priority = priority,
				speed = effectiveSpeed(
					run.dex.getStats(creature),
					side.active.stages,
					creature.status
				),
			})
		end
	end

	for _, entry in orderActions(entries, run.rng) do
		local side = sideById(run.state, entry.sideId)

		-- Liveness is re-checked here, not taken from the snapshot. A creature that
		-- fainted earlier this turn silently loses its queued action.
		if activeOf(side).currentHp > 0 then
			local intent = intents[entry.sideId]
			if intent.kind == "Switch" then
				performSwitch(run, side, intent)
			elseif intent.kind == "Move" then
				performMove(run, side, intent)
			else
				error(
					`TurnResolver: intent "{intent.kind}" is not implemented in this phase. `
						.. `Implemented: Move, Switch.`
				)
			end
		end
	end

	runEndOfTurn(run)

	run.state.turn += 1
	for _, event in run.events do
		table.insert(run.state.log, event)
	end

	return { state = run.state, events = run.events }
end

return {
	ACTION_RANK = ACTION_RANK,
	effectiveSpeed = effectiveSpeed,
	orderActions = orderActions,
	resolveTurn = resolveTurn,
}
