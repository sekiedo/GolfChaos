--!strict
--[[
	Trove : tout ce qui doit être nettoyé au même moment (fin de trou, déconnexion, fin d'effet...).

	  local trove = Trove.new()
	  trove:Add(instance)                         -- :Destroy()
	  trove:Add(connection)                       -- :Disconnect()
	  trove:Add(function() ... end)               -- appelée
	  trove:Add(task.delay(3, fn))                -- thread annulé (task.cancel)
	  trove:Add(objetAvecDestroy)                 -- :Destroy() / :Disconnect() / :Clean()
	  trove:Connect(signal, fn)                   -- raccourci
	  local enfant = trove:Extend()               -- sous-trove nettoyée avec la parente
	  trove:Remove(objet)                         -- retire sans nettoyer
	  trove:Clean()                               -- nettoie tout (ordre inverse d'ajout) ; réutilisable
	  trove:Destroy()                             -- alias de Clean
	  trove:Count()                               -- nombre d'éléments suivis (tests de fuite)
]]

export type Trove = {
	Add: <T>(self: Trove, item: T) -> T,
	Connect: (self: Trove, signal: any, callback: (...any) -> ()) -> any,
	Extend: (self: Trove) -> Trove,
	Remove: (self: Trove, item: any) -> (),
	Clean: (self: Trove) -> (),
	Destroy: (self: Trove) -> (),
	Count: (self: Trove) -> number,
}

local function cleanItem(item: any)
	local kind = typeof(item)
	if kind == "Instance" then
		item:Destroy()
	elseif kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		if coroutine.status(item) ~= "dead" and item ~= coroutine.running() then
			pcall(task.cancel, item)
		end
	elseif kind == "table" then
		if typeof(item.Destroy) == "function" then
			item:Destroy()
		elseif typeof(item.Disconnect) == "function" then
			item:Disconnect()
		elseif typeof(item.Clean) == "function" then
			item:Clean()
		end
	end
end

local TroveMethods = {}
TroveMethods.__index = TroveMethods

local Trove = {}

function Trove.new(): Trove
	local self = setmetatable({ _items = {}, _cleaning = false }, TroveMethods)
	return (self :: any) :: Trove
end

function TroveMethods.Add(self: any, item: any): any
	if self._cleaning then
		-- Ajout pendant un nettoyage : on nettoie immédiatement pour ne rien laisser fuir.
		task.defer(cleanItem, item)
		return item
	end
	table.insert(self._items, item)
	return item
end

function TroveMethods.Connect(self: any, signal: any, callback: (...any) -> ()): any
	return TroveMethods.Add(self, signal:Connect(callback))
end

function TroveMethods.Extend(self: any): Trove
	local child = Trove.new()
	TroveMethods.Add(self, child)
	return child
end

function TroveMethods.Remove(self: any, item: any)
	local index = table.find(self._items, item)
	if index then
		table.remove(self._items, index)
	end
end

function TroveMethods.Clean(self: any)
	if self._cleaning then
		return
	end
	self._cleaning = true
	local items = self._items
	self._items = {}
	for index = #items, 1, -1 do
		local ok, err = pcall(cleanItem, items[index])
		if not ok then
			warn("[Trove] erreur pendant le nettoyage :", err)
		end
	end
	self._cleaning = false
end

function TroveMethods.Destroy(self: any)
	TroveMethods.Clean(self)
end

function TroveMethods.Count(self: any): number
	return #self._items
end

return Trove
