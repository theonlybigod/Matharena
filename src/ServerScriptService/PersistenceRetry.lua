--[[
	PersistenceRetry.lua

	Tiny shared retry-with-backoff helper for DataStore/OrderedDataStore
	calls (Message 11). Used by DataSystem and LeaderboardSystem so the
	retry policy lives in exactly one place instead of being duplicated
	across every module that talks to a DataStore.
]]

local PersistenceRetry = {}

PersistenceRetry.MAX_ATTEMPTS = 3
PersistenceRetry.BACKOFF_SECONDS = { 1, 2 } -- wait before attempt 2 and attempt 3, respectively

--[[
	Calls `fn()` (no arguments - capture whatever you need via closure) up
	to MAX_ATTEMPTS times, pcall-wrapped, with a short backoff between
	attempts. Returns (true, result) on the first successful attempt, or
	(false, lastErrorMessage) if every attempt failed.
]]
function PersistenceRetry.Attempt<T>(fn: () -> T): (boolean, T | string)
	local lastError: string = "unknown error"

	for attemptNumber = 1, PersistenceRetry.MAX_ATTEMPTS do
		local ok, resultOrError = pcall(fn)
		if ok then
			return true, resultOrError
		end

		lastError = tostring(resultOrError)
		local backoff = PersistenceRetry.BACKOFF_SECONDS[attemptNumber]
		if backoff then
			task.wait(backoff)
		end
	end

	return false, lastError
end

return PersistenceRetry
