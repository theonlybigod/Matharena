--[[
	Geometry.lua

	Round 8+ pool category. Rectangle area/perimeter or triangle area, with
	integer dimensions chosen so the result is always a whole number.
]]

export type RawQuestion = {
	text: string,
	answer: number,
	tolerance: number?,
	debugOperands: { [string]: any }?,
}

local Geometry = {}

local function randomInt(min: number, max: number): number
	return math.random(min, max)
end

function Geometry.Generate(): RawQuestion
	local shape = math.random(1, 3)

	if shape == 1 then
		local length = randomInt(2, 20)
		local width = randomInt(2, 20)
		return {
			text = ("A rectangle has length %d and width %d. What is its area?"):format(length, width),
			answer = length * width,
			debugOperands = { shape = "rectangleArea", length = length, width = width },
		}
	elseif shape == 2 then
		local length = randomInt(2, 20)
		local width = randomInt(2, 20)
		return {
			text = ("A rectangle has length %d and width %d. What is its perimeter?"):format(length, width),
			answer = 2 * (length + width),
			debugOperands = { shape = "rectanglePerimeter", length = length, width = width },
		}
	end

	local base = randomInt(2, 20)
	local height = randomInt(2, 20)
	if (base * height) % 2 ~= 0 then
		height += 1 -- keep the area a whole number
	end
	return {
		text = ("A triangle has base %d and height %d. What is its area?"):format(base, height),
		answer = (base * height) / 2,
		debugOperands = { shape = "triangleArea", base = base, height = height },
	}
end

return Geometry
