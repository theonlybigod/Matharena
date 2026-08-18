--[[
	AudioController.client.lua

	Client-side audio (Message 12): lobby/competition music, countdown,
	correct/wrong, elimination, and winner stings. Built entirely from
	AudioConfig's cue registry - creating a new Sound here means adding
	one entry to AudioConfig, not touching this file's logic.

	IMPORTANT: every SoundId in AudioConfig is currently a placeholder
	("rbxassetid://0" - Roblox's standard "no sound" id). This script's
	wiring (volume control, trigger points, music switching) is fully
	real and functional; a developer just needs to swap in real
	licensed/uploaded audio ids before publishing (Claude cannot supply
	copyrighted audio). See AudioConfig.lua for details.

	Reacts to settings changes (music/SFX volume) live via
	ClientSettingsState, and to match-flow remotes for cue triggers -
	this script never decides game state itself, only plays sound in
	response to what the server already broadcasts.
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AudioConfig = require(ReplicatedStorage.Modules.AudioConfig)
local MatchConfig = require(ReplicatedStorage.Modules.MatchConfig)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local ClientSettingsState = require(script.Parent.ClientSettingsState)

local soundFolder = Instance.new("Folder")
soundFolder.Name = "MathArenaAudio"
soundFolder.Parent = SoundService

local sounds: { [string]: Sound } = {}

for name, cue in pairs(AudioConfig.CUES) do
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = cue.id
	sound.Looped = cue.looped
	sound.Volume = cue.defaultVolume
	sound.Parent = soundFolder
	sounds[name] = sound
end

local function applyVolumes()
	local musicVolume = ClientSettingsState.Get("musicVolume") or 0.5
	local sfxVolume = ClientSettingsState.Get("sfxVolume") or 0.7

	for name, cue in pairs(AudioConfig.CUES) do
		local sound = sounds[name]
		local categoryVolume = if cue.category == "Music" then musicVolume else sfxVolume
		sound.Volume = cue.defaultVolume * categoryVolume
	end
end

ClientSettingsState.Subscribe(function(key: string)
	if key == "musicVolume" or key == "sfxVolume" then
		applyVolumes()
	end
end, true)

local function playOneShot(name: string)
	local sound = sounds[name]
	if sound then
		sound:Play()
	end
end

local function switchMusic(toName: string)
	for name, sound in pairs(sounds) do
		if AudioConfig.CUES[name].category == "Music" and name ~= toName and sound.IsPlaying then
			sound:Stop()
		end
	end

	local target = sounds[toName]
	if target and not target.IsPlaying then
		target:Play()
	end
end

-- ===== Music: lobby vs. competition, driven by match state =====

RemoteEvents.Get("GameStateChanged").OnClientEvent:Connect(function(state: string)
	if state == MatchConfig.GameState.Playing or state == MatchConfig.GameState.Winner then
		switchMusic("CompetitionMusic")
	else
		switchMusic("LobbyMusic")
	end
end)

-- ===== Countdown (3-2-1-GO) =====

RemoteEvents.Get("MatchCountdownTick").OnClientEvent:Connect(function(step: string?)
	if step and step ~= "" then
		playOneShot("Countdown")
	end
end)

-- ===== Correct / Wrong / Elimination =====

RemoteEvents.Get("TurnResolved").OnClientEvent:Connect(function(payload)
	if payload.correct then
		playOneShot("Correct")
	else
		playOneShot("Wrong")
		-- Elimination is a distinct cue from Wrong (a wrong answer always
		-- causes an elimination in this single-elimination format) - a
		-- brief delay so it reads as "wrong, THEN eliminated" rather than
		-- two sounds fighting for attention at once.
		task.delay(0.3, playOneShot, "Elimination")
	end
end)

-- ===== Winner =====

RemoteEvents.Get("MatchWinner").OnClientEvent:Connect(function()
	playOneShot("Winner")
end)

-- Start with lobby music playing (the server may already be past Lobby
-- state by the time this script runs, e.g. rejoining mid-match, but
-- GameStateChanged's first future fire will correct this).
switchMusic("LobbyMusic")
