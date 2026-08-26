--[[
	BuildingSignController.client.lua

	INTENTIONALLY INERT.

	This script used to own the building-teleport click: it found every
	sign's TextButton by CollectionService tag, reparented the sign's
	BillboardGui into PlayerGui, and fired "RequestTeleportToBuilding" on
	MouseButton1Click.

	That whole approach is gone. Clicking a building sign is now handled
	server-side by ClickDetectors on real geometry - see
	LobbyBuilder/BuildingSigns.lua (MakeTeleportTarget) and
	BuildingTeleportSystem (server), which wires every tagged target.

	Why the client half had to be REMOVED rather than left as a harmless
	fallback: a GUI element under the cursor ABSORBS the click and stops
	the mouse from reaching world geometry. A transparent sign button
	hosted in PlayerGui would therefore have blocked the very
	ClickDetector that now does the work. The two mechanisms cannot
	coexist over the same screen area - that conflict is itself one of
	the reasons the sign stayed unclickable through an earlier fix.

	The signs themselves are unchanged and still built in exactly one
	place (BuildingSigns.lua); they are presentation only now.

	This file is left in place, empty, rather than deleted, because
	removing a source-controlled script is a change worth making
	deliberately - see README section 7. It is safe to delete.
]]
