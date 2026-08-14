--!strict
--[[
	Source-level invariants. These are the two Absolute Rules that no unit test of
	behaviour can catch, because a violation compiles and passes every other test
	right up until the day it does not.

	  Rule #1  src/shared/Battle/ contains ZERO Roblox API calls.
	  Rule #3  --!strict everywhere.

	The Lune shim already makes Rule #1 mostly self-enforcing — the injected
	environment has no `game`, no `Instance`, no `task`, so a module that reaches for
	them dies the first time a test loads it. This spec closes the remaining gap:
	code on a path no test exercises yet, and `math.random`, which exists under Lune
	and would silently make a battle unreproducible instead of failing loudly.

	Run from the repo root; run-tests enforces that.
]]

local fs = require("@lune/fs")

local TestKit = require(script.Parent.Parent.TestKit)

local describe = TestKit.describe
local it = TestKit.it
local expect = TestKit.expect
local fail = TestKit.fail

local BATTLE_DIR = "src/shared/Battle"
local STRICT_DIRS = { "src", "tests", ".lune" }

--[[ File collection -------------------------------------------------------- ]]

local function collectLuauFiles(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local full = `{dir}/{entry}`
		if fs.isDir(full) then
			collectLuauFiles(full, out)
		elseif entry:match("%.luau?$") ~= nil then
			table.insert(out, full)
		end
	end
end

type CodeLine = { number: number, text: string }

--[[
	Returns the file's lines with comments removed, so a comment that mentions a
	banned identifier — and the comments in this repo mention several — does not trip
	the scan. Line numbers survive, which is the whole reason this is done line by
	line rather than with one gsub over the file.
]]
local function codeLinesOf(source: string): { CodeLine }
	local lines: { CodeLine } = {}
	local inBlockComment = false
	local lineNumber = 0

	for rawLine in (source .. "\n"):gmatch("([^\n]*)\n") do
		lineNumber += 1
		local text = rawLine

		if inBlockComment then
			local closeAt = text:find("]]", 1, true)
			if closeAt == nil then
				continue
			end
			text = text:sub(closeAt + 2)
			inBlockComment = false
		end

		-- Block comments that open and close on the same line.
		text = text:gsub("%-%-%[%[.-%]%]", "")

		local openAt = text:find("--[[", 1, true)
		if openAt ~= nil then
			text = text:sub(1, openAt - 1)
			inBlockComment = true
		end

		text = text:gsub("%-%-.*$", "")

		if text:match("^%s*$") == nil then
			table.insert(lines, { number = lineNumber, text = text })
		end
	end

	return lines
end

local battleFiles: { string } = {}
if fs.isDir(BATTLE_DIR) then
	collectLuauFiles(BATTLE_DIR, battleFiles)
end
table.sort(battleFiles)

local battleCode: { [string]: { CodeLine } } = {}
for _, path in battleFiles do
	battleCode[path] = codeLinesOf(fs.readFile(path))
end

--[[ Rule #1 ---------------------------------------------------------------- ]]

type BannedApi = {
	label: string,
	pattern: string,
	why: string,
}

--[[
	`%f[%w]` is Luau's frontier pattern: it matches only where the preceding character
	is not alphanumeric. It is what keeps "damage" from matching `game` and
	"CreatureInstance" from matching `Instance` — both of which appear legitimately
	throughout the engine.
]]
local BANNED: { BannedApi } = {
	{
		label = "game",
		pattern = "%f[%w]game%f[%W]",
		why = "the DataModel does not exist in a headless test",
	},
	{ label = "workspace", pattern = "%f[%w]workspace%f[%W]", why = "there is no world here" },
	{ label = "Workspace", pattern = "%f[%w]Workspace%f[%W]", why = "there is no world here" },
	{
		label = "Instance",
		pattern = "%f[%w]Instance%f[%W]",
		why = "battle state is plain tables, so it can be serialised and replayed",
	},
	{
		label = "task.*",
		pattern = "%f[%w]task%.",
		why = "a turn is a state transition, not something that waits",
	},
	{
		label = "math.random",
		pattern = "math%.random",
		why = "THE rule — every roll goes through the injected Rng or the battle stops being reproducible",
	},
	{
		label = "Random.new",
		pattern = "%f[%w]Random%.new",
		why = "same as math.random: use the injected Rng",
	},
	{
		label = "os.*",
		pattern = "%f[%w]os%.",
		why = "a battle that reads the clock cannot be replayed",
	},
	{ label = "tick()", pattern = "%f[%w]tick%(", why = "same as os.*" },
	{ label = "wait()", pattern = "%f[%w]wait%(", why = "same as task.*" },
	{ label = "spawn()", pattern = "%f[%w]spawn%(", why = "same as task.*" },
	{ label = "delay()", pattern = "%f[%w]delay%(", why = "same as task.*" },
	{ label = "DateTime", pattern = "%f[%w]DateTime%f[%W]", why = "same as os.*" },
	{ label = ":GetService", pattern = "GetService", why = "there are no services here" },
	{ label = "Enum", pattern = "%f[%w]Enum%f[%W]", why = "Roblox enums are a Roblox API" },
	{
		label = "Vector3",
		pattern = "%f[%w]Vector3%f[%W]",
		why = "turn-based battles have no geometry",
	},
	{
		label = "CFrame",
		pattern = "%f[%w]CFrame%f[%W]",
		why = "turn-based battles have no geometry",
	},
	{
		label = "@lune/*",
		pattern = "@lune/",
		why = "the engine must not know it is being tested",
	},
}

describe("Rule #1 / the battle engine touches no Roblox API", function()
	it("still has a src/shared/Battle directory to guard", function()
		-- If this fails, the directory moved and every check below silently became a
		-- no-op. That is a worse failure than any of them individually.
		expect(fs.isDir(BATTLE_DIR)).toBe(true)
	end)

	for _, banned in BANNED do
		it(`uses no {banned.label}`, function()
			local hits: { string } = {}
			for _, path in battleFiles do
				for _, line in battleCode[path] do
					if line.text:match(banned.pattern) ~= nil then
						table.insert(
							hits,
							`{path}:{line.number}  {line.text:match("^%s*(.-)%s*$")}`
						)
					end
				end
			end
			if #hits > 0 then
				fail(`{banned.label} is banned — {banned.why}\n{table.concat(hits, "\n")}`)
			end
			expect(#hits).toBe(0)
		end)
	end
end)

--[[ Rule #3 ---------------------------------------------------------------- ]]

describe("Rule #3 / --!strict everywhere", function()
	local sourceFiles: { string } = {}
	for _, dir in STRICT_DIRS do
		if fs.isDir(dir) then
			collectLuauFiles(dir, sourceFiles)
		end
	end
	table.sort(sourceFiles)

	it("finds source files to check", function()
		expect(#sourceFiles).toBeGreaterThan(0)
	end)

	it("starts every Luau file with --!strict", function()
		local offenders: { string } = {}
		for _, path in sourceFiles do
			local firstLine: string? = nil
			for line in (fs.readFile(path) .. "\n"):gmatch("([^\n]*)\n") do
				local trimmed = line:match("^%s*(.-)%s*$")
				if trimmed ~= "" then
					firstLine = trimmed
					break
				end
			end
			if firstLine ~= "--!strict" then
				table.insert(offenders, `{path} begins with {tostring(firstLine)}`)
			end
		end
		if #offenders > 0 then
			fail(table.concat(offenders, "\n"))
		end
		expect(#offenders).toBe(0)
	end)
end)
