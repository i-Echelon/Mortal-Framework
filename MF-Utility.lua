-- #################################################
-- # UTILITY
-- #################################################
local MF  = MortalFramework
local C   = MF.Constants
local mod = MF.mod

-- cache hot globals
local ipairs = ipairs
local rep, format = string.rep, string.format
local concat, insert, sort = table.concat, table.insert, table.sort
local floor, min, max, random = math.floor, math.min, math.max, math.random

local baseYear     = C.BASE_YEAR
local daysPerMonth = C.DAYS_PER_MONTH
local daysPerYear  = C.DAYS_PER_YEAR
local invDaysY     = 1 / daysPerYear

-- month-name tables
local FantasyMonths = {
	"Frostwane","Snowmelt","Rainmoot","Blossomtide","Greengrowth","Sunpeak",
	"Highsun","Harvestwane","Duskwatch","Coldfall","Darkreach","Deepfrost"
}
local JulianMonths = {
	"January","February","March","April","May","June",
	"July","August","September","October","November","December"
}

-- ─────────────────────── MISC FUNCTIONS ───────────────────────

function debugLog(msg)
    if MF.Config.DEBUG_MODE then
		mod:msgBox(format("[Mortal v%s DEBUG] %s", MF.VERSION, msg))
	else
		mod:log(format("[Mortal v%s] %s", MF.VERSION, msg))
	end
end

function validateDateStyle()  --validate custom date styles
	local s = MF.Config.DATE_STYLE
	if s~="Standard" and s~="Julian" and s~="Fantasy" then
		debugLog("Invalid DATE_STYLE '"..tostring(s).."', defaulting to Standard")
		MF.Config.DATE_STYLE = "Standard"
	end
end
validateDateStyle() mod:log("DATE_STYLE = " .. MF.Config.DATE_STYLE)

-- ─────────────────────── CALENDAR FUNCTIONS ───────────────────────
	
-- ordinal helper for Fantasy/Julian
function getOrdinal(n)
	local v = n % 100
	if v >= 11 and v <= 13 then return tostring(n) .. "th" end
	v = n % 10
	if v == 1 then return tostring(n) .. "st"
	elseif v == 2 then return tostring(n) .. "nd"
	elseif v == 3 then return tostring(n) .. "rd"
	else return tostring(n) .. "th" end
end

--- returns three numbers: year, month, day
function getCalendarFast(absDay)
	-- how many full years have passed?
	local yearsPassed = floor(absDay * invDaysY)
	local Y = baseYear + yearsPassed

	-- day-of-year without extra table math
	local dayOfYear = absDay - (yearsPassed * daysPerYear)
	local M = floor(dayOfYear / daysPerMonth) + 1
	local D = (dayOfYear % daysPerMonth) + 1

	return Y, M, D
end

-- format an absolute-index date as a string
function getFullDateString(absIdx, style)
	local Y, M, D = getCalendarFast(absIdx)
	if style == "Standard" then
		return format("%02d/%02d/%d", M, D, Y)
	elseif style == "Julian" then
		return format("%s %d, %d", JulianMonths[M], D, Y)
	else
		return format("%s %d, %d", FantasyMonths[M], D, Y)
	end
end

-- returns the day of year (0-based) for the given loop
function getCurrentYear(loop)
	return baseYear + floor(loop:getDay() * invDaysY)
end

function getDayOfYear(loop)
	return loop:getDay() % daysPerYear
end

--- Returns a 0-based “day of year” from the BirthdayMonth/Day
function getBirthdayDayOfYear(compAge)
	return (compAge.BirthdayMonth - 1) * daysPerMonth + (compAge.BirthdayDay   - 1)
end

-- ─────────────────────── FORMAT FUNCTIONS ───────────────────────
--- Returns "MM/DD"
function formatMd(month, day)
	return format("%02d/%02d", month, day)
end

--- Returns "MM/DD/YYYY"
function formatMdY(month, day, year) 
  return format("%02d/%02d/%04d", month, day, year) 
end

-- format a birthday from the component
function formatBirth(compAge, style)
	style = style or "Fantasy"
	if style == "Standard" then
		return formatMdY(compAge.BirthdayMonth, compAge.BirthdayDay, compAge.YearOfBirth)
	end
	local tbl = (style == "Julian") and JulianMonths or FantasyMonths
	return format("%s %s, %d",
		tbl[compAge.BirthdayMonth],	getOrdinal(compAge.BirthdayDay), compAge.YearOfBirth)
end

function formatList(title, list)
  if #list == 0 then return end
  mod:msgBox(title .. "\n" .. table.concat(list, "\n"))
end

-- ─────────────────────── I/O FUNCTIONS ───────────────────────

