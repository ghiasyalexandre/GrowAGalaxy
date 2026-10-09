--!strict
-- Number formatting for the HUD and in-world labels.

-- Shorthand: k thousand, m million, b billion, t trillion, qa, qi.
local SUFFIXES = { "", "k", "m", "b", "t", "qa", "qi" }

local Format = {}

function Format.abbreviate(n: number): string
	local value = n
	local index = 1
	while math.abs(value) >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end
	if index == 1 then
		-- Small fractional rates keep one decimal ("1.2"); whole numbers don't.
		if value < 100 and value ~= math.floor(value) then
			return (string.gsub(string.format("%.1f", value), "%.0$", ""))
		end
		return tostring(math.floor(value))
	end
	return string.format("%.1f%s", value, SUFFIXES[index])
end

-- A rate per second: one decimal under 100 ("1.2", "45.6"), whole with
-- separators under a million ("12,345"), abbreviated above ("3.4M").
function Format.rate(n: number): string
	local value = math.max(n, 0)
	if value < 100 then
		local text = string.format("%.1f", value)
		return (string.gsub(text, "%.0$", ""))
	elseif value < 1e6 then
		return Format.commas(value)
	end
	return Format.abbreviate(value)
end

-- A whole number with thousands separators ("1,234,567"), for exact prices.
function Format.commas(n: number): string
	local text = tostring(math.floor(math.abs(n) + 0.5))
	local grouped = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	grouped = string.gsub(grouped, "^,", "")
	return if n < 0 then `-{grouped}` else grouped
end

return Format
