--!strict
--[[
	Type chart tests.

	CLAUDE.md's gotcha list records that a test asserting "Frost resists Martial"
	once shipped, was wrong, and was caught only by running it. Frost is WEAK to
	Martial — Martial hits Arcane, Feral and Frost for 2x. That assertion is written
	out explicitly below so the mistake cannot be made silently a second time.
]]

local TestKit = require(script.Parent.Parent.TestKit)
local Shared = script.Parent.Parent.Parent.Shared
local TypeChart = require(Shared.Data.TypeChart)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect
local fail = TestKit.fail

describe("TypeChart / shape", function()
	it("has exactly 12 types", function()
		expect(#TypeChart.ALL_TYPES).toBe(12)
	end)

	it("splits into 7 Discipline and 5 Element", function()
		expect(#TypeChart.DISCIPLINE_TYPES).toBe(7)
		expect(#TypeChart.ELEMENT_TYPES).toBe(5)
	end)

	it("lists no type twice", function()
		local seen: { [string]: boolean } = {}
		for _, typeId in TypeChart.ALL_TYPES do
			expect(seen[typeId]).toBeFalsy()
			seen[typeId] = true
		end
	end)

	it("authors a matchup row for every type", function()
		for _, typeId in TypeChart.ALL_TYPES do
			expect(TypeChart.MATCHUPS[typeId]).never.toBeNil()
		end
	end)

	it("assigns every type to exactly one family", function()
		for _, typeId in TypeChart.DISCIPLINE_TYPES do
			expect(TypeChart.familyOf(typeId)).toBe("Discipline")
		end
		for _, typeId in TypeChart.ELEMENT_TYPES do
			expect(TypeChart.familyOf(typeId)).toBe("Element")
		end
	end)

	it("rejects an unknown type id", function()
		expect(function()
			TypeChart.getMultiplier("Blade" :: any, "Ki")
		end).toThrow("not a known type")
	end)
end)

describe("TypeChart / contradictions", function()
	-- This has been introduced twice during design. It is the single most important
	-- assertion in the file.
	it("lists no defender as both super-effective and resisted", function()
		local contradictions = TypeChart.findContradictions()
		if #contradictions > 0 then
			local first = contradictions[1]
			fail(
				`{first.attacker} -> {first.defender} appears in `
					.. `{table.concat(first.listedIn, " and ")}`
			)
		end
		expect(#contradictions).toBe(0)
	end)
end)

describe("TypeChart / multipliers", function()
	it("returns 1 for an unlisted pair", function()
		expect(TypeChart.getMultiplier("Martial", "Ki")).toBe(1)
	end)

	it("hits Martial > Arcane, Feral, Frost for 2x", function()
		expect(TypeChart.getMultiplier("Martial", "Arcane")).toBe(2)
		expect(TypeChart.getMultiplier("Martial", "Feral")).toBe(2)
		expect(TypeChart.getMultiplier("Martial", "Frost")).toBe(2)
	end)

	-- The assertion that shipped backwards once. Frost does NOT resist Martial.
	it("makes Frost WEAK to Martial, not resistant", function()
		expect(TypeChart.getMultiplier("Martial", "Frost")).toBe(2)
		expect(TypeChart.getMultiplier("Martial", "Frost")).never.toBe(0.5)
	end)

	it("resists Martial into Martial, Forge, Spirit, Terra", function()
		expect(TypeChart.getMultiplier("Martial", "Martial")).toBe(0.5)
		expect(TypeChart.getMultiplier("Martial", "Forge")).toBe(0.5)
		expect(TypeChart.getMultiplier("Martial", "Spirit")).toBe(0.5)
		expect(TypeChart.getMultiplier("Martial", "Terra")).toBe(0.5)
	end)

	it("gives Forge the defensive backbone matchups", function()
		expect(TypeChart.getMultiplier("Forge", "Martial")).toBe(2)
		expect(TypeChart.getMultiplier("Forge", "Frost")).toBe(2)
		expect(TypeChart.getMultiplier("Forge", "Terra")).toBe(2)
	end)

	it("keeps Arcane offensive against Ki, Feral, Aqua", function()
		expect(TypeChart.getMultiplier("Arcane", "Ki")).toBe(2)
		expect(TypeChart.getMultiplier("Arcane", "Feral")).toBe(2)
		expect(TypeChart.getMultiplier("Arcane", "Aqua")).toBe(2)
	end)
end)

describe("TypeChart / immunities", function()
	it("has exactly three immunities", function()
		local count = 0
		for _, attacker in TypeChart.ALL_TYPES do
			for _, defender in TypeChart.ALL_TYPES do
				if TypeChart.getMultiplier(attacker, defender) == 0 then
					count += 1
				end
			end
		end
		expect(count).toBe(3)
	end)

	it("blanks Ki into Spirit", function()
		expect(TypeChart.getMultiplier("Ki", "Spirit")).toBe(0)
	end)

	it("blanks Psyche into Forge — there is no mind to attack", function()
		expect(TypeChart.getMultiplier("Psyche", "Forge")).toBe(0)
	end)

	it("blanks Storm into Terra", function()
		expect(TypeChart.getMultiplier("Storm", "Terra")).toBe(0)
	end)

	-- Symmetric immunities create dead matchups where neither side can act.
	-- Asymmetric ones create hard reads. All three must stay one-directional.
	it("keeps all three immunities asymmetric", function()
		expect(TypeChart.getMultiplier("Spirit", "Ki")).never.toBe(0)
		expect(TypeChart.getMultiplier("Forge", "Psyche")).never.toBe(0)
		expect(TypeChart.getMultiplier("Terra", "Storm")).never.toBe(0)
	end)
end)

describe("TypeChart / starter triangle", function()
	it("cycles Flame > Frost > Terra > Flame at 2x", function()
		expect(TypeChart.getMultiplier("Flame", "Frost")).toBe(2)
		expect(TypeChart.getMultiplier("Frost", "Terra")).toBe(2)
		expect(TypeChart.getMultiplier("Terra", "Flame")).toBe(2)
	end)

	it("does not let the triangle run backwards at 2x", function()
		expect(TypeChart.getMultiplier("Frost", "Flame")).never.toBe(2)
		expect(TypeChart.getMultiplier("Terra", "Frost")).never.toBe(2)
		expect(TypeChart.getMultiplier("Flame", "Terra")).never.toBe(2)
	end)
end)

describe("TypeChart / dual typing", function()
	it("multiplies both halves", function()
		-- Martial hits Arcane 2x and Feral 2x.
		expect(TypeChart.effectiveness("Martial", { "Arcane", "Feral" })).toBe(4)
	end)

	it("cancels a weakness against a resistance", function()
		-- Martial hits Arcane 2x and Terra 0.5x.
		expect(TypeChart.effectiveness("Martial", { "Arcane", "Terra" })).toBe(1)
	end)

	it("stacks two resistances to 0.25x", function()
		-- Ki resists into Arcane and Psyche.
		expect(TypeChart.effectiveness("Ki", { "Arcane", "Psyche" })).toBe(0.25)
	end)

	it("lets an immunity beat any multiplier", function()
		-- Storm hits Forge 2x but cannot touch Terra at all.
		expect(TypeChart.effectiveness("Storm", { "Forge", "Terra" })).toBe(0)
	end)

	it("handles a mono typing", function()
		expect(TypeChart.effectiveness("Flame", { "Frost" })).toBe(2)
	end)

	it("rejects a typing with three entries", function()
		expect(function()
			TypeChart.effectiveness("Flame", { "Frost", "Terra", "Aqua" })
		end).toThrow("1 or 2 entries")
	end)

	it("rejects a dual typing of the same type twice", function()
		expect(function()
			TypeChart.effectiveness("Flame", { "Frost", "Frost" })
		end).toThrow("same type twice")
	end)

	it("rejects an empty typing", function()
		expect(function()
			TypeChart.effectiveness("Flame", {})
		end).toThrow("1 or 2 entries")
	end)
end)

describe("TypeChart / defensive balance", function()
	-- Generated per type: 12 tests each, so a regression names the type it broke.
	for _, typeId in TypeChart.ALL_TYPES do
		it(`{typeId} has 2 to 4 weaknesses`, function()
			local profile = TypeChart.defensiveProfile({ typeId })
			expect(#profile.weaknesses).toBeGreaterThanOrEqual(2)
			expect(#profile.weaknesses).toBeLessThanOrEqual(4)
		end)
	end

	for _, typeId in TypeChart.ALL_TYPES do
		it(`{typeId} has 2 to 5 resistances`, function()
			local profile = TypeChart.defensiveProfile({ typeId })
			expect(#profile.resistances).toBeGreaterThanOrEqual(2)
			expect(#profile.resistances).toBeLessThanOrEqual(5)
		end)
	end

	--[[
		Frost keeps five resistances. Pokemon's Ice type is the canonical design
		failure in this genre: excellent offensively, one resistance, permanently
		unplayable regardless of base stats. Do NOT "fix" Frost by making it more
		offensive — that is the same mistake with extra steps.
	]]
	it("gives Frost exactly 5 resistances", function()
		local profile = TypeChart.defensiveProfile({ "Frost" })
		expect(#profile.resistances).toBe(5)
		expect(profile.resistances).toContain("Ki")
		expect(profile.resistances).toContain("Spirit")
		expect(profile.resistances).toContain("Frost")
		expect(profile.resistances).toContain("Storm")
		expect(profile.resistances).toContain("Aqua")
	end)

	it("gives no mono type a quadruple weakness", function()
		for _, typeId in TypeChart.ALL_TYPES do
			expect(#TypeChart.defensiveProfile({ typeId }).quadWeaknesses).toBe(0)
		end
	end)

	it("finds the quadruple weakness on Martial/Terra", function()
		local profile = TypeChart.defensiveProfile({ "Martial", "Terra" })
		expect(#profile.quadWeaknesses).toBe(3)
		expect(profile.quadWeaknesses).toContain("Ki")
		expect(profile.quadWeaknesses).toContain("Forge")
		expect(profile.quadWeaknesses).toContain("Aqua")
	end)
end)

describe("TypeChart / typing legality", function()
	it("declares all 12 mono types legal", function()
		for _, typeId in TypeChart.ALL_TYPES do
			local verdict = TypeChart.validateTyping({ typeId })
			if not verdict.legal then
				fail(`{typeId} was rejected: {table.concat(verdict.reasons, "; ")}`)
			end
			expect(verdict.legal).toBe(true)
		end
	end)

	it("enumerates 78 possible typings", function()
		expect(#TypeChart.allTypings()).toBe(78)
	end)

	it("declares 72 of them legal", function()
		expect(#TypeChart.allLegalTypings()).toBe(72)
	end)

	it("rejects Frost/Terra for having only one weakness", function()
		local verdict = TypeChart.validateTyping({ "Frost", "Terra" })
		expect(verdict.legal).toBe(false)
		expect(#verdict.profile.weaknesses).toBe(1)
	end)

	it("rejects Arcane/Frost for being too defensively loaded", function()
		local verdict = TypeChart.validateTyping({ "Arcane", "Frost" })
		expect(verdict.legal).toBe(false)
		local defensive = #verdict.profile.resistances + #verdict.profile.immunities
		expect(defensive).toBeGreaterThan(TypeChart.MAX_DEFENSIVE)
	end)

	it("rejects the three typings with two or more quadruple weaknesses", function()
		for _, typing in { { "Ki", "Feral" }, { "Arcane", "Psyche" }, { "Feral", "Frost" } } do
			local verdict = TypeChart.validateTyping(typing)
			expect(verdict.legal).toBe(false)
			expect(#verdict.profile.quadWeaknesses).toBeGreaterThan(TypeChart.MAX_QUAD_WEAKNESS)
		end
	end)

	it("rejects exactly six typings, and only these six", function()
		local illegal: { string } = {}
		for _, typing in TypeChart.allTypings() do
			if not TypeChart.validateTyping(typing).legal then
				table.insert(illegal, table.concat(typing, "/"))
			end
		end
		table.sort(illegal)
		expect(illegal).toEqual({
			"Arcane/Frost",
			"Arcane/Psyche",
			"Feral/Frost",
			"Frost/Terra",
			"Ki/Feral",
			"Martial/Terra",
		})
	end)

	it("gives a reason for every rejection", function()
		for _, typing in TypeChart.allTypings() do
			local verdict = TypeChart.validateTyping(typing)
			if not verdict.legal then
				expect(#verdict.reasons).toBeGreaterThan(0)
			end
		end
	end)
end)

describe("TypeChart / coverage", function()
	--[[
		Measured against the legal typing pool, not the 12 mono-types. Measuring
		against mono-types alone reports about 20 false alarms, because no real team
		is made of mono-types.
	]]
	it("leaves no two-move combination unresisted", function()
		local unresisted = TypeChart.findUnresistedPairs()
		if #unresisted > 0 then
			local rendered = {}
			for _, pair in unresisted do
				table.insert(rendered, table.concat(pair, "+"))
			end
			fail(`unresisted: {table.concat(rendered, ", ")}`)
		end
		expect(#unresisted).toBe(0)
	end)

	it("stays under the coverage ceiling", function()
		expect(#TypeChart.findUnresistedPairs()).toBeLessThanOrEqual(
			TypeChart.MAX_ACCEPTABLE_UNRESISTED_PAIRS
		)
	end)
end)
