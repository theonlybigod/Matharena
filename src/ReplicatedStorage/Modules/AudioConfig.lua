--[[
	AudioConfig.lua

	Centralized registry of every audio cue in MathArena (Message 12):
	lobby/competition music, countdown, correct/wrong, elimination, and
	winner stings. Pure data - AudioController.client.lua owns actually
	creating Sound instances and playing them.

	IMPORTANT - PLACEHOLDER ASSET IDS: every SoundId below is
	"rbxassetid://0" (Roblox's standard "no sound" placeholder id).
	Claude has no way to upload or license real audio, and fabricating
	specific numeric asset ids would risk pointing at content that either
	doesn't exist or isn't rights-cleared for this project. The full
	audio ARCHITECTURE here is real and functional (volume categories,
	trigger points, settings integration) - a developer just needs to
	replace these ids with real uploaded/licensed audio before publishing.
	This is a normal, expected step for any Roblox game (Claude cannot
	own or supply copyrighted audio on a developer's behalf).
]]

export type SoundCategory = "Music" | "SFX"

export type SoundCue = {
	id: string,
	category: SoundCategory,
	looped: boolean,
	defaultVolume: number,
}

local AudioConfig = {}

AudioConfig.PLACEHOLDER_SOUND_ID = "rbxassetid://0"

AudioConfig.CUES = {
	LobbyMusic = { id = AudioConfig.PLACEHOLDER_SOUND_ID, category = "Music", looped = true, defaultVolume = 0.4 },
	CompetitionMusic = { id = AudioConfig.PLACEHOLDER_SOUND_ID, category = "Music", looped = true, defaultVolume = 0.4 },
	Countdown = { id = AudioConfig.PLACEHOLDER_SOUND_ID, category = "SFX", looped = false, defaultVolume = 0.7 },
	Correct = { id = AudioConfig.PLACEHOLDER_SOUND_ID, category = "SFX", looped = false, defaultVolume = 0.7 },
	Wrong = { id = AudioConfig.PLACEHOLDER_SOUND_ID, category = "SFX", looped = false, defaultVolume = 0.7 },
	Elimination = { id = AudioConfig.PLACEHOLDER_SOUND_ID, category = "SFX", looped = false, defaultVolume = 0.7 },
	Winner = { id = AudioConfig.PLACEHOLDER_SOUND_ID, category = "SFX", looped = false, defaultVolume = 0.8 },
} :: { [string]: SoundCue }

return AudioConfig
