--[[
	Workers — specialties, wages (paid every Economy.Wages.PaySeconds) and what they automate.
	Workers need a suitable station (store type in Stores[*].Workers) and available stock.
]]
return {
	Cashier = {
		Name = "Cashier",
		Wage = 18,
		Benefit = "Serves customers at the counter while you are away.",
		Tip = "Hiring a cashier costs wages, but customers get served while you explore.",
		ServeSeconds = 3.5,
		Shirt = Color3.fromRGB(64, 170, 160),
	},
	Stocker = {
		Name = "Stocker",
		Wage = 14,
		Benefit = "Carries delivered boxes to the shelves.",
		Tip = "Hiring a stocker costs wages, but keeps shelves available while you explore.",
		RestockSeconds = 7,
		Shirt = Color3.fromRGB(240, 120, 110),
	},
	Cook = {
		Name = "Cook",
		Wage = 22,
		Benefit = "Assembles food orders automatically.",
		Tip = "A cook prepares orders on their own, so the kiosk earns while you manage other stores.",
		AssembleSeconds = 4.5,
		Shirt = Color3.fromRGB(250, 250, 250),
	},
	Technician = {
		Name = "Technician",
		Wage = 28,
		Benefit = "Repairs arcade machines and runs electronics demos.",
		Tip = "Technicians keep machines running; a broken machine earns nothing.",
		RepairSeconds = 6,
		Shirt = Color3.fromRGB(80, 120, 220),
	},
	Manager = {
		Name = "Manager",
		Wage = 40,
		Benefit = "Runs a finished mall for you: modest net income while you build the next one.",
		Tip = "Assign a manager to a mall you have outgrown. It keeps earning a little, without you.",
		Shirt = Color3.fromRGB(40, 120, 110),
	},
}
