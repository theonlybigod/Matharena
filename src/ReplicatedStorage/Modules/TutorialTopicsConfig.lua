--[[
	TutorialTopicsConfig.lua

	The seven tutorial topics, in order.

	WHY THIS IS A SHARED MODULE. This table used to be a `local TOPICS`
	inside TutorialUIController. There are now TWO surfaces that present the
	same tutorial content:

		1. The tutorial overlay opened by the bottom-bar button
		   (TutorialUIController).
		2. The wall screen inside the Tutorial building, which players sit
		   down in front of (TutorialScreenController).

	Duplicating the text into the second one would mean every future wording
	change has to be made twice, and the two would silently drift apart. So
	the content lives here and both surfaces require it.

	Lives in ReplicatedStorage/Modules because both consumers are CLIENTS -
	unlike LeaderboardConfig, which sits in ServerScriptService precisely
	because all of its consumers are server-side.

	`title` is the heading shown on the topic's tab/header; `body` is the
	prose beneath it. Order here is the order presented in both surfaces.
]]

local TutorialTopicsConfig = {}

TutorialTopicsConfig.TOPICS = {
	{
		title = "How to Play",
		body = "MathArena is a competitive math game show. Join a match, answer questions faster and more "
			.. "accurately than your opponents, and be the last one standing to win Coins, XP, and Gems.",
	},
	{
		title = "How Matchmaking Works",
		body = "Click PLAY to pick a difficulty and queue up directly - no need to walk anywhere first. A match "
			.. "needs at least 2 players and holds up to 12 - once enough players are queued, a countdown begins "
			.. "and you're teleported to the arena.",
	},
	{
		title = "How Questions Work",
		body = "Questions get progressively harder as a match goes on, from basic arithmetic to fractions, "
			.. "percentages, and beyond. Each question has a time limit based on its difficulty - answer "
			.. "correctly before time runs out, or you're eliminated.",
	},
	{
		title = "Practice Mode",
		body = "Practice Mode lets you answer the same kinds of questions with no elimination to lose over. "
			.. "Click the PRACTICE button in the lobby any time and choose Regular Practice or Extra Time Mode "
			.. "(2x-5x time per question, or Infinite Time) - it doesn't count as a competitive match and won't "
			.. "affect your Wins or leaderboard standing.",
	},
	{
		title = "Quests",
		body = "Your Quest Log sits on the left edge of the screen - open it any time to see your current quests. "
			.. "Quests are entirely manual: you choose when to Accept one, Refresh a standard quest for a "
			.. "different one (up to 3 times a day), Cancel one you've accepted, or Claim a completed one. "
			.. "Nothing is ever accepted for you automatically. Quests unlock once you finish this tutorial.",
	},
	{
		title = "Rewards & XP",
		body = "Winning and playing matches earns Coins, XP, and Gems. Spend Coins and Gems in the Shop on "
			.. "cosmetics, and check the Rewards track and Daily Rewards building to see what you unlock over time.",
	},
	{
		title = "Getting Around",
		body = "Every major building has a floating sign above it and its name on the front. Click either one to "
			.. "teleport straight to that building's entrance instead of walking - handy when you're across the map.",
	},
}

return TutorialTopicsConfig
