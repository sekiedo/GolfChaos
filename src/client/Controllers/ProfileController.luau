--!strict
--[[
	ProfileController — copie locale (lecture seule) du profil du joueur, alimentée par Data.Sync, et envoi des
	intentions de boutique au serveur. Le client ne modifie jamais le profil : il demande, le serveur décide et
	répond par Shop.Result ; l'instantané suivant (Data.Sync) met l'interface à jour.

	  ProfileController.Get() -> Snapshot             dernière vue connue (tables vides avant le premier Data.Sync)
	  ProfileController.IsLoaded() -> boolean         un Data.Sync a été reçu
	  ProfileController.GetCoins() -> number
	  ProfileController.Changed                       Signal(snapshot) à chaque Data.Sync
	  ProfileController.ResultReceived                Signal(action, ok, reasonKey?, payload?) = Shop.Result
	  ProfileController.Buy(id) / Equip(slot, id?) / SetVariant(id, index) / SaveLoadout(n) / UseLoadout(n)
	  ProfileController.PlayEmote(id) / StopEmote()   Emote.Play / Emote.Stop
	  ProfileController.RequestSync()                 Data.RequestSync (limité par le réseau)

	Un instantané partiel ne remplace que les clés présentes. Les messages sont journalisés si le remote manque.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)

local ProfileController = {}
ProfileController.Priority = 8

ProfileController.Changed = Signal.new()
ProfileController.ResultReceived = Signal.new()

local snapshot: { [string]: any } = {
	coins = 0,
	owned = {},
	equipped = {},
	variants = {},
	loadouts = {},
	achievements = {},
	stats = {},
	sets = {},
	events = {},
	settings = {},
}
local loaded = false

local function send(name: string, ...: any)
	if not Net.getDefinitions()[name] then
		Log.warn("Profile", "remote absent :", name)
		return
	end
	local ok, err = pcall(Net.send, name, ...)
	if not ok then
		Log.warn("Profile", "envoi impossible :", name, err)
	end
end

function ProfileController.Get(): { [string]: any }
	return snapshot
end

function ProfileController.IsLoaded(): boolean
	return loaded
end

function ProfileController.GetCoins(): number
	local coins = snapshot.coins
	return if type(coins) == "number" then coins else 0
end

function ProfileController.Buy(id: string)
	send("Shop.Buy", id)
end

function ProfileController.Equip(slot: string, id: string?)
	send("Shop.Equip", slot, id)
end

function ProfileController.SetVariant(id: string, index: number)
	send("Shop.SetVariant", id, math.floor(index))
end

function ProfileController.SaveLoadout(index: number)
	send("Shop.SaveLoadout", math.floor(index))
end

function ProfileController.UseLoadout(index: number)
	send("Shop.UseLoadout", math.floor(index))
end

function ProfileController.PlayEmote(id: string)
	send("Emote.Play", id)
end

function ProfileController.StopEmote()
	send("Emote.Stop")
end

function ProfileController.RequestSync()
	send("Data.RequestSync")
end

local function onSync(payload: any)
	if type(payload) ~= "table" then
		return
	end
	for key, value in payload :: { [string]: any } do
		snapshot[key] = value
	end
	loaded = true
	ProfileController.Changed:Fire(snapshot)
end

local function onResult(action: any, ok: any, reasonKey: any, payload: any)
	if type(action) ~= "string" then
		return
	end
	ProfileController.ResultReceived:Fire(
		action,
		ok == true,
		if type(reasonKey) == "string" then reasonKey else nil,
		if type(payload) == "table" then payload else nil
	)
end

function ProfileController.Start()
	Net.listen("Data.Sync", onSync)
	Net.listen("Shop.Result", onResult)
	ProfileController.RequestSync()
end

return ProfileController
