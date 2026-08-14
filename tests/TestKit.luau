--!strict
--[[
	TestKit — the entire test framework, with zero external dependencies.

	Deliberately small. A battle engine test should cost nothing to write and
	nothing to run, because the plan calls for 200+ of them before the Phase 1 gate
	opens. Anything that makes a test feel expensive to add will result in fewer
	tests, which is the actual failure mode we are guarding against.

		local TestKit = require(script.Parent.Parent.TestKit)
		local describe, it, expect = TestKit.describe, TestKit.it, TestKit.expect

		describe("damage", function()
			it("doubles against a weakness", function()
				expect(compute(...)).toBe(120)
			end)
		end)

	Matchers use dots, not colons: `expect(x).toBe(y)`. Negate with `.never`:
	`expect(x).never.toBe(y)`.

	There is no beforeEach/afterEach and no mocking, on purpose. The engine is pure
	functions over plain tables; a test that needs setup can just call a helper.
]]

export type TestBody = () -> ()

export type Matchers = {
	toBe: (expected: any) -> (),
	toEqual: (expected: any) -> (),
	toBeCloseTo: (expected: number, tolerance: number?) -> (),
	toBeTruthy: () -> (),
	toBeFalsy: () -> (),
	toBeNil: () -> (),
	toBeType: (typeName: string) -> (),
	toThrow: (substring: string?) -> (),
	toContain: (value: any) -> (),
	toHaveLength: (length: number) -> (),
	toBeGreaterThan: (value: number) -> (),
	toBeGreaterThanOrEqual: (value: number) -> (),
	toBeLessThan: (value: number) -> (),
	toBeLessThanOrEqual: (value: number) -> (),
	never: Matchers,
}

export type Test = {
	path: { string },
	name: string,
	fullName: string,
	body: TestBody,
}

export type Failure = {
	fullName: string,
	message: string,
	traceback: string?,
	-- false when the test crashed rather than failing an assertion.
	isAssertion: boolean,
}

export type RunOptions = {
	filter: string?,
}

export type RunResult = {
	passed: number,
	failed: number,
	skipped: number,
	failures: { Failure },
	durationMs: number,
}

--[[ Value rendering -------------------------------------------------------- ]]

local MAX_DEPTH = 3
local MAX_ENTRIES = 12

local function show(value: any, depth: number?): string
	local d = depth or 0
	local valueType = type(value)

	if valueType == "string" then
		return `"{value}"`
	elseif valueType ~= "table" then
		return tostring(value)
	elseif d >= MAX_DEPTH then
		return "{...}"
	end

	local arrayLength = #value
	local keyCount = 0
	local allNumericKeys = true
	for key in value do
		keyCount += 1
		if type(key) ~= "number" then
			allNumericKeys = false
		end
	end

	local parts = {}

	if allNumericKeys and keyCount == arrayLength then
		for index, element in value do
			if index > MAX_ENTRIES then
				table.insert(parts, `...{arrayLength - MAX_ENTRIES} more`)
				break
			end
			table.insert(parts, show(element, d + 1))
		end
	else
		local keys: { { key: any, rendered: string } } = {}
		for key in value do
			table.insert(keys, { key = key, rendered = tostring(key) })
		end
		table.sort(keys, function(a, b)
			return a.rendered < b.rendered
		end)
		for index, entry in keys do
			if index > MAX_ENTRIES then
				table.insert(parts, `...{#keys - MAX_ENTRIES} more`)
				break
			end
			table.insert(parts, `{entry.rendered} = {show((value :: any)[entry.key], d + 1)}`)
		end
	end

	return "{" .. table.concat(parts, ", ") .. "}"
end

