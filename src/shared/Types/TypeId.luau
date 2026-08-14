--!strict
--[[
	The 12 types, as types.

	Type identity is defined by the SOURCE OF A PERSON'S POWER, never by "what the
	creature is". Every creature in this game is a human, so "what it is" fails as an
	axis — that is why the original Beast/Machine draft was scrapped.

	This module is shapes only. The chart, the ordering, and the validators live in
	Data/TypeChart.luau. Read docs/TYPES.md before touching either.
]]

--[[
	Discipline — where the power comes from.

	The Ki/Arcane test: if the power stops working when the character is alone in an
	empty room, it is Arcane. If it does not, it is Ki.
]]
export type DisciplineType =
	"Martial" -- trained body, weapons, technique
	| "Ki" -- internal energy, aura, cultivated force
	| "Arcane" -- contracts, sigils, curses, summons, sealed artifacts
	| "Psyche" -- mental force
	| "Spirit" -- ghosts, demons, the ethereal, possession
	| "Feral" -- transforming your own body
	| "Forge" -- built gear, augmentation, powered armor, drones

--[[
	Element — what natural force they command.

	The character COMMANDS the element; they are not made of it. A fire-shaped blob
	is a different game's starter. A swordsman whose blade breathes cinder is this one.
]]
export type ElementType =
	"Flame" -- combustion, temper
	| "Frost" -- ice, stillness, preservation
	| "Storm" -- lightning and wind
	| "Terra" -- stone, weight, gravity
	| "Aqua" -- flow, pressure, adaptability

--[[
	Written out flat rather than as `DisciplineType | ElementType`.

	A union of two alias unions gets flattened by the Luau solver into plain `string`,
	which silently destroys the whole point: `{ TypeId }` stops rejecting typos and
	every chart lookup becomes unchecked. The two aliases above stay for documentation
	and for signatures that genuinely mean one family or the other.

	If you add a type here, add it to the matching family alias above and to
	ALL_TYPES in Data/TypeChart.luau. Three places, deliberately — the test suite
	catches it if you miss one.
]]
export type TypeId =
	"Martial"
	| "Ki"
	| "Arcane"
	| "Psyche"
	| "Spirit"
	| "Feral"
	| "Forge"
	| "Flame"
	| "Frost"
	| "Storm"
	| "Terra"
	| "Aqua"

export type TypeFamily = "Discipline" | "Element"

-- One or two entries. Two entries must be distinct; Data/TypeChart validates this.
export type Typing = { TypeId }

return {}
