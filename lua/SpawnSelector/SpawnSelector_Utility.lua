-- SpawnSelector
-- lua/SpawnSelector/SpawnSelector_Utility.lua
--
-- Class_ReplaceMethod is vendored verbatim from the NSL plugin.
-- Source: https://github.com/xToken/NSL - lua/NSL/nsl_utilities.lua - by Dragon
-- It safely swaps a method on a class and all of its already-derived classes,
-- returning the original so callers can chain to it.

-- Guard against double-definition (loaded from both client and server bootstraps).
if not Class_ReplaceMethod then

	local function ReplaceMethodInDerivedClasses(className, methodName, method, original)

		-- only replace the method when it matches with super class (has not been implemented by the derived class)
		if _G[className][methodName] ~= original then
			return
		end

		_G[className][methodName] = method

		local classes = Script.GetDerivedClasses(className)

		if classes then
			for i, c in ipairs(classes) do
				ReplaceMethodInDerivedClasses(c, methodName, method, original)
			end
		end

	end

	function Class_ReplaceMethod(className, methodName, method)

		if _G[className] == nil then
			return nil
		end

		local original = _G[className][methodName]

		if original then
			ReplaceMethodInDerivedClasses(className, methodName, method, original)
		end

		return original

	end

end
