--[[
	This file has been neutralized (Claude has no delete capability for the
	local filesystem). It briefly implemented a teleport-based Hub redirect
	(disable character auto-spawn, immediately TeleportService:Teleport
	every joining player to the Futuristic Place) that was abandoned because
	TeleportService does not work within a single local Play-Test session -
	combined with disabling character spawn, that left players stuck in an
	empty void with nothing loaded at all.

	Replaced by a much simpler approach: Main.server.lua's Hub branch now
	just builds the Futuristic map directly (the same LobbyBuilder.Build/
	ArenaBuilder.BuildForMap call a dedicated difficulty Place makes for its
	own map), so a player lands straight on a real, playable map with no
	redirect, no teleport, and no separate Hub scene ever existing at all.

	Nothing requires this module anymore. It can be safely deleted:

		src/ServerScriptService/HubRedirectSystem/init.lua
]]
