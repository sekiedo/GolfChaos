-- Banc d'essai LOCAL (hors Roblox) : émulation minimale des API Roblox pour exécuter les tests unitaires des
-- modules purs avec l'interpréteur Luau (tools/luau.exe). Assemblé par scripts/essais-locaux.sh.
-- Ce n'est PAS Roblox : un test vert ici ne remplace pas une exécution dans Studio.

local __M = {} -- chemin Roblox -> fonction du module
local __typeof = typeof

--------------------------------------------------------------------------------
-- Signaux et instances factices
--------------------------------------------------------------------------------
local function stubSignal()
	local handlers = {}
	local signal = {}
	function signal.Connect(_self, fn)
		table.insert(handlers, fn)
		local connection = { Connected = true }
		function connection.Disconnect(self)
			self.Connected = false
			local index = table.find(handlers, fn)
			if index then
				table.remove(handlers, index)
			end
		end
		return connection
	end
	signal.Once = signal.Connect
	function signal.Wait() end
	function signal.Fire(_self, ...)
		for _, fn in table.clone(handlers) do
			fn(...)
		end
	end
	return signal
end

local Methods = {}
local NodeMeta = {}

local function newNode(name, class)
	return setmetatable({ Name = name, ClassName = class, _children = {}, _attrs = {}, _isInstance = true }, NodeMeta)
end

NodeMeta.__index = function(self, key)
	local method = Methods[key]
	if method then
		return method
	end
	if key == "Parent" then
		return rawget(self, "_parent")
	end
	for _, child in rawget(self, "_children") do
		if child.Name == key then
			return child
		end
	end
	return nil
end

NodeMeta.__newindex = function(self, key, value)
	if key == "Parent" then
		local old = rawget(self, "_parent")
		if old then
			local list = rawget(old, "_children")
			local index = table.find(list, self)
			if index then
				table.remove(list, index)
			end
		end
		rawset(self, "_parent", value)
		if value then
			table.insert(rawget(value, "_children"), self)
		end
	else
		rawset(self, key, value)
	end
end

NodeMeta.__tostring = function(self)
	return self.Name
end

function Methods.FindFirstChild(self, name)
	for _, child in rawget(self, "_children") do
		if child.Name == name then
			return child
		end
	end
	return nil
end
Methods.WaitForChild = Methods.FindFirstChild
function Methods.GetChildren(self)
	return table.clone(rawget(self, "_children"))
end
function Methods.GetDescendants(self)
	local out = {}
	local function walk(node)
		for _, child in rawget(node, "_children") do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end
function Methods.IsA(self, class)
	return self.ClassName == class or class == "Instance"
end
function Methods.Clone(self)
	local copy = newNode(self.Name, self.ClassName)
	rawset(copy, "_path", rawget(self, "_path"))
	return copy
end
function Methods.Destroy(self)
	self.Parent = nil
end
function Methods.GetFullName(self)
	return rawget(self, "_path") or self.Name
end
function Methods.GetAttribute(self, name)
	return rawget(self, "_attrs")[name]
end
function Methods.SetAttribute(self, name, value)
	rawget(self, "_attrs")[name] = value
end
function Methods.GetAttributeChangedSignal()
	return stubSignal()
end
function Methods.GetService(self, name)
	local service = Methods.FindFirstChild(self, name)
	if not service then
		service = newNode(name, name)
		service.Parent = self
	end
	return service
end
function Methods.GetPlayers()
	return {}
end
function Methods.IsServer()
	return true
end
function Methods.IsClient()
	return true -- comme le mode Édition de Studio : Net reste inerte
end
function Methods.IsStudio()
	return true
end
function Methods.IsRunning()
	return false
end
function Methods.BindToClose() end
function Methods.GetServerTimeNow()
	return os.clock()
end
local guid = 0
function Methods.GenerateGUID()
	guid += 1
	return string.format("00000000-0000-0000-0000-%012d", guid)
end

local function jsonEncode(value, out)
	local kind = type(value)
	if kind == "table" then
		local count = 0
		for _ in value do
			count += 1
		end
		if count > 0 and count == #value then
			table.insert(out, "[")
			for index, item in ipairs(value) do
				if index > 1 then
					table.insert(out, ",")
				end
				jsonEncode(item, out)
			end
			table.insert(out, "]")
		else
			table.insert(out, "{")
			local first = true
			for key, item in value do
				if not first then
					table.insert(out, ",")
				end
				first = false
				table.insert(out, string.format("%q:", tostring(key)))
				jsonEncode(item, out)
			end
			table.insert(out, "}")
		end
	elseif kind == "string" then
		table.insert(out, string.format("%q", value))
	elseif kind == "number" or kind == "boolean" then
		table.insert(out, tostring(value))
	elseif value == nil then
		table.insert(out, "null")
	else
		error("JSONEncode : type non sérialisable " .. kind)
	end
