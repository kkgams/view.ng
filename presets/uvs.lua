local uvs = {}
for i = 0, 32 * 32 - 1 do
	local x = i % 32
	local y = math.floor(i / 32)
	uvs[#uvs + 1] = {
		x * 16 / 512,
		y * 16 / 512,
		(x + 1) * 16 / 512,
		(y + 1) * 16 / 512,
	}
end

outputs[1] = uvs
