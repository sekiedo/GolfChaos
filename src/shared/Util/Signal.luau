--!strict
--[[
	Signal : communication entre modules sans BindableEvent ni _G.

	  local Signal = require(ReplicatedStorage.Shared.Util.Signal)
	  local changed = Signal.new()
	  local connection = changed:Connect(function(a, b) ... end)
	  changed:Fire(a, b)            -- chaque écouteur s'exécute dans son propre thread (task.spawn) :
	                                -- une erreur dans un écouteur n'interrompt pas les autres.
	  connection:Disconnect()
	  changed:Once(fn)  /  changed:Wait()  /  changed:DisconnectAll()  /  changed:Destroy()
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, callback: (...any) -> ()) -> Connection,
	Once: (self: Signal, callback: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	Wait: (self: Signal) -> ...any,
	DisconnectAll: (self: Signal) -> (),
	Destroy: (self: Signal) -> (),
	GetConnectionCount: (self: Signal) -> number,
}

local ConnectionMethods = {}
ConnectionMethods.__index = ConnectionMethods

function ConnectionMethods.Disconnect(self: any)
	if not self.Connected then
		return
	end
	self.Connected = false
	local handlers = self._signal._handlers
	local index = table.find(handlers, self)
	if index then
		table.remove(handlers, index)
	end
end

local SignalMethods = {}
SignalMethods.__index = SignalMethods

local Signal = {}

function Signal.new(): Signal
	local self = setmetatable({ _handlers = {} }, SignalMethods)
	return (self :: any) :: Signal
end

function SignalMethods.Connect(self: any, callback: (...any) -> ()): Connection
	local connection = setmetatable({
		Connected = true,
		_signal = self,
		_callback = callback,
	}, ConnectionMethods)
	table.insert(self._handlers, connection)
	return (connection :: any) :: Connection
end

function SignalMethods.Once(self: any, callback: (...any) -> ()): Connection
	local connection: Connection
	connection = SignalMethods.Connect(self, function(...)
		connection:Disconnect()
		callback(...)
	end)
	return connection
end

function SignalMethods.Fire(self: any, ...: any)
	-- Copie : un écouteur peut se déconnecter (ou en connecter un autre) pendant l'itération.
	local handlers = table.clone(self._handlers)
	for _, connection in handlers do
		if connection.Connected then
			task.spawn(connection._callback, ...)
		end
	end
end

function SignalMethods.Wait(self: any): ...any
	local thread = coroutine.running()
	SignalMethods.Once(self, function(...)
		task.spawn(thread, ...)
	end)
	return coroutine.yield()
end

function SignalMethods.DisconnectAll(self: any)
	for _, connection in self._handlers do
		connection.Connected = false
	end
	table.clear(self._handlers)
end

function SignalMethods.Destroy(self: any)
	SignalMethods.DisconnectAll(self)
end

function SignalMethods.GetConnectionCount(self: any): number
	return #self._handlers
end

return Signal