end
function Methods.JSONEncode(_self, value)
	local out = {}
	jsonEncode(value, out)
	return table.concat(out)
end

--------------------------------------------------------------------------------
-- Globales Roblox
--------------------------------------------------------------------------------
game = newNode("game", "DataModel")
rawset(game, "JobId", "local-job")
workspace = game:GetService("Workspace")
local players = game:GetService("Players")
rawset(players, "PlayerAdded", stubSignal())
rawset(players, "PlayerRemoving", stubSignal())
local runService = game:GetService("RunService")
rawset(runService, "Heartbeat", stubSignal())
rawset(runService, "Stepped", stubSignal())
rawset(runService, "PostSimulation", stubSignal())
rawset(runService, "PreSimulation", stubSignal())

Instance = {
	new = function(class, parent)
		local node = newNode(class, class)
		if parent then
			node.Parent = parent
		end
		return node
	end,
}

local EnumMeta = {}
EnumMeta.__index = function(self, key)
	local item = setmetatable({ Name = key }, EnumMeta)
	rawset(self, key, item)
	return item
end
EnumMeta.__tostring = function(self)
	return "Enum." .. tostring(rawget(self, "Name"))
end
Enum = setmetatable({}, EnumMeta)

task = {
	spawn = function(fn, ...)
		local thread = if type(fn) == "thread" then fn else coroutine.create(fn)
		local ok, err = coroutine.resume(thread, ...)
		if not ok then
			print("[essais] erreur dans une tâche : " .. tostring(err))
		end
		return thread
	end,
	delay = function()
		return coroutine.create(function() end)
	end,
	wait = function(seconds)
		return seconds or 0
	end,
	cancel = function(thread)
		pcall(coroutine.close, thread)
	end,
}
task.defer = task.spawn

Random = {
	new = function(seed)
		if seed then
			math.randomseed(seed)
		end
		local random = {}
		function random.NextNumber(_self, min, max)
			if min then
				return min + math.random() * (max - min)
			end
			return math.random()
		end
		function random.NextInteger(_self, min, max)
			return math.random(min, max)
		end
		function random.Clone(self)
			return self
		end
		return random
	end,
}

warn = function(...)
	-- Avertissements du jeu : silencieux par défaut pour garder la sortie des tests lisible.
	if __ESSAIS_VERBEUX then
		print("[warn]", ...)
	end
end

-- Vector3 (valeur immuable) --------------------------------------------------
local V3 = {}
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, _isVector3 = true }, V3)
end
V3.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif key == "Unit" then
		local m = self.Magnitude
		return v3(self.X / m, self.Y / m, self.Z / m)
	elseif key == "x" then
		return self.X
	elseif key == "y" then
		return self.Y
	elseif key == "z" then
		return self.Z
	end
	return V3[key]
end
V3.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(a)
	return string.format("%g, %g, %g", a.X, a.Y, a.Z)
end
function V3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3.Lerp(a, b, alpha)
	return a + (b - a) * alpha
end
function V3.FuzzyEq(a, b, epsilon)
	return (a - b).Magnitude <= (epsilon or 1e-5)
end
Vector3 = {
	new = v3,
	zero = v3(0, 0, 0),
	one = v3(1, 1, 1),
	xAxis = v3(1, 0, 0),
	yAxis = v3(0, 1, 0),
	zAxis = v3(0, 0, 1),
}

-- CFrame (position + matrice de rotation 3x3, lignes m11..m33) ------------------
local CF = {}
local function cf(px, py, pz, m11, m12, m13, m21, m22, m23, m31, m32, m33)
	return setmetatable({
		X = px, Y = py, Z = pz,
		m = { m11 or 1, m12 or 0, m13 or 0, m21 or 0, m22 or 1, m23 or 0, m31 or 0, m32 or 0, m33 or 1 },
		_isCFrame = true,
	}, CF)
end
local function rotate(m, x, y, z)
	return m[1] * x + m[2] * y + m[3] * z, m[4] * x + m[5] * y + m[6] * z, m[7] * x + m[8] * y + m[9] * z
