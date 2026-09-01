--[[
	Roots.lua

	Round 7 category ("Square roots"). Always a perfect square so the
	answer is a clean integer.
]]

export type RawQuestion = {
	text: string,
	answer: number,
	tolerance: number?,
	debugOperands: { [string]: any }?,
}

local Roots = {}

local function randomInt(min: number, max: number): number
	return math.random(min, max)
end

function Roots.Generate(): RawQuestion
	local root = randomInt(2, 15)
	local radicand = root * root

	return {
		text = ("\u{221A}%d"):format(radicand),
		answer = root,
		debugOperands = { root = root, radicand = radicand },
	}
end

return Roots
