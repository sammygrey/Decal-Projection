local Generator = {}
Generator.__index = Generator

export type Class = typeof(setmetatable({}:: {
	_seed: IntValue?
}, Generator))

function Generator.GenerateUUID(self: Class, wrapInCurlyBraces: boolean?)
	if self._seed then
		math.randomseed(self._seed)
	end

	local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
	if wrapInCurlyBraces then
		template = '{' .. template .. '}'
	end

	return string.gsub(template, '[xy]', function (c)
		local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
		return string.format('%x', v)
	end)
end

function Generator.CreateUniqueSeed(self: Class)
	-- Is this number random? No. However, we can use this to our advantage as this seed will never have a duplicate.
	self._seed = os.time()
end

function Generator.SetSeed(self: Class, Seed: number)
	self._seed = Seed
end

return Generator