end
local function mulRotation(a, b)
	local out = {}
	for row = 0, 2 do
		for col = 1, 3 do
			out[row * 3 + col] = a[row * 3 + 1] * b[col] + a[row * 3 + 2] * b[col + 3] + a[row * 3 + 3] * b[col + 6]
		end
	end
	return out
end
local function fromRotation(px, py, pz, m)
	return cf(px, py, pz, m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8], m[9])
end
local function rotX(a)
	local c, s = math.cos(a), math.sin(a)
	return { 1, 0, 0, 0, c, -s, 0, s, c }
end
local function rotY(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, 0, s, 0, 1, 0, -s, 0, c }
end
local function rotZ(a)
	local c, s = math.cos(a), math.sin(a)
	return { c, -s, 0, s, c, 0, 0, 0, 1 }
end
local function lookAt(eye, target, up)
	local look = (target - eye)
	if look.Magnitude < 1e-9 then
		return cf(eye.X, eye.Y, eye.Z)
	end
	look = look.Unit
	local right = look:Cross(up or v3(0, 1, 0))
	if right.Magnitude < 1e-9 then
		right = v3(1, 0, 0)
	end
	right = right.Unit
	local newUp = right:Cross(look)
	return cf(eye.X, eye.Y, eye.Z, right.X, newUp.X, -look.X, right.Y, newUp.Y, -look.Y, right.Z, newUp.Z, -look.Z)
end
CF.__index = function(self, key)
	local m = rawget(self, "m")
	if key == "Position" or key == "p" then
		return v3(self.X, self.Y, self.Z)
	elseif key == "LookVector" then
		return v3(-m[3], -m[6], -m[9])
	elseif key == "RightVector" or key == "XVector" then
		return v3(m[1], m[4], m[7])
	elseif key == "UpVector" or key == "YVector" then
		return v3(m[2], m[5], m[8])
	elseif key == "ZVector" then
		return v3(m[3], m[6], m[9])
	elseif key == "Rotation" then
		return fromRotation(0, 0, 0, m)
	end
	return CF[key]
end
CF.__mul = function(a, b)
	if rawget(b, "_isVector3") then
		local x, y, z = rotate(a.m, b.X, b.Y, b.Z)
		return v3(a.X + x, a.Y + y, a.Z + z)
	end
	local x, y, z = rotate(a.m, b.X, b.Y, b.Z)
	return fromRotation(a.X + x, a.Y + y, a.Z + z, mulRotation(a.m, b.m))
end
CF.__add = function(a, b)
	return fromRotation(a.X + b.X, a.Y + b.Y, a.Z + b.Z, a.m)
end
CF.__sub = function(a, b)
	return fromRotation(a.X - b.X, a.Y - b.Y, a.Z - b.Z, a.m)
end
CF.__eq = function(a, b)
	if a.X ~= b.X or a.Y ~= b.Y or a.Z ~= b.Z then
		return false
	end
	for index = 1, 9 do
		if a.m[index] ~= b.m[index] then
			return false
		end
	end
	return true
end
function CF.Inverse(self)
	local m = self.m
	local t = { m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] }
	local x, y, z = rotate(t, -self.X, -self.Y, -self.Z)
	return fromRotation(x, y, z, t)
end
function CF.ToWorldSpace(self, other)
	return self * other
end
function CF.ToObjectSpace(self, other)
	return self:Inverse() * other
end
function CF.PointToWorldSpace(self, point)
	return self * point
end
function CF.PointToObjectSpace(self, point)
	return self:Inverse() * point
end
function CF.VectorToWorldSpace(self, vector)
	return v3(rotate(self.m, vector.X, vector.Y, vector.Z))
end
function CF.VectorToObjectSpace(self, vector)
	local m = self.m
	return v3(rotate({ m[1], m[4], m[7], m[2], m[5], m[8], m[3], m[6], m[9] }, vector.X, vector.Y, vector.Z))
end
function CF.GetComponents(self)
	return self.X, self.Y, self.Z, table.unpack(self.m)
end
CF.components = CF.GetComponents
function CF.ToEulerAnglesYXZ(self)
	local m = self.m
	return math.asin(math.clamp(-m[6], -1, 1)), math.atan2(m[3], m[9]), math.atan2(m[4], m[5])
end
CF.ToOrientation = CF.ToEulerAnglesYXZ
function CF.ToEulerAnglesXYZ(self)
	local m = self.m
	return math.atan2(-m[6], m[9]), math.asin(math.clamp(m[3], -1, 1)), math.atan2(-m[2], m[1])
