--!strict
--[[
	A deep copy, for the two places in the save path that must not write through to
	the caller's table.

	Both the migration runner and the validator work on a copy and let the caller
	adopt the result only on success. The input in both cases is live session data
	that ProfileStore will write to disk, so a half-finished transform left in place
	is a corrupt save rather than a failed operation.

	Shallow would not do. The fields that matter — party, storage, inventory, a
	creature's move list — are all nested, so a shallow copy shares exactly the
	tables a failed repair would have damaged.

	Keys are copied as-is and not recursed into. Save data is JSON, so every key is
	a string or a number.
]]

local function copy(value: unknown): unknown
	if type(value) ~= "table" then
		return value
	end

	local copied: { [unknown]: unknown } = {}
	for key, item in value :: { [unknown]: unknown } do
		copied[key] = copy(item)
	end
	return copied
end

return {
	copy = copy,
}