-- save to logs/<label>/summary_<year>.txt
function saveSummaryFile(mod, label, reportYear, text)
	local folder = "logs/" .. label
	if not mod:directoryExists(folder) then mod:createDirectory(folder) end
	local fname = format("%s/summary_%d.txt", folder, reportYear)
	local ok, err = mod:writeFileAsString(fname, text)
	if not ok then mod:logError("Failed to save summary: "..tostring(err)) end
end

--- Assemble the main death table for a given set of entries
-- entries: array of { Name, BornMdY, DiedMdY, JobTitle, Cause }
-- returns: string with Markdown‐style table
function formatDeathTable(entries)
	local headers = { "Name", "Age", "Born", "Died", "Job", "Cause" }
	 -- calculate column widths
	local widths = {}
	for i, h in ipairs(headers) do widths[i] = #h end
	for _, e in ipairs(entries) do
		widths[1]  = max(widths[1], #e.Name)
		widths[2]  = max(widths[2], #tostring(e.Age))
		widths[3]  = max(widths[3], #e.BornMdY)
		widths[4]  = max(widths[4], #e.DiedMdY)
		widths[5]  = max(widths[5], #e.JobTitle)
		widths[6]  = max(widths[6], #e.Cause)
	end
    -- header row
    local row = {}
    for i, h in ipairs(headers) do row[i] = "| " .. h .. rep(" ", widths[i] - #h) .. " " end
    local out = { concat(row, "") .. "|" }
    -- separator row
    for i=1,#row do row[i] = "| " .. rep("-", widths[i]) .. " " end
    out[#out+1] = concat(row, "") .. "|"
    -- data rows
    for _, e in ipairs(entries) do
        local cells = { e.Name, tostring(e.Age), e.BornMdY, e.DiedMdY, e.JobTitle, e.Cause, }
        for i, c in ipairs(cells) do cells[i] = "| " .. c .. rep(" ", widths[i] - #c) .. " " end
        out[#out+1] = concat(cells, "") .. "|"
    end
    return concat(out, "\n")
end

--- Assemble the cause‐summary table for a given set of entries
-- returns: string with Markdown‐style table
function formatCauseSummary(entries)
    -- tally causes
    local stats = {}
    for _, e in ipairs(entries) do stats[e.Cause] = (stats[e.Cause] or 0) + 1 end
    local list = {}
    for cause, cnt in pairs(stats) do list[#list+1] = { cause, tostring(cnt) } end
    sort(list, function(a,b) return tonumber(a[2]) > tonumber(b[2]) end)
    local headers = { "Cause", "Count" }
    local widths  = { #headers[1], #headers[2] }
    for _, row in ipairs(list) do
        widths[1] = max(widths[1], #row[1])
        widths[2] = max(widths[2], #row[2])
    end
    -- title
    local out = { "CAUSE SUMMARY" }
    -- header
    local row = {}
    for i, h in ipairs(headers) do row[i] = "| " .. h .. rep(" ", widths[i] - #h) .. " " end
    out[#out+1] = concat(row, "") .. "|"
    -- separator
    for i=1,#row do row[i] = "| " .. rep("-", widths[i]) .. " " end
    out[#out+1] = concat(row, "") .. "|"
    -- data
    for _, r in ipairs(list) do
        for i, c in ipairs(r) do r[i] = "| " .. c .. rep(" ", widths[i] - #c) .. " " end
        out[#out+1] = concat(r, "") .. "|"
    end
    return concat(out, "\n")
end

--- Backfill any missed birthdays on load & announce them
function backfillAges(mgr, loop)
	local d    = loop:getDay()
	local Y,M,D = getCalendarFast(d)
	local msgs = {}

	for _, vcomp in ipairs(mgr.throttleQueue) do
		local owner = vcomp:getOwner()
		local ca    = owner:getComponent("COMP_AGE")
		if ca and ca.Initialized and not ca.IsDead then
			-- did their birthday pass already this year?
			local hadBday = (M > ca.BirthdayMonth)
						or (M == ca.BirthdayMonth and D >= ca.BirthdayDay)
			local trueAge = Y - ca.YearOfBirth - (hadBday and 0 or 1)
			if trueAge > ca.Age then
					-- for each birthday they “missed,” queue a message
				for newAge = ca.Age + 1, trueAge do
					local birthStr = formatMd(ca.BirthdayMonth, ca.BirthdayDay)
					insert(	msgs, format("%s turns %d on %s", owner.Name, newAge, birthStr))
				end
				ca.Age = trueAge
			end
		end
	end
	-- blast them all in one dialog
	if #msgs > 0 then
		show("[HAPPY BIRTHDAY]", msgs)
	end
end