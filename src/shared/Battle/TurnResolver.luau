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
	works today against synthetic fixtures and works unchanged when the real tables
	land, which keeps this file out of another agent's territory by construction rather
	than by discipline.

	The engine does import Data/TypeChart. That is deliberate and not a contradiction:
	the chart is RULES, not content — it is as much a part of the battle system as the
	damage formula, and it changes about as often. The tables the dex exists to keep out
	are the CONTENT tables, Moves and Species, which change whenever anyone rebalances
	anything.

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
local TypeChart = require(script.Parent.Parent.Data.TypeChart)
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
type StagedStat = StatBlockModule.StagedStat
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

--[[
	A Luau table indexer keyed by a union type is invariant (CLAUDE.md section 10), so
	`side.active.volatiles.Recharge` is rejected even though Recharge is a VolatileId.
	Every key read or written through this accessor comes from the closed VolatileId
	list in Types/MoveEffect, so the cast cannot introduce a key that does not exist.
]]
local function volatilesOf(side: SideState): { [string]: any }
	return side.active.volatiles :: any
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

--[[
	Per-move scratch space.

	`damageDealt` is why this exists. Recoil and Drain are defined as fractions of what
	the move already did, so the interpreter has to carry that number forward between
	effects rather than recomputing it — a move that hits five times and then drains
	must drain against all five hits, not against the last one.
]]
type MoveRun = {
	damageDealt: number,
}

--[[ HP movement ----------------------------------------------------------- ]]

-- Single funnel for every point of HP the engine removes, so the clamp, the faint
-- event and the log entry cannot disagree between one caller and the next.
local function dealDamage(
	run: TurnRun,
	side: SideState,
	creature: CreatureInstance,
	amount: number,
	effectiveness: number,
	isCritical: boolean
): number
	local applied = math.min(amount, creature.currentHp)
	if applied <= 0 then
		return 0
	end

	creature.currentHp -= applied
	emit(run, {
		kind = "DamageDealt",
		sideId = side.id,
		creatureUid = creature.uid,
		amount = applied,
		remainingHp = creature.currentHp,
		effectiveness = effectiveness,
		isCritical = isCritical,
	})

	if creature.currentHp <= 0 then
		emit(run, { kind = "Fainted", sideId = side.id, creatureUid = creature.uid })
	end
	return applied
end

-- Returns 0 and logs nothing when there is nothing to restore, so a full-HP creature
-- using recovery does not produce a misleading "healed 0" line.
local function healCreature(
	run: TurnRun,
	side: SideState,
	creature: CreatureInstance,
	amount: number
): number
	local maxHp = run.dex.getStats(creature).hp
	local applied = math.min(amount, maxHp - creature.currentHp)
	if applied <= 0 then
		return 0
	end

	creature.currentHp += applied
	emit(run, {
		kind = "Healed",
		sideId = side.id,
		creatureUid = creature.uid,
		amount = applied,
		remainingHp = creature.currentHp,
	})
	return applied
end

local function sideForTarget(
	effect: any,
	attackerSide: SideState,
	defenderSide: SideState
): SideState
	local target = MoveEffectModule.targetOf(effect)
	if target == "Self" or target == "UserSide" or target == "UserParty" then
		return attackerSide
	end
	return defenderSide
end

--[[ Damage ---------------------------------------------------------------- ]]

