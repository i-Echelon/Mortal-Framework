-- #################################################
-- # EXTERNAL API (MortalFramework table)
-- #################################################
--- MortalFramework API
-- @module MortalFramework
-- @brief Functions for querying death archives: counts, averages, per-year lookups
-- ──────────────────────────────────────────────────────────────────────────
local MF = MortalFramework

-- internal: computes average Age over any list of entries
local function computeAverage(entries)
    local sum, count = 0, 0
    for _, e in ipairs(entries or {}) do
        sum   = sum + (e.Age or 0)
        count = count + 1
    end
    return (count > 0) and (sum / count) or 0
end

--- Returns the number of recorded deaths, optionally filtered by cause and/or year
function MF:getDeathCount(cause, year)
	local cnt = 0
	for _, e in ipairs(self.Entries) do
		if e.Cause == cause and e.Year == year then cnt = cnt + 1 end
	end
	return cnt
end

--- Returns the array of death entries for the given year (or empty table if none)
function MF:getYearlyArchive(year)
	local out = {}
	for _, e in ipairs(self.Entries) do
		if e.Year == year then table.insert(out, e) end
	end
	return out
end

--- Returns the average lifespan of deaths in a given year
function MF:getYearlyAverage(year)
    return computeAverage(self:getYearlyArchive(year))
end

--- Computes the average lifespan (in years, fractional) of all recorded deaths
function MF:getAverageLifespan()
    return computeAverage(self.Entries)
end

--- Pop up a list of every enabled villager’s age & date of birth.
-- @param level Game level (COMP_MAIN_GAME_LOOP component) or nil to auto-find.
--[[function MF:showAgeCheck()
	-- inside your driver (e.g. at end of onEnabled or in a debug command)
	local ages = {}
	local vMgr = self:getLevel():getComponentManager("COMP_VILLAGER")
	local allV = vMgr:getAllEnabledComponent()

	-- materialize intrusive list if needed
	local villagers = {}
	if allV.forEach then
	  allV:forEach(function(c) table.insert(villagers, c) end)
	else
	  villagers = allV
	end

	for _, vcomp in ipairs(villagers) do
	  local owner = vcomp:getOwner()
	  local ca    = owner:getComponent("COMP_AGE")
	  if ca and ca.Initialized then
		local bMon, bDay, yob = ca.BirthdayMonth, ca.BirthdayDay, ca.YearOfBirth
		ages[#ages+1] = string.format(
		  "%s - [AGE]: %d - [DOB]: %02d/%02d/%d",
		  owner.Name,
		  ca.Age,
		  bMon, bDay, yob
		)
	  end
	end

	if #ages > 0 then
	  mod:msgBox("[AGE & BIRTHDAYS]\n" .. table.concat(ages, "\n"))
	end
end--]]