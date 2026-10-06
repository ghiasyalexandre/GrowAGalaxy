--!strict
-- Number formatting for the HUD and in-world labels.

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

local Format = {}

function Format.abbreviate(n: number): string
	local value = n
	local index = 1
	while math.abs(value) >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end
	if index == 1 then
		return tostring(math.floor(value))
	end
	return string.format("%.1f%s", value, SUFFIXES[index])
end

-- A whole number with thousands separators ("1,234,567"), for exact prices.
function Format.commas(n: number): string
	local text = tostring(math.floor(math.abs(n) + 0.5))
	local grouped = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	grouped = string.gsub(grouped, "^,", "")
	return if n < 0 then `-{grouped}` else grouped
end

return Format
