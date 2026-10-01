--[[
	Economy — every balancing number that is not store- or mall-specific.
	All money is one cash currency. Tune here, never in gameplay scripts.
]]
return {
	StartingCash = 250,

	Save = {
		StoreName = "Shoprise_v1",
		DevPrefix = "Dev_", -- Studio (and DevMode) saves go to "Dev_Shoprise_v1" so production saves are never touched
		DevMode = false, -- force dev saves outside Studio (e.g. a private test place)
		AutosaveSeconds = 60,
		SessionLockSeconds = 180, -- a lock older than this is considered stale (crashed server)
		LoadRetries = 3,
	},

	Wages = {
		PaySeconds = 60, -- wages are paid once per this interval ("per minute")
	},

	Assist = {
		RewardPerAction = 6, -- paid to a helper, not deducted from the owner
		MaxRewardsPerMinute = 8, -- hard cap per helper
		SameActionCooldown = 4, -- seconds before the same helper is rewarded for the same object again
	},

	Recovery = {
		BasketReward = 5, -- cash for returning a stray basket (manual earning, never blocked)
		BasketsPerFloor = 3,
		BasketRespawnSeconds = 25,
	},

	Rush = {
		FirstAfterSeconds = 180,
		IntervalSeconds = 300,
		DurationSeconds = 45,
		SpawnMultiplier = 2.2,
		AnnounceText = "Shopping rush! Customers are pouring in.",
	},

	Customers = {
		MaxPerServer = 18,
		MaxPerStore = 3,
		SpawnIntervalSeconds = 7, -- base time between customers for one store
		MinSpawnIntervalSeconds = 3,
		BrowseSeconds = 2.5,
		PatienceSeconds = 28, -- time a customer waits at the counter / for a request
		LeaveAngrySatisfactionHit = 8,
		ServedSatisfactionGain = 1.5,
		EmptyShelfSatisfactionHit = 4,
	},

	Simulation = {
		-- stores on floors whose owner is in another mall (or has no visitors) sell economically:
		InactiveSaleRate = 0.3, -- fraction of a normal cashier's throughput
		TickSeconds = 10,
	},

	PreviousMall = {
		-- Income from a completed mall once a manager is assigned (online only for the MVP).
		-- Target: about 10-20% of the next mall's first expansion cost in ~10 minutes.
		-- The manager's own wage is paid by the normal wage tick (Workers.Manager.Wage), so the net is
		-- roughly stores * IncomePerMinutePerStore - 40. Three staffed stores: ~50/min net -> ~500 in
		-- 10 minutes = 18% of the Downtown Electronics lease (2800).
		IncomePerMinutePerStore = 30, -- gross, after simulated operating costs
		RequiresWorkerPerStore = true, -- only stores that still have a (paid) worker produce
	},

	Satisfaction = {
		Start = 80,
		Min = 0,
		Max = 100,
		PriceBonusAt100 = 0.25, -- +25% sale value at 100% satisfaction, linear from 0
	},

	WorkerLevels = {
		{ Tasks = 0, Speed = 1.0, Label = "Trainee" },
		{ Tasks = 15, Speed = 1.25, Label = "Skilled" },
		{ Tasks = 50, Speed = 1.5, Label = "Expert" },
	},

	MoneyPopDurationSeconds = 1.2,
}
