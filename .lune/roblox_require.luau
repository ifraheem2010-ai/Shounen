--!strict
--[[
	roblox_require.luau — Roblox instance-require emulation for Lune.

	WHY THIS EXISTS
	---------------
	Roblox resolves modules through the instance tree: `require(script.Parent.Foo)`.
	Lune resolves them through the filesystem: `require("./Foo")`. Those are not
	compatible, and only one of them can be the thing our source files are written in.

	We chose Roblox-native. This shim builds a fake instance tree over the source
	directories and loads every module with `script` and `require` injected into its
	environment, so `src/` stays exactly what Studio and Rojo expect — no build step,
	no darklua conversion — while tests still run headless in milliseconds.

	DO NOT "simplify" this by rewriting src/ to use Lune-style path requires.
	That breaks Studio, which is the actual shipping target.

	A USEFUL SIDE EFFECT
	--------------------
	The injected environment contains no `game`, no `workspace`, no `task`, and no
	`Instance`. Anything in `src/shared/Battle/` that reaches for the Roblox API dies
	loudly the first time a test loads it. Absolute Rule #1 is enforced by physics
	here, not by good intentions. (tests/battle/Purity.spec.luau makes it explicit.)

	MAPPING
	-------
	Directory                       -> Folder
	Directory containing init.luau  -> ModuleScript (Rojo's rule)
	Foo.luau                        -> ModuleScript "Foo"
	Foo.spec.luau                   -> ModuleScript "Foo.spec"
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")

export type Node = {
	Name: string,
	ClassName: string,
	Parent: Node?,
	-- Backing file for ModuleScript nodes; nil for Folder nodes.
	_path: string?,
	_children: { [string]: Node },
	-- Child names in sorted order, so traversal is deterministic across platforms.
	_order: { string },

	FindFirstChild: (self: Node, name: string) -> Node?,
	WaitForChild: (self: Node, name: string, timeout: number?) -> Node,
	GetChildren: (self: Node) -> { Node },
	IsA: (self: Node, className: string) -> boolean,
	GetFullName: (self: Node) -> string,
}

--[[ Instance methods ------------------------------------------------------- ]]

local methods = {}

function methods.FindFirstChild(self: Node, name: string): Node?
	return self._children[name]
end

-- There is nothing to wait for in a synchronous filesystem tree, so this either
-- returns immediately or fails immediately. That is strictly better than Roblox's
-- behaviour, where a typo silently hangs forever.
function methods.WaitForChild(self: Node, name: string, _timeout: number?): Node
	local child = self._children[name]
	if child == nil then
		error(`{self:GetFullName()} has no child named "{name}"`, 2)
	end
	return child
end

function methods.GetChildren(self: Node): { Node }
	local out = {}
	for _, name in self._order do
		table.insert(out, self._children[name])
	end
	return out
end

function methods.IsA(self: Node, className: string): boolean
	return self.ClassName == className or className == "Instance"
end

function methods.GetFullName(self: Node): string
	local parts = { self.Name }
	local current = self.Parent
	while current ~= nil do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end
	return table.concat(parts, ".")
end

local nodeMeta = {
	__index = function(self: any, key: any): any
		local method = methods[key]
		if method ~= nil then
			return method
		end
		local children = rawget(self, "_children")
		if children ~= nil then
			return children[key]
		end
		return nil
	end,

	__tostring = function(self: any): string
		return rawget(self, "Name") :: string
	end,
}

--[[ Tree construction ------------------------------------------------------ ]]

local function newNode(name: string, className: string, parent: Node?): Node
	local node = setmetatable({
		Name = name,
		ClassName = className,
		Parent = parent,
		_path = nil,
		_children = {},
		_order = {},
	}, nodeMeta) :: any

	if parent ~= nil then
		if parent._children[name] ~= nil then
			error(`duplicate child name "{name}" under {parent:GetFullName()}`)
		end
		parent._children[name] = node
		table.insert(parent._order, name)
	end

	return node
end

-- "Foo.luau" -> "Foo", "Foo.spec.luau" -> "Foo.spec", "notes.md" -> nil
local function moduleNameOf(entry: string): string?
	return entry:match("^(.+)%.luau?$")
end

local function isInitFile(entry: string): boolean
	return entry == "init.luau" or entry == "init.lua"
end

local function build(dirPath: string, name: string, parent: Node?): Node
	local node: Node
	local initLuau = `{dirPath}/init.luau`
	local initLua = `{dirPath}/init.lua`

	if fs.isFile(initLuau) then
		node = newNode(name, "ModuleScript", parent)
		node._path = initLuau
	elseif fs.isFile(initLua) then
		node = newNode(name, "ModuleScript", parent)
		node._path = initLua
	else
		node = newNode(name, "Folder", parent)
	end

	local entries = fs.readDir(dirPath)
	table.sort(entries)

	for _, entry in entries do
		local full = `{dirPath}/{entry}`
		if fs.isDir(full) then
			build(full, entry, node)
		elseif not isInitFile(entry) then
			local moduleName = moduleNameOf(entry)
			if moduleName ~= nil then
				local child = newNode(moduleName, "ModuleScript", node)
				child._path = full
			end
		end
	end

	return node
end

export type MountMap = { [string]: string }

--[[
	Mounts directories as named children of a synthetic root, mirroring the Rojo tree:

		mount({ Shared = "src/shared", Tests = "tests" })

	produces Root.Shared and Root.Tests, so a module at tests/battle/Foo.spec.luau
	reaches the engine via script.Parent.Parent.Parent.Shared.Battle — the same shape
	of path it would use in Roblox.
]]
local function mount(map: MountMap, rootName: string?): Node
	local root = newNode(rootName or "Root", "Folder", nil)

	local names = {}
	for name in map do
		table.insert(names, name)
	end
	table.sort(names)

	for _, name in names do
		local dir = map[name]
		if not fs.isDir(dir) then
			error(`cannot mount "{name}": "{dir}" is not a directory (cwd is {process.cwd})`)
		end
		build(dir, name, root)
	end

	return root
end

--[[ Requiring -------------------------------------------------------------- ]]

-- The only non-instance requires we honour. Source files must never touch these:
-- they exist for the test harness, which is Lune-only by definition.
local BUILTINS: { [string]: any } = {
	["@lune/fs"] = fs,
	["@lune/luau"] = luau,
	["@lune/process"] = process,
	["@lune/serde"] = serde,
	["@lune/stdio"] = stdio,
}

-- Stand-in value cached for spec modules, which legitimately return nothing.
local SPEC_SENTINEL = table.freeze({})

local moduleCache: { [Node]: { value: any } } = {}
local loadingSet: { [Node]: boolean } = {}

local shimRequire: (target: any) -> any

local function requireNode(node: Node): any
	local cached = moduleCache[node]
	if cached ~= nil then
		return cached.value
	end

	if loadingSet[node] then
		error(`cyclic require detected at {node:GetFullName()}`)
	end
	if node.ClassName ~= "ModuleScript" then
		error(
			`attempted to require {node:GetFullName()}, which is a {node.ClassName}, `
				.. `not a ModuleScript`
		)
	end

	local path = node._path
	if path == nil then
		error(`{node:GetFullName()} is a ModuleScript with no backing file`)
	end

	loadingSet[node] = true

	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = {
			script = node,
			require = shimRequire,
		},
		injectGlobals = true,
	})

	local ok, result = pcall(chunk)
	loadingSet[node] = nil

	if not ok then
		error(`while loading {node:GetFullName()} ({path}):\n{result}`, 0)
	end

	--[[
		Roblox requires a ModuleScript to return a value, and so do we — forgetting the
		trailing `return` is a real and easy mistake in src/, and it should fail loudly.

		Spec files are the one exception. A spec is a script, not a module: it registers
		its tests as a side effect of loading and has nothing to hand back. Requiring a
		pointless `return {}` on every spec forever is boilerplate that teaches people to
		add a line they do not understand.
	]]
	if result == nil then
		if node.Name:match("%.spec$") == nil then
			error(`module {node:GetFullName()} ({path}) did not return a value`)
		end
		result = SPEC_SENTINEL
	end

	moduleCache[node] = { value = result }
	return result
end

shimRequire = function(target: any): any
	if type(target) == "string" then
		local builtin = BUILTINS[target]
		if builtin ~= nil then
			return builtin
		end
		error(
			`require("{target}") is not available here. Source files must use Roblox-style `
				.. `instance requires, e.g. require(script.Parent.Foo).`
		)
	end

	if type(target) == "table" then
		return requireNode(target :: Node)
	end

	error(`require() expected a ModuleScript node, got a {type(target)}`)
end

--[[ Convenience ------------------------------------------------------------ ]]

-- resolve(root, "Shared/Data/TypeChart") -> Node
local function resolve(root: Node, path: string): Node
	local node = root
	for segment in path:gmatch("[^/]+") do
		local child = node:FindFirstChild(segment)
		if child == nil then
			error(`cannot resolve "{path}": {node:GetFullName()} has no child "{segment}"`)
		end
		node = child
	end
	return node
end

local function import(root: Node, path: string): any
	return requireNode(resolve(root, path))
end

-- Depth-first, deterministic order.
local function descendants(node: Node): { Node }
	local out = {}
	for _, child in node:GetChildren() do
		table.insert(out, child)
		for _, grandchild in descendants(child) do
			table.insert(out, grandchild)
		end
	end
	return out
end

return {
	mount = mount,
	require = requireNode,
	resolve = resolve,
	import = import,
	descendants = descendants,
}