local function applyDamageEffect(
	run: TurnRun,
	moveRun: MoveRun,
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
		moveRun.damageDealt += dealDamage(
			run,
			defenderSide,
			defender,
			result.damage,
			result.effectiveness,
			result.isCritical
		)

		if defender.currentHp <= 0 then
			break
		end
	end
end

--[[
	Damage that ignores the formula. Type effectiveness does not SCALE it — that is the
	point of the primitive — but an immunity still stops it, matching Gen 5, where a
	fixed-damage move cannot reach something its type fundamentally cannot touch.
]]
local function applyFixedDamage(
	run: TurnRun,
	moveRun: MoveRun,
	effect: any,
	move: Move,
	attackerSide: SideState,
	defenderSide: SideState
)
	local attacker = activeOf(attackerSide)
	local targetSide = sideForTarget(effect, attackerSide, defenderSide)
	local target = activeOf(targetSide)

	if effect.respectsTypeChart ~= false and targetSide ~= attackerSide then
		local effectiveness = TypeChart.effectiveness(move.typeId, run.dex.getTyping(target))
		if effectiveness == 0 then
			emit(run, {
				kind = "MoveFailed",
				sideId = attackerSide.id,
				creatureUid = attacker.uid,
				moveId = move.id,
				reason = "NoEffect",
			})
			return
		end
	end

	local amount: number
	if effect.mode == "UserLevel" then
		amount = attacker.level
	elseif effect.mode == "TargetCurrentHpFraction" then
		amount = math.floor(target.currentHp * (effect.value or 0))
	else
		amount = effect.value or 0
	end

	-- A connecting hit always does something.
	moveRun.damageDealt += dealDamage(run, targetSide, target, math.max(1, amount), 1, false)
end

--[[ Recoil and drain ------------------------------------------------------- ]]

local function applyRecoil(run: TurnRun, moveRun: MoveRun, effect: any, attackerSide: SideState)
	local attacker = activeOf(attackerSide)

	local amount: number
	if effect.fractionOfUserMaxHp ~= nil then
		-- Unconditional: this is the user's own cost, not a share of the outcome.
		local maxHp = run.dex.getStats(attacker).hp
		amount = math.max(1, math.floor(maxHp * effect.fractionOfUserMaxHp))
	else
		if moveRun.damageDealt <= 0 then
			-- Nothing landed, so there is nothing to take a fraction of. Charging the
			-- minimum here would bill a player for an immunity they could not see.
			return
		end
		amount = math.max(1, math.floor(moveRun.damageDealt * effect.fractionOfDamageDealt))
	end

	dealDamage(run, attackerSide, attacker, amount, 1, false)
end

local function applyDrain(run: TurnRun, moveRun: MoveRun, effect: any, attackerSide: SideState)
	if moveRun.damageDealt <= 0 then
		return
	end
	local amount = math.max(1, math.floor(moveRun.damageDealt * effect.fractionOfDamageDealt))
	healCreature(run, attackerSide, activeOf(attackerSide), amount)
end

local function applyHeal(
	run: TurnRun,
	effect: any,
	attackerSide: SideState,
	defenderSide: SideState
)
	local targetSide = sideForTarget(effect, attackerSide, defenderSide)
	local target = activeOf(targetSide)

	local amount: number
	if effect.flat ~= nil then
		amount = effect.flat
	else
		local maxHp = run.dex.getStats(target).hp
		amount = math.max(1, math.floor(maxHp * effect.fractionOfMaxHp))
	end

	healCreature(run, targetSide, target, amount)
end

--[[ Status and stages ------------------------------------------------------ ]]

local function applyInflictStatus(
	run: TurnRun,
	effect: any,
	attackerSide: SideState,
	defenderSide: SideState
)
	local targetSide = sideForTarget(effect, attackerSide, defenderSide)
	local target = activeOf(targetSide)

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
	local side = sideForTarget(effect, attackerSide, defenderSide)
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

--[[ Conditions ------------------------------------------------------------ ]]

--[[
	Which volatiles the engine actually acts on.

	A volatile that is stored and never read is worse than one that is missing: the
	state looks right, the log looks right, and the move does nothing. This table names
	the ones with behaviour so the gap is greppable rather than a surprise. Everything
	not listed here is stored faithfully and read by nobody yet.

	  Recharge  blocks the next action, then clears. The price of the 130 tier.
	  Flinch    blocks an action not yet taken this turn, then clears.
	  Taunt     blocks Status moves while it lasts.
]]
local VOLATILE_BEHAVIOUR: { [string]: string } = {
	Recharge = "blocks the next action",
	Flinch = "blocks this turn's action",
	Taunt = "blocks Status moves",
}

local function applyCureStatus(
	run: TurnRun,
	effect: any,
	attackerSide: SideState,
	defenderSide: SideState
)
	local targetSide = sideForTarget(effect, attackerSide, defenderSide)

	-- UserParty is the whole reason this primitive takes a target at all: a cleric
	-- move that only reached the creature already in front of you would not be worth
	-- the turn it costs.
	local creatures: { CreatureInstance } = {}
	if MoveEffectModule.targetOf(effect) == "UserParty" then
		for _, creature in targetSide.party do
			table.insert(creatures, creature)
		end
	else
		table.insert(creatures, activeOf(targetSide))
	end

	local allowed: { [string]: boolean }? = nil
	if effect.statuses ~= nil then
		allowed = {}
		for _, status in effect.statuses do
			(allowed :: any)[status] = true
		end
	end

	for _, creature in creatures do
		local status = creature.status
		if status ~= nil and (allowed == nil or allowed[status] == true) then
			creature.status = nil
			creature.statusTurns = nil
			emit(run, {
				kind = "StatusCured",
				sideId = targetSide.id,
				creatureUid = creature.uid,
				status = status :: StatusId,
			})
		end
	end
end

-- Emits one StatStageChanged per stat that actually moved, so the log says what
-- changed rather than announcing a reset that may have done nothing.
local function resetStagesOn(run: TurnRun, side: SideState, effect: any)
	local before = side.active.stages
	local after = StatStages.reset(before, {
		onlyPositive = effect.onlyPositive,
		onlyNegative = effect.onlyNegative,
	})
	side.active.stages = after

	for _, stat: StagedStat in StatStages.STAGED_STATS do
		local previous = StatStages.get(before, stat)
		local current = StatStages.get(after, stat)
		if previous ~= current then
			emit(run, {
				kind = "StatStageChanged",
				sideId = side.id,
				creatureUid = activeOf(side).uid,
				stat = stat,
				delta = current - previous,
				newStage = current,
			})
		end
	end
end

local function applyResetStatStages(
	run: TurnRun,
	effect: any,
	attackerSide: SideState,
	defenderSide: SideState
)
	if MoveEffectModule.targetOf(effect) == "AllActive" then
		resetStagesOn(run, attackerSide, effect)
		resetStagesOn(run, defenderSide, effect)
		return
	end
	resetStagesOn(run, sideForTarget(effect, attackerSide, defenderSide), effect)
end

local function applyApplyVolatile(
	run: TurnRun,
	effect: any,
	attackerSide: SideState,
	defenderSide: SideState
)
	local side = sideForTarget(effect, attackerSide, defenderSide)
	if not run.rng:nextBoolean(MoveEffectModule.chanceOf(effect)) then
		return
	end

	-- Re-applying does not refresh or stack. Letting it would make a Taunt loop
	-- permanent, which is a lock rather than a play.
	local volatiles = volatilesOf(side)
	if volatiles[effect.volatile] ~= nil then
		return
	end

	volatiles[effect.volatile] = { turnsRemaining = effect.duration }
	emit(run, {
		kind = "VolatileApplied",
		sideId = side.id,
		creatureUid = activeOf(side).uid,
		volatileId = effect.volatile,
	})
end

local function applyRemoveVolatile(
	run: TurnRun,
	effect: any,
	attackerSide: SideState,
	defenderSide: SideState
)
	local side = sideForTarget(effect, attackerSide, defenderSide)
	local volatiles = volatilesOf(side)
	if volatiles[effect.volatile] == nil then
		return
	end

	volatiles[effect.volatile] = nil
	emit(run, {
		kind = "VolatileRemoved",
		sideId = side.id,
		creatureUid = activeOf(side).uid,
		volatileId = effect.volatile,
	})
end

--[[ Dispatch --------------------------------------------------------------- ]]

local function applyEffect(
	run: TurnRun,
	moveRun: MoveRun,
	effect: MoveEffect,
	move: Move,
	attackerSide: SideState,
	defenderSide: SideState
)
	if effect.kind == "Damage" then
		applyDamageEffect(run, moveRun, effect, move, attackerSide, defenderSide)
	elseif effect.kind == "FixedDamage" then
		applyFixedDamage(run, moveRun, effect, move, attackerSide, defenderSide)
	elseif effect.kind == "Recoil" then
		applyRecoil(run, moveRun, effect, attackerSide)
	elseif effect.kind == "Drain" then
		applyDrain(run, moveRun, effect, attackerSide)
	elseif effect.kind == "Heal" then
		applyHeal(run, effect, attackerSide, defenderSide)
	elseif effect.kind == "InflictStatus" then
		applyInflictStatus(run, effect, attackerSide, defenderSide)
	elseif effect.kind == "StatStage" then
		applyStatStageEffect(run, effect, attackerSide, defenderSide)
	elseif effect.kind == "CureStatus" then
		applyCureStatus(run, effect, attackerSide, defenderSide)
	elseif effect.kind == "ResetStatStages" then
		applyResetStatStages(run, effect, attackerSide, defenderSide)
	elseif effect.kind == "ApplyVolatile" then
		applyApplyVolatile(run, effect, attackerSide, defenderSide)
	elseif effect.kind == "RemoveVolatile" then
		applyRemoveVolatile(run, effect, attackerSide, defenderSide)
	else
		error(
			`TurnResolver: effect "{effect.kind}" is not implemented in this phase. `
				.. `Implemented: Damage, FixedDamage, Recoil, Drain, Heal, InflictStatus, `
				.. `StatStage, CureStatus, ResetStatStages, ApplyVolatile, RemoveVolatile.`
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
	local move = run.dex.getMove(slot.moveId)
	local volatiles = volatilesOf(side)

	--[[
		Recharge is checked before anything else and clears itself as it fires, so it
		costs exactly one turn and never two. It also returns before the PP deduction:
		the move was not used, so it is not paid for.
	]]
	if volatiles.Recharge ~= nil then
		volatiles.Recharge = nil
		emit(run, {
			kind = "VolatileRemoved",
			sideId = side.id,
			creatureUid = attacker.uid,
			volatileId = "Recharge",
		})
		emit(run, {
			kind = "MoveFailed",
			sideId = side.id,
			creatureUid = attacker.uid,
			moveId = move.id,
			reason = "Blocked",
		})
		return
	end

	-- A flinch only takes a turn that has not been spent yet. The queue is already
	-- ordered, so a slower flincher simply misses its window.
	if volatiles.Flinch ~= nil then
		emit(run, {
			kind = "MoveFailed",
			sideId = side.id,
			creatureUid = attacker.uid,
			moveId = move.id,
			reason = "Flinched",
		})
		return
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

	if move.category == "Status" and volatiles.Taunt ~= nil then
		emit(run, {
			kind = "MoveFailed",
			sideId = side.id,
			creatureUid = attacker.uid,
			moveId = move.id,
			reason = "Taunted",
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

	local moveRun: MoveRun = { damageDealt = 0 }
	for _, effect in move.effects do
		applyEffect(run, moveRun, effect, move, side, defenderSide)
	end
end

--[[ End of turn ------------------------------------------------------------ ]]

--[[
	Flinch always clears; anything with a duration counts down and expires at zero.
	A volatile applied this turn therefore loses one tick immediately, so "duration 3"
	means three turns INCLUDING the one it landed on.
]]
local function expireVolatiles(run: TurnRun)
	for _, side in run.state.sides do
		local creature = activeOf(side)
		local expired: { string } = {}

		local volatiles = volatilesOf(side)
		for volatileId, volatileState in volatiles do
			if volatileId == "Flinch" then
				table.insert(expired, volatileId)
			elseif volatileState.turnsRemaining ~= nil then
				local remaining = volatileState.turnsRemaining - 1
				if remaining <= 0 then
					table.insert(expired, volatileId)
				else
					volatileState.turnsRemaining = remaining
				end
			end
		end

		-- Collected first, deleted after: removing during iteration is undefined.
		table.sort(expired)
		for _, volatileId in expired do
			volatiles[volatileId] = nil
			emit(run, {
				kind = "VolatileRemoved",
				sideId = side.id,
				creatureUid = creature.uid,
				volatileId = volatileId :: any,
			})
		end
	end
end

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
	expireVolatiles(run)

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
