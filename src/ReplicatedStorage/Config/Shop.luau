--[[
	Robux shop and session rewards. Everything sold is cosmetic or fun; nothing sold gives cash,
	stores or project progress.
	Create the passes / product on Creator Hub (Shoprise ▸ Monetization) with the suggested prices and
	paste their ids here. Id = 0 hides the buy button (in Studio a "test" button grants it instead).
]]
return {
	GamePasses = {
		VIP = { Id = 2006438595, Price = 25, Name = "VIP", Icon = "⭐", Desc = "Gold VIP name tag above your character and the gold storefront colour." },
		StylePack = { Id = 2007026607, Price = 15, Name = "Style Pack", Icon = "🎨", Desc = "Five extra storefront colours and a glowing neon sign." },
	},
	Products = {
		MallRush = { Id = 3716110864, Price = 1, Name = "Mall Rush", Icon = "⚡", Minutes = 10, Desc = "10 minutes of extra customers for every store in this server. Everyone gets thanked by your name!" },
	},
	-- storefront sign colours: index -> colour; Requires = pass id needed
	Accents = {
		{ Name = "Teal", Color = Color3.fromRGB(64, 150, 150) },
		{ Name = "Coral", Color = Color3.fromRGB(240, 120, 100) },
		{ Name = "Lavender", Color = Color3.fromRGB(140, 110, 200) },
		{ Name = "Orange", Color = Color3.fromRGB(250, 170, 60) },
		{ Name = "Green", Color = Color3.fromRGB(90, 180, 90) },
		{ Name = "Hot pink", Color = Color3.fromRGB(240, 80, 170), Requires = "StylePack" },
		{ Name = "Sky", Color = Color3.fromRGB(80, 170, 240), Requires = "StylePack" },
		{ Name = "Lime", Color = Color3.fromRGB(170, 230, 60), Requires = "StylePack" },
		{ Name = "Crimson", Color = Color3.fromRGB(200, 40, 60), Requires = "StylePack" },
		{ Name = "Midnight", Color = Color3.fromRGB(40, 45, 90), Requires = "StylePack" },
		{ Name = "Gold", Color = Color3.fromRGB(240, 190, 50), Requires = "VIP" },
	},
	-- free rewards for minutes played in the current session (claimed in Menu ▸ Shop)
	SessionRewards = {
		{ Minutes = 5, Kind = "Cash", Amount = 100, Text = "$100" },
		{ Minutes = 15, Kind = "Express", Minutes2 = 10, Text = "10 min Express Delivery" },
		{ Minutes = 30, Kind = "Rush", Minutes2 = 10, Text = "10 min Rush in your stores" },
		{ Minutes = 45, Kind = "Cash", Amount = 400, Text = "$400" },
		{ Minutes = 60, Kind = "Express", Minutes2 = 20, Text = "20 min Express Delivery" },
		{ Minutes = 90, Kind = "Rush", Minutes2 = 20, Text = "20 min Rush in your stores" },
	},
	ExpressDeliverySeconds = 1, -- delivery time while Express Delivery is active
}
