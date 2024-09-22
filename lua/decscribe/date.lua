local M = {}

---@enum decscribe.date.Precision
M.Precision = {
	Date = "DATE",
	DateTime = "DATETIME",
}

---@alias decscribe.date.Timestamp integer seconds since the epoch, as returned by os.time

---@class (exact) decscribe.date.Date
---@field timestamp decscribe.date.Timestamp
---@field precision decscribe.date.Precision

return M