end
function CF.Lerp(self, goal, alpha)
	-- Approximation suffisante pour des tests : position interpolée, rotation de l'extrémité la plus proche.
	local source = if alpha < 0.5 then self else goal
	return fromRotation(self.X + (goal.X - self.X) * alpha, self.Y + (goal.Y - self.Y) * alpha, self.Z + (goal.Z - self.Z) * alpha, source.m)
end
CFrame = {
	new = function(a, b, c, ...)
		if a == nil then
			return cf(0, 0, 0)
		elseif type(a) == "number" then
			return cf(a, b, c, ...)
		elseif b ~= nil then
			return lookAt(a, b)
		end
		return cf(a.X, a.Y, a.Z)
	end,
	lookAt = lookAt,
	lookAlong = function(eye, direction, up)
		return lookAt(eye, eye + direction, up)
	end,
	Angles = function(rx, ry, rz)
		return fromRotation(0, 0, 0, mulRotation(mulRotation(rotX(rx), rotY(ry)), rotZ(rz)))
	end,
	fromEulerAnglesYXZ = function(rx, ry, rz)
		return fromRotation(0, 0, 0, mulRotation(mulRotation(rotY(ry), rotX(rx)), rotZ(rz)))
	end,
	fromMatrix = function(pos, vx, vy, vz)
		vz = vz or vx:Cross(vy).Unit
		return cf(pos.X, pos.Y, pos.Z, vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z)
	end,
	fromAxisAngle = function(axis, angle)
		local u = axis.Unit
		local c, s = math.cos(angle), math.sin(angle)
		local k = 1 - c
		return cf(0, 0, 0,
			c + u.X * u.X * k, u.X * u.Y * k - u.Z * s, u.X * u.Z * k + u.Y * s,
			u.Y * u.X * k + u.Z * s, c + u.Y * u.Y * k, u.Y * u.Z * k - u.X * s,
			u.Z * u.X * k - u.Y * s, u.Z * u.Y * k + u.X * s, c + u.Z * u.Z * k)
	end,
}
CFrame.fromEulerAnglesXYZ = CFrame.Angles
CFrame.fromOrientation = CFrame.fromEulerAnglesYXZ
CFrame.identity = cf(0, 0, 0)

Vector2 = {
	new = function(x, y)
		return { X = x or 0, Y = y or 0, _isVector2 = true }
	end,
}
Vector2.zero = Vector2.new(0, 0)
Vector2.one = Vector2.new(1, 1)

NumberRange = {
	new = function(min, max)
		return { Min = min, Max = max or min }
	end,
}

Color3 = {
	new = function(r, g, b)
		return { R = r or 0, G = g or 0, B = b or 0, _isColor3 = true }
	end,
	fromRGB = function(r, g, b)
		return { R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255, _isColor3 = true }
	end,
	fromHSV = function(h, s, v)
		return { R = v, G = v * (1 - s), B = h, _isColor3 = true }
	end,
}

typeof = function(value)
	if type(value) == "table" then
		if rawget(value, "_isInstance") then
			return "Instance"
		elseif rawget(value, "_isVector3") then
			return "Vector3"
		elseif rawget(value, "_isCFrame") then
			return "CFrame"
		elseif rawget(value, "_isVector2") then
			return "Vector2"
		elseif rawget(value, "_isColor3") then
			return "Color3"
		elseif getmetatable(value) == EnumMeta then
			return "EnumItem"
		end
	end
	return __typeof(value)
end

--------------------------------------------------------------------------------
-- Arbre des modules et require
--------------------------------------------------------------------------------
local function ensurePath(path)
	local node = game
	for _, name in string.split(path, "/") do
		local child = Methods.FindFirstChild(node, name)
		if not child then
			child = newNode(name, if node == game then name else "Folder")
			child.Parent = node
		end
		node = child
	end
	return node
end

local function __register(path, loader)
	__M[path] = loader
	local node = ensurePath(path)
	rawset(node, "ClassName", "ModuleScript")
	rawset(node, "_path", path)
end

local loaded = {}
require = function(node)
	if type(node) ~= "table" or not rawget(node, "_path") then
		error("require : module introuvable (" .. tostring(node) .. ")", 2)
	end
	local state = loaded[node]
	if state then
		if state.loading then
			error("require récursif : " .. rawget(node, "_path"), 2)
		end
		return state.result
	end
	state = { loading = true }
	loaded[node] = state
	local ok, result = pcall(__M[rawget(node, "_path")], node)
	if not ok then
		loaded[node] = nil
		error(result, 0)
	end
	state.loading = false
	state.result = result
	return result
end
