--[[
	Percentages.lua

	Round 4 category: "What is X% of Y?" Y is always chosen as a multiple
	of 20, which divides cleanly for every percent in PERCENTS below,
	guaranteeing a whole-number answer.
]]

export type RawQuestion = {
	text: string,
	answer: number,
	tolerance: number?,
	debugOperands: { [string]: any }?,
}

local Percentages = {}

local PERCENTS = { 10, 20, 25, 50, 75 }

local function randomInt(min: number, max: number): number
	return math.random(min, max)
end

function Percentages.Generate(): RawQuestion
	local percent = PERCENTS[math.random(1, #PERCENTS)]
	local y = 20 * randomInt(1, 10)
	local answer = (percent * y) / 100

	return {
		text = ("What is %d%% of %d?"):format(percent, y),
		answer = answer,
		debugOperands = { percent = percent, y = y },
	}
end

return Percentages