local function deepEqual(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not deepEqual(value, (b :: any)[key]) then
			return false
		end
	end
	for key in b do
		if (a :: any)[key] == nil then
			return false
		end
	end
	return true
end

--[[ Assertions ------------------------------------------------------------- ]]

-- Assertion failures are thrown as tables so the runner can tell "this test found
-- a bug" apart from "this test itself is broken". Both are failures; only one of
-- them deserves a stack trace.
type AssertionError = { __testkit: true, message: string }

local function fail(message: string): never
	error({ __testkit = true, message = message } :: AssertionError, 0)
end

-- Returns `any` rather than `Matchers`: the `never` field is cross-linked by
-- expect() afterwards, so the table is genuinely incomplete until then.
local function buildMatchers(actual: any, negated: boolean): any
	-- `positive` is the message when a non-negated expectation fails,
	-- `negative` is the message when a `.never` expectation fails.
	local function check(condition: boolean, positive: string, negative: string)
		if negated then
			if condition then
				fail(negative)
			end
		elseif not condition then
			fail(positive)
		end
	end

	local m = {}

	m.toBe = function(expected: any)
		check(
			rawequal(actual, expected),
			`expected {show(expected)}, got {show(actual)}`,
			`expected value not to be {show(expected)}`
		)
	end

	m.toEqual = function(expected: any)
		check(
			deepEqual(actual, expected),
			`expected {show(expected)}, got {show(actual)}`,
			`expected value not to deep-equal {show(expected)}`
		)
	end

	m.toBeCloseTo = function(expected: number, tolerance: number?)
		local epsilon = tolerance or 1e-9
		if type(actual) ~= "number" then
			fail(`expected a number for toBeCloseTo, got {show(actual)}`)
		end
		local delta = math.abs(actual - expected)
		check(
			delta <= epsilon,
			`expected {expected} (±{epsilon}), got {actual} (off by {delta})`,
			`expected value not to be within {epsilon} of {expected}`
		)
	end

	m.toBeTruthy = function()
		check(
			actual ~= nil and actual ~= false,
			`expected a truthy value, got {show(actual)}`,
			`expected a falsy value, got {show(actual)}`
		)
	end

	m.toBeFalsy = function()
		check(
			actual == nil or actual == false,
			`expected a falsy value, got {show(actual)}`,
			`expected a truthy value, got {show(actual)}`
		)
	end

	m.toBeNil = function()
		check(actual == nil, `expected nil, got {show(actual)}`, `expected a value, got nil`)
	end

	m.toBeType = function(typeName: string)
		check(
			type(actual) == typeName,
			`expected type "{typeName}", got "{type(actual)}" ({show(actual)})`,
			`expected type not to be "{typeName}"`
		)
	end

	m.toThrow = function(substring: string?)
		if type(actual) ~= "function" then
			fail(`toThrow expects a function, got {show(actual)}`)
		end
		-- Cast to a varargs return: `() -> ()` tells the solver pcall yields a single
		-- value, and the `err` binding silently becomes an error.
		local ok, err = pcall(actual :: () -> ...any)
		local message = if type(err) == "table" and (err :: any).message ~= nil
			then tostring((err :: any).message)
			else tostring(err)

		if negated then
			if not ok then
				fail(`expected no error, but got: {message}`)
			end
			return
		end

		if ok then
			fail("expected the function to throw, but it returned normally")
		end
		if substring ~= nil and not string.find(message, substring, 1, true) then
			fail(`expected the error to contain "{substring}", but it was: {message}`)
		end
	end

	m.toContain = function(value: any)
		if type(actual) ~= "table" then
			fail(`toContain expects a table, got {show(actual)}`)
		end
		local found = false
		for _, element in actual :: { any } do
			if deepEqual(element, value) then
				found = true
				break
			end
		end
		check(
			found,
			`expected {show(actual)} to contain {show(value)}`,
			`expected {show(actual)} not to contain {show(value)}`
		)
	end

	m.toHaveLength = function(length: number)
		if type(actual) ~= "table" and type(actual) ~= "string" then
			fail(`toHaveLength expects a table or string, got {show(actual)}`)
		end
		local actualLength = #actual
		check(
			actualLength == length,
			`expected length {length}, got {actualLength}`,
			`expected length not to be {length}`
		)
	end

	-- Written out rather than generated in a loop: assigning `m[name]` with a computed
	-- key turns `m` into an indexed table and loses every field type above it.
	local function asNumber(matcher: string): number
		if type(actual) ~= "number" then
			fail(`{matcher} expects a number, got {show(actual)}`)
		end
		return actual :: number
	end

	m.toBeGreaterThan = function(value: number)
		local n = asNumber("toBeGreaterThan")
		check(n > value, `expected {n} > {value}`, `expected {n} not > {value}`)
	end

	m.toBeGreaterThanOrEqual = function(value: number)
		local n = asNumber("toBeGreaterThanOrEqual")
		check(n >= value, `expected {n} >= {value}`, `expected {n} not >= {value}`)
	end

	m.toBeLessThan = function(value: number)
		local n = asNumber("toBeLessThan")
		check(n < value, `expected {n} < {value}`, `expected {n} not < {value}`)
	end

	m.toBeLessThanOrEqual = function(value: number)
		local n = asNumber("toBeLessThanOrEqual")
		check(n <= value, `expected {n} <= {value}`, `expected {n} not <= {value}`)
	end

	return m
end

local function expect(actual: any): Matchers
	local positive: any = buildMatchers(actual, false)
	local negative: any = buildMatchers(actual, true)
	positive.never = negative
	negative.never = positive
	return positive :: Matchers
end

--[[ Registry --------------------------------------------------------------- ]]

local suiteStack: { string } = {}
local registered: { Test } = {}

local function describe(name: string, body: () -> ())
	table.insert(suiteStack, name)
	local ok, err = pcall(body :: () -> ...any)
	table.remove(suiteStack)
	if not ok then
		error(`error while registering describe("{name}"):\n{tostring(err)}`, 0)
	end
end

local function it(name: string, body: TestBody)
	local path = table.clone(suiteStack)
	local prefix = if #path > 0 then table.concat(path, " > ") .. " > " else ""
	table.insert(registered, {
		path = path,
		name = name,
		fullName = prefix .. name,
		body = body,
	})
end

local function run(options: RunOptions?): RunResult
	local filter = if options then options.filter else nil
	local loweredFilter = if filter then string.lower(filter) else nil

	local passed = 0
	local skipped = 0
	local failures: { Failure } = {}
	local startedAt = os.clock()

	for _, test in registered do
		if
			loweredFilter ~= nil
			and not string.find(string.lower(test.fullName), loweredFilter, 1, true)
		then
			skipped += 1
			continue
		end

		local traceback: string? = nil
		local ok, err = xpcall(test.body :: () -> ...any, function(caught: any): any
			if type(caught) == "table" and (caught :: any).__testkit == true then
				return caught
			end
			traceback = debug.traceback(tostring(caught), 2)
			return caught
		end)

		if ok then
			passed += 1
		elseif type(err) == "table" and (err :: any).__testkit == true then
			table.insert(failures, {
				fullName = test.fullName,
				message = tostring((err :: any).message),
				traceback = nil,
				isAssertion = true,
			})
		else
			table.insert(failures, {
				fullName = test.fullName,
				message = tostring(err),
				traceback = traceback,
				isAssertion = false,
			})
		end
	end

	return {
		passed = passed,
		failed = #failures,
		skipped = skipped,
		failures = failures,
		durationMs = (os.clock() - startedAt) * 1000,
	}
end

local function count(): number
	return #registered
end

return {
	describe = describe,
	it = it,
	expect = expect,
	run = run,
	count = count,
	-- For assertions whose failure message is worth building by hand — a list of every
	-- offending file, say. Raw error() works too, but the runner then reports it as a
	-- crashed test rather than a failed one, which buries the message under a
	-- traceback nobody needs.
	fail = fail,
	-- Exposed for the runner's own diagnostics, not for use inside tests.
	_show = show,
	_deepEqual = deepEqual,
}
