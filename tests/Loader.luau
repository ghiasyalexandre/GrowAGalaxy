-- Loads game modules in Lune the way Rojo maps them into Roblox, so modules can
-- keep using `require(script.Parent.X)`.
--
-- A .luau file becomes a ModuleScript. A folder with init.luau becomes a
-- ModuleScript whose children are the folder's other files and subfolders.
-- Only `script`, `.Parent`, `.Name`, child indexing, FindFirstChild and
-- WaitForChild are emulated: enough for pure shared modules, not for code
-- that touches Roblox services.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Loader = {}

local cache: { [string]: any } = {}
local loading: { [string]: boolean } = {}
local files: { [string]: boolean } = {}
local dirs: { [string]: boolean } = {}
local nodeMeta = {}

-- Lune's fs calls yield, and yielding inside a metamethod is not allowed, so
-- the file tree is indexed up front and lookups only read these tables.
local function indexTree(dir: string)
	if dirs[dir] then
		return
	end
	dirs[dir] = true
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			indexTree(path)
		else
			files[path] = true
		end
	end
end

local function stripSlash(path: string): string
	return (string.gsub(path, "/+$", ""))
end

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]+$") or "."
end

local function basename(path: string): string
	return string.match(path, "([^/]+)$") or path
end

local function makeNode(path: string, isDir: boolean)
	return setmetatable({ __path = path, __isDir = isDir }, nodeMeta)
end

local function child(node, name: string)
	if not node.__isDir then
		return nil
	end
	local base = node.__path .. "/" .. name
	if files[base .. ".luau"] then
		return makeNode(base .. ".luau", false)
	elseif dirs[base] then
		return makeNode(base, true)
	end
	return nil
end

nodeMeta.__index = function(node, key: string)
	if key == "Parent" then
		return makeNode(dirname(node.__path), true)
	elseif key == "Name" then
		return (string.gsub(basename(node.__path), "%.luau$", ""))
	elseif key == "FindFirstChild" or key == "WaitForChild" then
		return function(self, name: string)
			return child(self, name)
		end
	end
	local found = child(node, key)
	if found == nil then
		error(`{key} is not a valid member of {node.__path}`, 2)
	end
	return found
end

nodeMeta.__tostring = function(node)
	return node.__path
end

local requireNode

local function sourcePath(node): string
	if node.__isDir then
		return node.__path .. "/init.luau"
	end
	return node.__path
end

requireNode = function(node)
	if type(node) ~= "table" or getmetatable(node) ~= nodeMeta then
		error("Loader only supports require(script...) style module references", 2)
	end
	local path = sourcePath(node)
	if cache[path] ~= nil then
		return cache[path]
	end
	if loading[path] then
		error(`circular require of {path}`)
	end
	loading[path] = true
	local env = setmetatable({ script = node, require = requireNode }, { __index = getfenv() })
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = env })
	local result = chunk()
	loading[path] = nil
	cache[path] = if result == nil then false else result
	return result
end

-- Loads the module at `path` (a .luau file without extension, or a folder
-- with init.luau), relative to the repository root.
function Loader.require(path: string): any
	path = stripSlash(path)
	indexTree(string.match(path, "^[^/]+") or path)
	if files[path .. ".luau"] then
		return requireNode(makeNode(path .. ".luau", false))
	end
	return requireNode(makeNode(path, true))
end

return Loader
