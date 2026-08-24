--[[
	Algebra.lua

	Round 8+ pool category ("Master" pool): one-step linear equations with
	an integer solution. Four equally-likely forms: x + a = b, x - a = b,
	m·x = b, x ÷ m = q. Ranges widened so the numbers involved take
	genuinely longer to work through than earlier rounds, without
	introducing any new algebraic concept.
]]

export type RawQuestion = {
	text: string,
	answer: number,
	tolerance: number?,
	debugOperands: { [string]: any }?,
}

local Algebra = {}

local function randomInt(min: number, max: number): number
	return math.random(min, max)
end

function Algebra.Generate(): RawQuestion
	local solution = randomInt(2, 35)
	local form = math.random(1, 4)

	if form == 1 then
		local a = randomInt(1, 45)
		local b = solution + a
		return {
			text = ("x + %d = %d"):format(a, b),
			answer = solution,
			debugOperands = { form = "add", a = a, b = b },
		}
	elseif form == 2 then
		local a = randomInt(1, 30)
		local b = solution - a
		return {
			text = ("x - %d = %d"):format(a, b),
			answer = solution,
			debugOperands = { form = "sub", a = a, b = b },
		}
	elseif form == 3 then
		local m = randomInt(2, 16)
		local b = m * solution
		return {
			text = ("%dx = %d"):format(m, b),
			answer = solution,
			debugOperands = { form = "mul", m = m, b = b },
		}
	else
		local m = randomInt(2, 16)
		local q = randomInt(2, 30) -- the equation's right-hand side; x = q * m
		local x = m * q
		return {
			text = ("x \u{00F7} %d = %d"):format(m, q),
			answer = x,
			debugOperands = { form = "div", m = m, q = q },
		}
	end
end

return Algebra
