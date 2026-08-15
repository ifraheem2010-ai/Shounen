--!strict
--[[
	The Phase 1 gate demonstration.

		lune run gate-6v6

	Runs one full 6v6 from a fixed seed using the real move table and the real engine,
	and prints every BattleEvent it produced. Then runs the identical battle a second
	time and compares the two logs line for line, because "deterministic" is a claim
	that has to be shown rather than asserted in a comment.

	The battle itself is built in tests/fixtures/GateBattle.luau, which the determinism
	spec also uses — so the battle printed here and the battle the suite checks are
	provably the same one.
]]

local process = require("@lune/process")
local stdio = require("@lune/stdio")

local shim = require("./roblox_require")

local GATE_SEED = 12345

local root = shim.mount({ Shared = "src/shared", Tests = "tests" })
local Engine = shim.import(root, "Shared/Battle/Engine")
local GateBattle = shim.import(root, "Tests/fixtures/GateBattle")
local Species = shim.import(root, "Shared/Data/Species")

local function bold(text: string): string
	return stdio.style("bold") .. text .. stdio.style("reset")
end

local function paint(color: string, text: string): string
	return stdio.color(color :: any) .. text .. stdio.color("reset")
end

--[[
	Renders one event as a single line. Deliberately mechanical: this is the log, not a
	battle transcript, and the point is that every field the engine recorded is visible.
]]
local function render(event: any): string
	local parts: { string } = {}
	local keys: { string } = {}
	for key in event do
		if key ~= "kind" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	for _, key in keys do
		table.insert(parts, `{key}={tostring(event[key])}`)
	end
	return `{event.kind}  {table.concat(parts, "  ")}`
end

local function runOnce(): any
	local engine = GateBattle.build(GATE_SEED)
	return Engine.run(engine)
end

print("")
print(bold("PHASE 1 GATE — full 6v6 from a fixed seed"))
print(`seed {GATE_SEED} | real move table | real species table | level {GateBattle.GATE_LEVEL}`)
print("")

local function printRoster(label: string, roster: { string })
	print(bold(label))
	for index, speciesId in roster do
		local entry = Species.getSpecies(speciesId)
		local moves = Species.defaultMoveset(speciesId, GateBattle.GATE_LEVEL)
		print(
			`  {index}. {entry.name}  {table.concat(entry.typing, "/")}  `
				.. `{entry.role}  stage {entry.stage}  [{table.concat(moves, ", ")}]`
		)
	end
end

printRoster("SIDE 1", GateBattle.ROSTER_ONE)
printRoster("SIDE 2", GateBattle.ROSTER_TWO)

local first = runOnce()

print("")
print(bold(`EVENT LOG — {#first.events} events across {first.turns} turns`))
print("")

local turn = 0
for index, event in first.events do
	if event.kind == "TurnBegin" then
		turn += 1
		print(paint("cyan", `-- turn {event.turn} --`))
	end
	print(`  {string.format("%4d", index)}  {render(event)}`)
end

print("")
print(bold(`OUTCOME: {first.outcome}`))
print("")

--[[ Determinism, demonstrated rather than claimed ------------------------- ]]

local second = runOnce()

local identical = #first.events == #second.events
local firstDifference = 0
if identical then
	for index = 1, #first.events do
		if render(first.events[index]) ~= render(second.events[index]) then
			identical = false
			firstDifference = index
			break
		end
	end
else
	firstDifference = math.min(#first.events, #second.events) + 1
end

print(bold("DETERMINISM"))
print(`  run 1: {#first.events} events, outcome {first.outcome}, {first.turns} turns`)
print(`  run 2: {#second.events} events, outcome {second.outcome}, {second.turns} turns`)

if identical then
	print(paint("green", "  identical: every event matches line for line"))
	print("")
	process.exit(0)
end

print(paint("red", `  DIVERGED at event {firstDifference}`))
print(`    run 1: {render(first.events[firstDifference])}`)
print(`    run 2: {render(second.events[firstDifference])}`)
print("")
process.exit(1)
