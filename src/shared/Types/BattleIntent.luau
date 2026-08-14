--!strict
--[[
	What a client is allowed to say.

	Absolute Rule #2: clients send INTENT, never results. A client says "I want to use
	move slot 2"; the server decides what happened. There is no field anywhere in this
	file for a damage number, a hit/miss, a catch result, or an encounter roll,
	because if the shape cannot express a claim the client cannot make one.

	Every field here is an index or an id — never a computed outcome. Validate all of
	them server-side anyway: a slot index is still a number an attacker can set to
	anything.
]]

export type MoveIntent = {
	kind: "Move",
	-- 1..4, index into the active creature's move slots.
	slot: number,
	-- Which side and party index to hit. Ignored for self-targeting moves and for
	-- 1v1, where there is only one legal target.
	targetSideId: number?,
	targetPartyIndex: number?,
}

export type SwitchIntent = {
	kind: "Switch",
	-- Index into the requesting side's party.
	partyIndex: number,
}

export type ItemIntent = {
	kind: "Item",
	itemId: string,
	-- Which of the user's own party members the item is used on, if any.
	targetPartyIndex: number?,
	-- Set when the item targets the opposing creature, e.g. a ball.
	targetsOpponent: boolean?,
}

export type RunIntent = {
	kind: "Run",
}

export type ForfeitIntent = {
	kind: "Forfeit",
}

export type BattleIntent = MoveIntent | SwitchIntent | ItemIntent | RunIntent | ForfeitIntent

export type SubmittedIntent = {
	battleId: string,
	sideId: number,
	-- The turn this intent was submitted for. An intent for a turn that has already
	-- resolved is dropped, which is what stops a lagging or replaying client from
	-- acting twice.
	turn: number,
	intent: BattleIntent,
}

export type IntentKind = "Move" | "Switch" | "Item" | "Run" | "Forfeit"

local INTENT_KINDS: { IntentKind } = { "Move", "Switch", "Item", "Run", "Forfeit" }

return {
	INTENT_KINDS = INTENT_KINDS,
}
