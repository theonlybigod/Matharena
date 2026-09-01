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

	THREE-WALL LECTURE ROOM. The Tutorial building now presents each topic
	across three screens at once rather than one back wall, so each field
	below has a fixed destination:

		- `title` + `body`   -> LEFT wall  (the words and descriptions)
		- `caption`          -> CENTRE wall, under the map image/video loop
		- `tips`             -> RIGHT wall (tips and heads-ups, one per line)

	The bottom-bar overlay (TutorialUIController) only ever reads `title`
	and `body`, so it is completely unaffected by the two new fields - they
	are additive, and a topic that omits them still renders correctly on
	every surface.

	`tips` is a list of SHORT lines. They are heads-ups a player benefits
	from knowing before they hit the thing in question, not a restatement of
	the body text - if a tip could be deleted without the player losing
	anything, it should be.
]]

local TutorialTopicsConfig = {}

--[[
	Per-map media for the CENTRE screen: a still of the map, and a short
	looping clip (aim for ~4 seconds - it loops, so anything longer reads as
	a video rather than an ambient backdrop).

	Keyed by MapsConfig `id`, so each arena shows ITSELF on the centre wall
	rather than a generic image - a player sitting in the Under the Sea
	tutorial sees the Under the Sea arena.

	BOTH IDS ARE 0 UNTIL YOU UPLOAD THE ASSETS. 0 is the same placeholder
	convention AudioConfig already uses. Uploading is a manual step that has
	to happen from your own Roblox account - image and video assets cannot be
	created from code, and a made-up numeric id would either fail to load or
	resolve to somebody else's unrelated asset, which is worse than an
	honest blank. Until an id is set, the centre screen shows a labelled
	placeholder naming exactly which asset is missing, and the room is fully
	functional without it.

	To wire one up: upload the image (Decal) and the video, then paste the
	numeric ids below. Video assets additionally require your experience to
	be allowed to use them, so a video id that works in Studio may still be
	blank for other players until it has moderation-passed.
]]
TutorialTopicsConfig.MAP_MEDIA = {
	Futuristic = { imageId = 0, videoId = 0, label = "Futuristic Arena" },
	Lava = { imageId = 0, videoId = 0, label = "Lava Arena" },
	Space = { imageId = 0, videoId = 0, label = "Space Arena" },
	UnderTheSea = { imageId = 0, videoId = 0, label = "Under the Sea Arena" },
	IceAge = { imageId = 0, videoId = 0, label = "Ice Age Arena" },
}

--[[
	Returns the media entry for `mapId`, or a safe empty entry. Never nil, so
	the screen controller never has to branch on a missing map.
]]
function TutorialTopicsConfig.GetMapMedia(mapId: string?)
	return (mapId and TutorialTopicsConfig.MAP_MEDIA[mapId])
		or { imageId = 0, videoId = 0, label = "MathArena" }
end

