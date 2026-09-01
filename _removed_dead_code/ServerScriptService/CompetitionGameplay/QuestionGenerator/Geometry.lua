--[[
	Geometry.lua

	Round 8+ pool category ("Master" pool). Rectangle area/perimeter,
	triangle area, or a compound two-rectangle area, with integer
	dimensions chosen so the result is always a whole number. Dimensions
	widened and the compound variant added so Master-pool Geometry
	genuinely takes longer to work through than earlier rounds - through
	bigger numbers and a real extra step, not a new formula/concept.
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
	local shape = math.random(1, 4)

	if shape == 1 then
		local length = randomInt(5, 35)
		local width = randomInt(5, 35)
		return {
			text = ("A rectangle has length %d and width %d. What is its area?"):format(length, width),
			answer = length * width,
			debugOperands = { shape = "rectangleArea", length = length, width = width },
		}
	elseif shape == 2 then
		local length = randomInt(5, 35)
		local width = randomInt(5, 35)
		return {
			text = ("A rectangle has length %d and width %d. What is its perimeter?"):format(length, width),
			answer = 2 * (length + width),
			debugOperands = { shape = "rectanglePerimeter", length = length, width = width },
		}
	elseif shape == 3 then
		local base = randomInt(5, 35)
		local height = randomInt(5, 35)
		if (base * height) % 2 ~= 0 then
			height += 1 -- keep the area a whole number
		end
		return {
			text = ("A triangle has base %d and height %d. What is its area?"):format(base, height),
			answer = (base * height) / 2,
			debugOperands = { shape = "triangleArea", base = base, height = height },
		}
	end

	-- Compound two-rectangle area: a genuine two-step version of the same
	-- rectangleArea formula ("more steps... not extremely advanced
	-- functions") - compute each rectangle's area, then add them.
	local lengthA = randomInt(5, 25)
	local widthA = randomInt(5, 25)
	local lengthB = randomInt(5, 25)
	local widthB = randomInt(5, 25)
	return {
		text = (
			"A room is made of two rectangular sections: one is %d by %d, the other is %d by %d. What is the TOTAL area of both sections combined?"
		):format(lengthA, widthA, lengthB, widthB),
		answer = (lengthA * widthA) + (lengthB * widthB),
		debugOperands = { shape = "compoundRectangleArea", lengthA = lengthA, widthA = widthA, lengthB = lengthB, widthB = widthB },
	}
end

return Geometry
