--!strict
--[[
	Headless test entry point.

		lune run run-tests
		lune run run-tests -- --filter data
		lune run run-tests -- --list

	Mounts src/ and tests/ as a fake Roblox instance tree (see roblox_require.luau),
	loads every *.spec.luau under tests/, and runs them. No Studio, no DataModel, no
	network — the whole suite is a few milliseconds of pure Luau.

	Must be run from the repo root.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local shim = require("./roblox_require")

--[[ Preflight -------------------------------------------------------------- ]]

if not fs.isDir("src") or not fs.isDir("tests") then
	stdio.ewrite(
		`run-tests must be run from the repo root; cwd is {process.cwd}\n`
			.. "  cd to the directory containing default.project.json and try again.\n"
	)
	process.exit(2)
end

--[[ Arguments -------------------------------------------------------------- ]]

local filter: string? = nil
local listOnly = false

local index = 1
while index <= #process.args do
	local arg = process.args[index]
	if arg == "--" then
		-- Lune forwards the separator itself rather than swallowing it, so both
		-- `lune run run-tests -- --filter x` and `lune run run-tests --filter x` work.
		index += 1
	elseif arg == "--filter" or arg == "-f" then
		filter = process.args[index + 1]
		if filter == nil then
			stdio.ewrite("--filter requires a value\n")
			process.exit(2)
		end
		index += 2
	elseif arg == "--list" or arg == "-l" then
		listOnly = true
		index += 1
	else
		stdio.ewrite(`unknown argument "{arg}"\n`)
		process.exit(2)
	end
end

--[[ Output helpers --------------------------------------------------------- ]]

local function paint(color: string, text: string): string
	return stdio.color(color :: any) .. text .. stdio.color("reset")
end

local function bold(text: string): string
	return stdio.style("bold") .. text .. stdio.style("reset")
end

--[[ Load ------------------------------------------------------------------- ]]

local root = shim.mount({
	Shared = "src/shared",
	Server = "src/server",
	Client = "src/client",
	Tests = "tests",
})

local TestKit = shim.import(root, "Tests/TestKit")

local specs = {}
for _, node in shim.descendants(shim.resolve(root, "Tests")) do
	if node.ClassName == "ModuleScript" and node.Name:match("%.spec$") ~= nil then
		table.insert(specs, node)
	end
end

if #specs == 0 then
	stdio.ewrite("no *.spec.luau files found under tests/\n")
	process.exit(2)
end

for _, spec in specs do
	shim.require(spec)
end

--[[ Run -------------------------------------------------------------------- ]]

print(bold("shounen test suite"))
print(`  {#specs} spec file(s), {TestKit.count()} test(s) registered`)
if filter ~= nil then
	print(`  filter: "{filter}"`)
end
print("")

if listOnly then
	for _, spec in specs do
		print(`  {spec:GetFullName()}`)
	end
	process.exit(0)
end

local result = TestKit.run({ filter = filter })

for _, failure in result.failures do
	print(`{paint("red", "FAIL")}  {failure.fullName}`)
	for line in failure.message:gmatch("[^\n]+") do
		print(`        {line}`)
	end
	if not failure.isAssertion then
		print(`        {paint("yellow", "(this test crashed rather than failing an assertion)")}`)
		if failure.traceback ~= nil then
			for line in failure.traceback:gmatch("[^\n]+") do
				print(`        {paint("black", line)}`)
			end
		end
	end
	print("")
end

local duration = string.format("%.1f ms", result.durationMs)
local summary = `{result.passed} passed, {result.failed} failed, {result.skipped} skipped  ({duration})`

if result.failed > 0 then
	print(paint("red", bold(summary)))
	process.exit(1)
end

if result.passed == 0 then
	print(paint("yellow", bold(`{summary} — nothing ran, which is not the same as passing`)))
	process.exit(1)
end

print(paint("green", bold(summary)))
process.exit(0)