TutorialTopicsConfig.TOPICS = {
	{
		title = "How to Play",
		body = "MathArena is a competitive math game show. Join a match, answer questions faster and more "
			.. "accurately than your opponents, and be the last one standing to win Coins, XP, and Gems.",
		caption = "Welcome to MathArena",
		tips = {
			"Everything here is optional - read at your own pace.",
			"Use the pads either side of the centre screen to page.",
			"Finishing this tutorial unlocks Quests.",
		},
	},
	{
		title = "The Lobby",
		body = "The lobby is the hub between matches. The queue portal sits at the centre, the leaderboards "
			.. "stand on the spawn side, and four buildings ring the back: Shop, Daily Rewards, Tutorial, and "
			.. "Statistics. Each building holds one feature you cannot reach from the bottom bar.",
		caption = "Your home between matches",
		tips = {
			"Each building has exactly one thing inside it.",
			"If a feature is on the bottom bar, it is not in a building.",
			"You can walk the whole map - nothing is locked off.",
		},
	},
	{
		title = "How Matchmaking Works",
		body = "Click PLAY to pick a difficulty and queue up directly - no need to walk anywhere first. A match "
			.. "needs at least 2 players and holds up to 12 - once enough players are queued, a countdown begins "
			.. "and you're teleported to the arena.",
		caption = "Queue from anywhere",
		tips = {
			"You can leave the queue any time before the countdown ends.",
			"Queueing does not cost anything.",
			"Fuller queues start faster - try a busier difficulty.",
		},
	},
	{
		title = "Difficulties & Arenas",
		body = "There are five difficulties, and each one has its own arena: Easy, Medium (Under the Sea), "
			.. "Hard (Tundra), Expert (Volcano), and Master. Harder tiers ask harder questions and give less "
			.. "time per question, but pay out more. Pick the one you want from the PLAY menu.",
		caption = "Five tiers, five worlds",
		tips = {
			"Difficulty changes the questions AND the time limit.",
			"Start lower than you think - speed matters more than ceiling.",
			"Each arena is a different place, so expect a short load.",
		},
	},
	{
		title = "How Questions Work",
		body = "Questions get progressively harder as a match goes on, from basic arithmetic to fractions, "
			.. "percentages, and beyond. Each question has a time limit based on its difficulty - answer "
			.. "correctly before time runs out, or you're eliminated.",
		caption = "Answer before the timer runs out",
		tips = {
			"Read the whole question - the trap is usually in the wording.",
			"A wrong answer costs the same as no answer.",
			"The timer shrinks as the match goes on.",
		},
	},
	{
		title = "Question Types",
		body = "You will meet basic arithmetic, order of operations, fractions, decimals, percentages, "
			.. "exponents, roots, algebra, geometry, and mixed operations. Which types appear depends on how "
			.. "far into the match you are and which difficulty you queued for.",
		caption = "Ten families of questions",
		tips = {
			"Order of operations catches more players than hard algebra.",
			"Practice Mode draws from the same question pool.",
			"Weak on one type? Practice it with Infinite Time.",
		},
	},
	{
		title = "Elimination & Winning",
		body = "Miss a question or run out of time and you are eliminated from that match. Eliminated players "
			.. "stay to spectate rather than being sent away. The last player standing wins; if time or "
			.. "questions run out with several players left, standing is decided on accuracy and speed.",
		caption = "Last one standing takes it",
		tips = {
			"Being eliminated still pays out - you keep what you earned.",
			"Spectating is a fast way to learn the harder tiers.",
			"You can leave a match you are out of at any time.",
		},
	},
	{
		title = "Practice Mode",
		body = "Practice Mode lets you answer the same kinds of questions with no elimination to lose over. "
			.. "Click the PRACTICE button in the lobby any time and choose Regular Practice or Extra Time Mode "
			.. "(2x-5x time per question, or Infinite Time) - it doesn't count as a competitive match and won't "
			.. "affect your Wins or leaderboard standing.",
		caption = "No timer pressure, no stakes",
		tips = {
			"Infinite Time is the one to use when learning a new type.",
			"Practice never affects Wins, rank, or your streak.",
			"You can stop a practice run whenever you like.",
		},
	},
	{
		title = "Quests",
		body = "Your Quest Log sits on the left edge of the screen - open it any time to see your current quests. "
			.. "Quests are entirely manual: you choose when to Accept one, Refresh a standard quest for a "
			.. "different one (up to 3 times a day), Cancel one you've accepted, or Claim a completed one. "
			.. "Nothing is ever accepted for you automatically. Quests unlock once you finish this tutorial.",
		caption = "Accept, complete, claim",
		tips = {
			"Nothing is auto-accepted - an unaccepted quest earns nothing.",
			"You get 3 refreshes a day on standard quests.",
			"Claim finished quests before they expire.",
		},
	},
	{
		title = "Coins, Gems & XP",
		body = "Three currencies. Coins are the everyday one, earned from playing and winning. Gems are rarer "
			.. "and come from bigger milestones. XP is not spendable - it raises your level, which is what "
			.. "unlocks progression rewards over time.",
		caption = "What you earn, and what it does",
		tips = {
			"XP cannot be spent - only Coins and Gems can.",
			"You earn something from every match, win or lose.",
			"Harder difficulties pay more per match.",
		},
	},
	{
		title = "Rewards & XP",
		body = "Winning and playing matches earns Coins, XP, and Gems. Spend Coins and Gems in the Shop on "
			.. "cosmetics, and check the Rewards track and Daily Rewards building to see what you unlock over time.",
		caption = "Progress that carries between matches",
		tips = {
			"The Reward Track advances on XP, not on wins.",
			"Rewards you have not claimed are kept, not lost.",
			"Check the track after a long session.",
		},
	},
	{
		title = "The Shop",
		body = "The Shop building holds the Featured Item of the Day - one cosmetic shown at full size on a "
			.. "preview column, which you can only see by walking in. Buy from the terminal inside, or browse "
			.. "the full cosmetics list from the bottom bar.",
		caption = "One featured item, every day",
		tips = {
			"The featured item rotates daily - it may be gone tomorrow.",
			"Cosmetics are visual only and never affect questions.",
			"The full catalogue is on the bottom bar, not in the building.",
		},
	},
	{
		title = "Daily Rewards & Streaks",
		body = "The Daily Rewards building shows your streak as a physical seven-step path running toward the "
			.. "screen, lit gold for the day you can claim now and grey for the days ahead. Claim once a day "
			.. "from the terminal to keep the streak going; the later days are worth the most.",
		caption = "Seven days, rising rewards",
		tips = {
			"Missing a day resets the streak to day one.",
			"The gold plinth is the day you can claim right now.",
			"You can only claim once per day, however long you play.",
		},
	},
	{
		title = "Leaderboards",
		body = "The lobby leaderboards track Wins, XP, Questions Solved, Accuracy, and Fastest Answer. They "
			.. "are global and refresh as players finish matches, so a strong run can move you up while you "
			.. "are still standing there.",
		caption = "Five boards, global standing",
		tips = {
			"Accuracy rewards care, not speed - a separate board entirely.",
			"Practice runs never count toward any board.",
			"Boards update after a match resolves, not mid-question.",
		},
	},
	{
		title = "Statistics & Rivals",
		body = "The Statistics building puts your own numbers head-to-head against the current leaderboard "
			.. "leaders on one wall-sized board - how far off the top you are in each category, and what you "
			.. "would need to close the gap. It only exists inside that building.",
		caption = "You versus the leaders",
		tips = {
			"This comparison is nowhere else in the game.",
			"There are two seats - the board is meant to be read sitting.",
			"Numbers are yours alone; nobody else sees them.",
		},
	},
	{
		title = "Getting Around",
		body = "Every major building has a floating sign above it and its name on the front. Click either one to "
			.. "teleport straight to that building's entrance instead of walking - handy when you're across the map.",
		caption = "Click a sign to travel",
		tips = {
			"Both the floating sign and the door plate work as targets.",
			"Teleports always take you to YOUR map's copy.",
			"Walking still works if you would rather look around.",
		},
	},
	{
		title = "Settings",
		body = "Settings are on the bottom bar. You can adjust music and sound effects, visual effects, and "
			.. "other comfort options. Changes save to your account and follow you into every match and arena.",
		caption = "Tune it to suit you",
		tips = {
			"Settings persist across sessions and arenas.",
			"Turning effects down can help on a slower device.",
			"Nothing in Settings changes question difficulty.",
		},
	},
	{
		title = "You're Ready",
		body = "That is the whole game. Click PLAY to queue for a match, PRACTICE to warm up with no stakes, "
			.. "or walk out and explore. You can come back and sit here again any time - this room does not "
			.. "lock after the first read, and the bottom-bar Tutorial button shows the same text.",
		caption = "Go and play",
		tips = {
			"This room stays open forever - come back whenever.",
			"Try Practice first if you have not answered one yet.",
			"Quests unlock the moment the walkthrough is done.",
		},
	},
}

return TutorialTopicsConfig
