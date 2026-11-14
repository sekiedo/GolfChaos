--!strict
-- Shop and customisation (English). Keys prefixed "shop.".
-- shop.err.* keys are returned by CosmeticService (Shop.Result remote): one per refusal reason.
return {
	["shop.err.profile"] = "Profile unavailable: try again in a moment",
	["shop.err.unknown"] = "This item does not exist",
	["shop.err.owned"] = "You already own this item",
	["shop.err.notOwned"] = "You do not own this item",
	["shop.err.coins"] = "Not enough coins",
	["shop.err.locked"] = "Item locked: meet its requirement to unlock it",
	["shop.err.slot"] = "Unknown slot",
	["shop.err.variant"] = "This colour does not exist for this item",
	["shop.err.emotesFull"] = "All your emote slots are taken: remove one first",
	["shop.err.loadout"] = "This outfit set does not exist",
	["shop.err.emptyLoadout"] = "This outfit set is empty: save an outfit first",
}
