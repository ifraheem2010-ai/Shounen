--!strict
--[[
	Temporary analysis: does the starter triangle actually play out?

	The chart says Flame > Frost > Terra > Flame at 2x. This runs each edge as a
	head-to-head over many seeds and reports win rates, at a low level and a high one,
	because the answer is not the same at both.

	Not part of the suite. Run with `lune run triangle`.
]]

local shim = require("./roblox_require")

local root = shim.mount({ Shared = "src/shared", Tests = "tests" })
local Battle = shim.import(root, "Tests/fixtures/SyntheticBattle")
local Engine = shim.import(root, "Shared/Battle/Engine")
local GateBattle = shim.import(root, "Tests/fixtures/GateBattle")
local MoveModule = shim.import(root, "Shared/Types/Move")
local Moves = shim.import(root, "Shared/Data/Moves")
local RNG = shim.import(root, "Shared/Battle/RNG")
local Species = shim.import(root, "Shared/Data/Species")

local TypeChart = shim.import(root, "Shared/Data/TypeChart")

--[[
	Picks the damaging move with the highest expected power: base power, times STAB,
	times the type multiplier against whatever is actually in front of it.

	The first-usable controller the gate uses is fine for a determinism demo and useless
	here — it would have Cairnling open with a 40-power priority move and never touch
	its 75-power Forge attack, which hits Flame for double. Measuring the type triangle
	with a controller that ignores type would answer a question nobody asked.
]]
local function bestEffortController(): any
	return {
		chooseAction = function(sideId: number, state: any): any
			local side = state.sides[sideId]
			local foe = state.sides[if sideId == 1 then 2 else 1]
			local active = side.party[side.active.partyIndex]
			local target = foe.party[foe.active.partyIndex]

			local typing = Species.getSpecies(active.speciesId).typing
			local targetTyping = Species.getSpecies(target.speciesId).typing

			local bestSlot, bestScore = 1, -1
			for slot, entry in active.moves do
				if entry.pp > 0 then
					local move = Moves.getMove(entry.moveId)
					if MoveModule.isDamaging(move) then
						local score = MoveModule.displayPower(move)
							* TypeChart.effectiveness(move.typeId, targetTyping)
						for _, own in typing do
							if own == move.typeId then
								score *= 1.5
							end
						end
						if score > bestScore then
							bestScore, bestSlot = score, slot
						end
					end
				end
			end
			return { kind = "Move", slot = bestSlot }
		end,
		chooseReplacement = function(_sideId: number, legal: { number }, _state: any): number
			return legal[1]
		end,
	}
end

local function duel(oneId: string, twoId: string, level: number, seed: number): string
	local state = Battle.state({
		seed = seed,
		sides = {
			Battle.side({ id = 1, party = { GateBattle.creatureFor(oneId, level, "one") } }),
			Battle.side({ id = 2, party = { GateBattle.creatureFor(twoId, level, "two") } }),
		},
	})
	local engine = Engine.create({
		state = state,
		dex = GateBattle.realDex(),
		rng = RNG.new(seed),
		controllers = { [1] = bestEffortController(), [2] = bestEffortController() },
		maxTurns = 300,
	})
	return Engine.run(engine).outcome
end

local function report(label: string, oneId: string, twoId: string, level: number, expected: string)
	local wins, losses, draws = 0, 0, 0
	local samples = 200
	for seed = 1, samples do
		local outcome = duel(oneId, twoId, level, seed)
		if outcome == "Side1Win" then
			wins += 1
		elseif outcome == "Side2Win" then
			losses += 1
		else
			draws += 1
		end
	end

	local one = Species.getSpecies(oneId)
	local two = Species.getSpecies(twoId)
	local rate = wins / samples * 100
	local verdict = if rate > 55 then "chart holds" elseif rate < 45 then "CHART INVERTED" else "coin flip"

	print(
		string.format(
			"  %-28s %-11s %3d%% / %3d%% (draw %d)   %s",
			label,
			`L{level}`,
			math.floor(rate + 0.5),
			math.floor(losses / samples * 100 + 0.5),
			draws,
			verdict
		)
	)
	print(
		`      {one.name} [{table.concat(Species.defaultMoveset(oneId, level), ", ")}]`
	)
	print(
		`      {two.name} [{table.concat(Species.defaultMoveset(twoId, level), ", ")}]`
	)
	print(`      expected: {expected}`)
end

print("")
print("STARTER TRIANGLE — 200 seeds per edge, win% for the side the chart favours")
print("")
print("LEVEL 15 (all stage 1, pre-evolution)")
report("Flame vs Frost", "flame.emberlin", "frost.rimeling", 15, "Flame wins (2x)")
report("Frost vs Terra", "frost.rimeling", "terra.cairnling", 15, "Frost wins (2x)")
report("Terra vs Flame", "terra.cairnling", "flame.emberlin", 15, "Terra wins (2x)")

print("")
print("LEVEL 50 (all stage 3, every line has its same-type move)")
report("Flame vs Frost", "flame.pyrecant", "frost.glacivast", 50, "Flame wins (2x)")
report("Frost vs Terra", "frost.glacivast", "terra.cragmarrow", 50, "Frost wins (2x)")
report("Terra vs Flame", "terra.cragmarrow", "flame.pyrecant", 50, "Terra wins (2x)")
print("")
