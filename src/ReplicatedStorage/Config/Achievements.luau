--[[
	Achievements. Each one can also award a Roblox badge: create the badge on Creator Hub
	(Shoprise ▸ Engagement ▸ Badges), then paste its id into BadgeId. BadgeId = 0 means in-game only.
	Stat paths read the saved profile (see AchievementService for the special checks).
]]
return {
	{ Id = "Welcome", Name = "Grand Opening", Icon = "🎉", Desc = "Join Shoprise and get your first shop.", Check = "Always", BadgeId = 327334513378892 },
	{ Id = "FirstSale", Name = "First Customer", Icon = "🧾", Desc = "Serve your first customer.", Stat = "Stats.CustomersServed", Goal = 1, BadgeId = 162787550783178 },
	{ Id = "Served100", Name = "Regulars", Icon = "🛒", Desc = "Serve 100 customers.", Stat = "Stats.CustomersServed", Goal = 100, BadgeId = 1890283646031122 },
	{ Id = "Served1000", Name = "Crowd Favourite", Icon = "🏆", Desc = "Serve 1,000 customers.", Stat = "Stats.CustomersServed", Goal = 1000, BadgeId = 2565512474796555 },
	{ Id = "Revenue1K", Name = "Small Business", Icon = "💵", Desc = "Earn $1,000 in lifetime sales.", Stat = "Stats.LifetimeRevenue", Goal = 1000, BadgeId = 810313009306035 },
	{ Id = "Revenue10K", Name = "Entrepreneur", Icon = "💰", Desc = "Earn $10,000 in lifetime sales.", Stat = "Stats.LifetimeRevenue", Goal = 10000, BadgeId = 0 },
	{ Id = "Revenue100K", Name = "Mall Mogul", Icon = "👑", Desc = "Earn $100,000 in lifetime sales.", Stat = "Stats.LifetimeRevenue", Goal = 100000, BadgeId = 0 },
	{ Id = "Savings", Name = "Rainy Day Fund", Icon = "🏦", Desc = "Have $5,000 in cash at once.", Stat = "Cash", Goal = 5000, BadgeId = 0 },
	{ Id = "FirstHire", Name = "Team Player", Icon = "🤝", Desc = "Hire your first worker.", Check = "Workers", Goal = 1, BadgeId = 0 },
	{ Id = "FullTeam", Name = "Dream Team", Icon = "🧑‍🍳", Desc = "Have 3 workers.", Check = "Workers", Goal = 3, BadgeId = 0 },
	{ Id = "ThreeStores", Name = "Chain Store", Icon = "🏬", Desc = "Run 3 stores at the same time.", Check = "Stores", Goal = 3, BadgeId = 0 },
	{ Id = "Elevator", Name = "Going Up!", Icon = "🛗", Desc = "Help restore the Neighborhood Mall elevator.", Check = "Project", Mall = 1, BadgeId = 0 },
	{ Id = "Downtown", Name = "Moving Downtown", Icon = "🌆", Desc = "Unlock the Downtown Mall.", Check = "Mall", Mall = 2, BadgeId = 0 },
	{ Id = "Helper", Name = "Good Neighbour", Icon = "💛", Desc = "Earn $100 in assist bonuses by helping other players' stores.", Stat = "Stats.AssistEarned", Goal = 100, BadgeId = 0 },
	{ Id = "Baskets", Name = "Tidy Mall", Icon = "🧺", Desc = "Return 25 stray baskets.", Stat = "Stats.BasketsReturned", Goal = 25, BadgeId = 0 },
}
