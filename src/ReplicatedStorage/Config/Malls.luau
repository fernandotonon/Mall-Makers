--[[
	Malls — economic tiers. Each mall has the same floor layout family (see MallService) but its own
	lots, prices, project, worker discoveries and the milestones needed to open the next mall.
	Discovery kinds: LostDelivery (bring the misplaced box back), RestorePower (fix the generator),
	Trial (serve N customers in a newly bought store), Specialist (found in the unlocked area).
]]
return {
	{
		Id = 1,
		Name = "Neighborhood Mall",
		Origin = Vector3.new(0, 0, 0),
		Floors = 4,
		PriceMultiplier = 1,
		Lots = {
			{ Id = "A", Store = "Convenience", Cost = 0, Starter = true, Pos = Vector3.new(-55, 0, -35) },
			{ Id = "B", Store = "Clothing", Cost = 650, Pos = Vector3.new(0, 0, -35) },
			{ Id = "C", Store = "FoodKiosk", Cost = 1300, Pos = Vector3.new(55, 0, -35) },
		},
		Project = {
			Id = "Elevator",
			Name = "Restore the elevator",
			Desc = "The atrium elevator is out of order. Fund the repair to ride between floors instantly.",
			Cost = 1600,
			Step = 100,
			CompleteText = "The elevator is running again! Everyone celebrates.",
		},
		Discoveries = {
			{ Id = "LostDelivery", Kind = "LostDelivery", Worker = "Stocker", Pos = Vector3.new(-70, 0, 38), BoxPos = Vector3.new(62, 0, -14),
				Text = "A courier lost a box somewhere on this floor. Bring it back to meet a stocker." },
			{ Id = "StaffRoom", Kind = "RestorePower", Worker = "Cashier", Pos = Vector3.new(70, 0, 40),
				Text = "The staff room is dark. Restart the generator to find a cashier." },
			{ Id = "KioskTrial", Kind = "Trial", Worker = "Cook", RequiresLot = "C", Serves = 3, Pos = Vector3.new(55, 0, -16),
				Text = "A cook offers a trial: serve 3 kiosk orders yourself and they join you." },
		},
		UnlockNext = {
			Milestones = {
				{ Id = "OwnAllLots", Text = "Open all 3 stores" },
				{ Id = "Workers2", Text = "Hire 2 workers", Count = 2 },
				{ Id = "ProjectDone", Text = "Restore the elevator" },
				{ Id = "Revenue", Text = "Earn $4,000 in sales", Amount = 4000 },
			},
			OpeningCost = 2000,
			Text = "Downtown Mall opening project",
		},
	},
	{
		Id = 2,
		Name = "Downtown Mall",
		Origin = Vector3.new(700, 0, 0),
		Floors = 4,
		PriceMultiplier = 2.5,
		Logistics = {
			-- Mall 2 mechanic: deliveries arrive at the loading dock, boxes go to the stockroom first,
			-- and stores can only be restocked from the stockroom.
			StockroomCapacity = 10,
			StockroomUpgrade = { Cost = 1200, Capacity = 20 },
			DeliveryBoxes = 5,
			DeliveryCostPerBox = 60, -- generic supplies; a box becomes the store's product on restock
			DeliverySeconds = 14,
			DockPos = Vector3.new(-70, 0, 40),
			StockroomPos = Vector3.new(-40, 0, 40),
		},
		Lots = {
			{ Id = "A", Store = "Electronics", Cost = 2800, Pos = Vector3.new(-35, 0, -35) },
			{ Id = "B", Store = "Arcade", Cost = 4200, Pos = Vector3.new(35, 0, -35) },
		},
		Project = {
			Id = "LoadingDock",
			Name = "Expand the loading dock",
			Desc = "A bigger dock lets deliveries bring 8 boxes at once for everyone on this mall.",
			Cost = 6000,
			Step = 250,
			CompleteText = "The loading dock is open! Deliveries now bring 8 boxes.",
			DeliveryBoxes = 8,
		},
		Discoveries = {
			{ Id = "DockTech", Kind = "LostDelivery", Worker = "Technician", Pos = Vector3.new(-70, 0, 20), BoxPos = Vector3.new(62, 0, -14),
				Text = "A technician misplaced a parts box near the dock. Find it to recruit them." },
			{ Id = "Office", Kind = "RestorePower", Worker = "Manager", Pos = Vector3.new(70, 0, 40),
				Text = "The management office has no power. Fix it to meet a manager." },
		},
		UnlockNext = nil,
	},
}
