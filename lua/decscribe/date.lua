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

---@param date_str string
---@return decscribe.date.Date? precisioned_date_opt or nil if could not parse
function M.str2prec_date(date_str)
	local _, _, year, month, day =
		string.find(date_str or "", "^(%d%d%d%d)(%d%d)(%d%d)")
	if year and month and day then
		local timestamp = os.time({ year = year, month = month, day = day })
		return { timestamp = timestamp, precision = M.Precision.Date }
	else
		return nil -- unexpected format
	end
end

---@param datetime_str string
---@return decscribe.date.Date? precisioned_date_opt nil if could not be parsed
function M.str2prec_dt(datetime_str)
	local _, _, year, month, day, hour, minute =
		string.find(datetime_str or "", "^(%d%d%d%d)(%d%d)(%d%d)T(%d%d)(%d%d)")
	if year and month and day and hour and minute then
		local timestamp = os.time({
			year = year,
			month = month,
			day = day,
			hour = hour,
			min = minute,
		})
		return { timestamp = timestamp, precision = M.Precision.DateTime }
	else
		return nil -- unexpected format
	end
end

---@param prec_date decscribe.date.Date
---@return string
function M.prec_date2str(prec_date)
	local out
	if prec_date.precision == M.Precision.DateTime then
		out = os.date("%Y%m%dT%H%M", prec_date.timestamp)
	else
		out = os.date("%Y%m%d", prec_date.timestamp)
	end
	---@cast out string
	return out
end

return M
