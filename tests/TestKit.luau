-- Minimal test helpers for the Lune test runner.

local TestKit = {
	passed = 0,
	failed = 0,
}

local currentGroup = ""

function TestKit.describe(name: string, body: () -> ())
	local previous = currentGroup
	currentGroup = if previous == "" then name else `{previous} > {name}`
	body()
	currentGroup = previous
end

function TestKit.test(name: string, body: () -> ())
	local ok, err = pcall(body)
	local label = if currentGroup == "" then name else `{currentGroup} > {name}`
	if ok then
		TestKit.passed += 1
		print(`  ok    {label}`)
	else
		TestKit.failed += 1
		print(`  FAIL  {label}\n        {err}`)
	end
end

local function show(value: any): string
	if type(value) == "string" then
		return `"{value}"`
	end
	return tostring(value)
end

function TestKit.equal(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(`{label or "value"}: expected {show(expected)}, got {show(actual)}`, 2)
	end
end

function TestKit.near(actual: number, expected: number, epsilon: number?, label: string?)
	if math.abs(actual - expected) > (epsilon or 1e-6) then
		error(`{label or "value"}: expected ~{expected}, got {actual}`, 2)
	end
end

function TestKit.truthy(value: any, label: string?)
	if not value then
		error(`{label or "value"}: expected truthy, got {show(value)}`, 2)
	end
end

function TestKit.falsy(value: any, label: string?)
	if value then
		error(`{label or "value"}: expected falsy, got {show(value)}`, 2)
	end
end

function TestKit.deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value do
		copy[key] = TestKit.deepCopy(inner)
	end
	return copy
end

return TestKit
