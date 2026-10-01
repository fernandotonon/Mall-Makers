--[[
	Stores — one entry per store type. Interaction kinds:
	  Restock  : carry stock boxes from the delivery point to shelves, serve at the counter (Convenience)
	  Match    : customer shows a symbol, pick the matching display item (Clothing)
	  Assemble : customer orders 1-3 items, tap the stations in any order, serve (FoodKiosk)
	  MatchDemo: pick the product category, optional demo hold for a bonus (Electronics, Mall 2)
	  Repair   : arcade machines break, repeat a 3-step icon sequence to fix them (Arcade, Mall 2)
	Money: UnitCost is what a unit of stock costs you, UnitPrice what a customer pays.
]]
return {
	Convenience = {
		Name = "Convenience Store",
		Color = Color3.fromRGB(64, 170, 160),
		Interaction = "Restock",
		Product = "Groceries",
		ProductIcon = "🥛",
		UnitCost = 3,
		UnitPrice = 8,
		BoxUnits = 8,
		DeliverySeconds = 6,
		MaxPendingBoxes = 4,
		Shelves = 2,
		ShelfCapacity = 16,
		ItemsPerCustomer = { 1, 3 },
		Upgrades = {
			{ Id = "ExtraShelf", Name = "Extra shelf", Cost = 220, Desc = "+1 shelf: more stock on display, more customers browse at once." },
			{ Id = "BiggerBoxes", Name = "Bigger boxes", Cost = 350, Desc = "Each delivery box holds 12 units instead of 8." },
			{ Id = "Decor", Name = "Nice decor", Cost = 300, Desc = "Customers wait longer and pay a little more." },
		},
		Workers = { "Cashier", "Stocker" },
	},
	Clothing = {
		Name = "Clothing Shop",
		Color = Color3.fromRGB(240, 120, 110),
		Interaction = "Match",
		Product = "Outfits",
		ProductIcon = "👕",
		Symbols = { "Star", "Heart", "Bolt" },
		UnitCost = 12,
		UnitPrice = 32,
		BoxUnits = 6,
		DeliverySeconds = 8,
		MaxPendingBoxes = 3,
		Shelves = 1, -- the rack
		ShelfCapacity = 12,
		ItemsPerCustomer = { 1, 1 },
		Upgrades = {
			{ Id = "Display", Name = "Display table", Cost = 420, Desc = "A second display: two customers can be helped at once." },
			{ Id = "Decor", Name = "Boutique lighting", Cost = 380, Desc = "Customers wait longer and pay a little more." },
		},
		Workers = { "Cashier", "Stocker" },
	},
	FoodKiosk = {
		Name = "Food Kiosk",
		Color = Color3.fromRGB(250, 170, 60),
		Interaction = "Assemble",
		Product = "Meals",
		ProductIcon = "🍔",
		Ingredients = { "Burger", "Fries", "Drink" },
		UnitCost = 4,
		UnitPrice = 14, -- per item in the order
		BoxUnits = 10, -- ingredients per supply box
		DeliverySeconds = 7,
		MaxPendingBoxes = 3,
		Shelves = 1, -- the pantry
		ShelfCapacity = 20,
		ItemsPerCustomer = { 1, 3 },
		Upgrades = {
			{ Id = "SecondGriddle", Name = "Second griddle", Cost = 500, Desc = "Orders are assembled faster by cooks." },
			{ Id = "Decor", Name = "Seating area", Cost = 450, Desc = "Customers wait longer and pay a little more." },
		},
		Workers = { "Cook", "Stocker" },
	},
	Electronics = {
		Name = "Electronics Shop",
		Color = Color3.fromRGB(80, 120, 220),
		Interaction = "MatchDemo",
		Product = "Gadgets",
		ProductIcon = "💻",
		Categories = { "Laptop", "Phone", "Headphones" },
		UnitCost = 55,
		UnitPrice = 140,
		DemoBonus = 45,
		BoxUnits = 4,
		DeliverySeconds = 10,
		MaxPendingBoxes = 3,
		Shelves = 1,
		ShelfCapacity = 8,
		ItemsPerCustomer = { 1, 1 },
		Upgrades = {
			{ Id = "DemoBench", Name = "Demo bench", Cost = 1800, Desc = "Demos pay double." },
			{ Id = "Decor", Name = "Showroom lights", Cost = 1500, Desc = "Customers wait longer and pay a little more." },
		},
		Workers = { "Cashier", "Technician", "Stocker" },
	},
	Arcade = {
		Name = "Arcade",
		Color = Color3.fromRGB(170, 90, 220),
		Interaction = "Repair",
		Product = "Plays",
		ProductIcon = "🕹️",
		Machines = 4,
		PlayPrice = 9,
		BreakChancePerPlay = 0.22,
		RepairSteps = { "Wrench", "Plug", "Chip" },
		UnitCost = 0,
		UnitPrice = 9,
		BoxUnits = 0,
		Shelves = 0,
		ShelfCapacity = 0,
		ItemsPerCustomer = { 1, 2 },
		Upgrades = {
			{ Id = "MoreMachines", Name = "Two more machines", Cost = 2500, Desc = "+2 arcade machines." },
			{ Id = "Decor", Name = "Neon signs", Cost = 1600, Desc = "Customers wait longer and pay a little more." },
		},
		Workers = { "Technician" },
	},
}
