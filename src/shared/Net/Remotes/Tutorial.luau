--!strict
--[[
	Remotes du tutoriel par points lumineux (TutorialController -> TutorialService).
	Le client signale seulement la fin (ou le saut) du tutoriel ; le serveur pose profile.tutorialDone.
]]
return {
	["Tutorial.Complete"] = { kind = "Event", dir = "ToServer", args = {}, rate = 1, burst = 2 },
}
