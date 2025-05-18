-- ##############################################################
-- # MORTALITY FRAMEWORK BETA
-- # Echelon
-- # Modular villager aging, birthdays, mortality & archives
-- ##############################################################

-- ──────────────────────────────────────────────
-- # CONFIGURATION
-- ──────────────────────────────────────────────
local MF     = MortalFramework
local Config = MF.Config
local C      = MF.Constants
local mod    = MF.mod

-- cache hot globals
local ipairs = ipairs
local rep, format = string.rep, string.format
local concat, insert, sort = table.concat, table.insert, table.sort
local floor, min, max, random = math.floor, math.min, math.max, math.random

-- time constants
local baseYear		= C.BASE_YEAR
local daysPerWeek	= C.DAYS_PER_WEEK
local daysPerMonth	= C.DAYS_PER_MONTH
local daysPerYear	= C.DAYS_PER_YEAR
local monthsPerYear	= C.MONTHS_PER_YEAR


-- = RISK TABLES (unified schema)
-- ───────────────────────────────────────────────────────────────────
local AgeDeathCauses = {
    { MinAge=0,   MaxAge=14,  BaseChance=0.001, ChancePerYear=0.0001 },
    { MinAge=15,  MaxAge=49,  BaseChance=0.500, ChancePerYear=0.0005 },
    { MinAge=50,  MaxAge=74,  BaseChance=0.020, ChancePerYear=0.0010 },
    { MinAge=75,  MaxAge=150, BaseChance=0.050, ChancePerYear=0.0020 },
}

local JobDeathCauses = {
	MINER       = { BaseChance = 0.002, ChancePerYear = 0.0003, Cause = "Mine Collapse" },
	BUILDER     = { BaseChance = 0.003, ChancePerYear = 0.0002, Cause = "Construction Accident" },
	GATHERER 	= { BaseChance = 0.004, ChancePerYear = 0.0001, Cause = "Snake Bite" },
	HUNTER 		= { BaseChance = 0.005, ChancePerYear = 0.0001, Cause = "Wild Boar Attack" },
	-- placeholder
}

local EventDeathCauses = { -- year, cause, baseChance) -- map also accepts lists
	[1205] = { { Cause = "Great Plague", BaseChance = 1.0 }, { Cause = "Solar Eclipse", BaseChance = 0.1 } },
	[1204] = { Cause = "Great Flood", BaseChance = 0.5 },
}

local function getEventDefsForYear(year)
	local defs = EventDeathCauses[year]
	if not defs then return {} end
	-- if it's a single entry (has a Cause field but not an array), wrap it
	if defs.Cause and defs[1] == nil then return { defs } end
	return defs -- otherwise assume it's already an array
end

-- #################################################
-- # DATA‐TYPE REGISTRATIONS
-- #################################################

mod:registerClass({
	TypeName   = "MortalDeathEntry",
	Properties = {
		{ Name="Name",		Type="string",	Default="",				Flags={"SAVE_GAME"} },
		{ Name="Age",		Type="integer",	Default=0,				Flags={"SAVE_GAME"} },
		{ Name="BornMdY",	Type="string",	Default="",				Flags={"SAVE_GAME"} },
		{ Name="DiedMdY",	Type="string",	Default="",				Flags={"SAVE_GAME"} },
		{ Name="JobTitle",	Type="string",	Default="Unemployed",	Flags={"SAVE_GAME"} },
		{ Name="Cause",		Type="string",	Default="Unknown",		Flags={"SAVE_GAME"} },
		{ Name="Year",		Type="integer",	Default=baseYear,		Flags={"SAVE_GAME"} },
	}
})

	-- ──────────────────────────────────────────────────────────────────────────
							-- COMPONENT MANAGERS
	-- ──────────────────────────────────────────────────────────────────────────

-- #################################################
-- # COMPONENT: COMP_AGE
-- #################################################
local COMP_AGE = {
    TypeName   = "COMP_AGE",
    ParentType = "COMPONENT",
    Properties = {
        { Name="Age",			 Type="float",	 Default=0, 		   Flags={"SAVE_GAME"} },
        { Name="Initialized", 	 Type="boolean", Default=false, 	   Flags={"SAVE_GAME"} },
        { Name="BirthdayDay",	 Type="integer", Default=1, 		   Flags={"SAVE_GAME"} },
        { Name="BirthdayMonth",  Type="integer", Default=1, 		   Flags={"SAVE_GAME"} },
        { Name="YearOfBirth", 	 Type="integer", Default=baseYear,     Flags={"SAVE_GAME"} },
        { Name="IsDead", 		 Type="boolean", Default=false, 	   Flags={"SAVE_GAME"} },
        { Name="DeathYear", 	 Type="integer", Default=0, 		   Flags={"SAVE_GAME"} },
        { Name="DeathDayIndex",  Type="integer", Default=-1, 		   Flags={"SAVE_GAME"} },
        { Name="DeathJob", 		 Type="string",  Default="Unemployed", Flags={"SAVE_GAME"} },
        { Name="DeathCause", 	 Type="string",  Default="Unknown",    Flags={"SAVE_GAME"} },
        { Name="DeathCauseType", Type="string",  Default="Unknown",	   Flags={"SAVE_GAME"} },
    }
}

-- ===============================================================
--- Initialize this age-component (set random age, birthday, yearOfBirth)
-- loop component manager for date info
-- ===============================================================
function COMP_AGE:ensureInitialized(loop)
    if self.Initialized then return end
    self.Initialized = true

    local owner = self:getOwner()
    -- use the fast calendar math
    local year, month, day = getCalendarFast(loop:getDay())
    -- pick a random age and birthday
    local rawAge            = random(Config.MIN_AGE, Config.MAX_AGE)
    local bm, bd            = random(1, monthsPerYear), random(1, daysPerMonth)
    self.BirthdayMonth, self.BirthdayDay = bm, bd
    -- has their birthday passed this year?
    local hasHadBday = (month > bm) or (month == bm and day >= bd)
    self.YearOfBirth     = year - rawAge
    self.Age             = hasHadBday and rawAge or (rawAge - 1)
    -- build the “MORTALIZED” log message
    return format("%s - age %d, born on %s", owner.Name, self.Age, formatMdY(bm, bd, self.YearOfBirth))
end
-- ===============================================================
--- Compute death chance breakdown for this villager
-- loop component manager for date info
-- return ageC, jobC, eventC, totalChance
-- ===============================================================
function COMP_AGE:computeDeathChance(loop)
    local owner = self:getOwner()
    local age   = self.Age

    -- age contribution
    local ageC = 0
    for _, r in ipairs(AgeDeathCauses) do
        if age >= r.MinAge and age <= (r.MaxAge or age) then
            ageC = r.BaseChance + (r.ChancePerYear or 0) * (age - r.MinAge)
            break
        end
    end

    -- job contribution
    local jobC = 0
    local cv = owner:getComponent("COMP_VILLAGER")
    if cv and cv:hasJob() then
        local inst = cv:getJobInstance()
        local jt   = (inst and inst.AssetJob and inst.AssetJob.JobName or ""):upper()
        local def  = JobDeathCauses[jt]
		if def then
                jobC = def.BaseChance + (def.ChancePerYear or 0) * age
        end
    end

	-- event contribution (fixed BaseChance)
	local eventC = 0
	local thisYear = getCurrentYear(loop)
	local eventDefs = getEventDefsForYear(thisYear)
	for _, ev in ipairs(eventDefs) do
		eventC = eventC + (ev.BaseChance or 0)
	end

	-- return all four components plus the total
	return ageC, jobC, eventC, (ageC + jobC + eventC)
end



-- #################################################
-- # COMPONENT: COMP_MORTALITY
-- #################################################
local COMP_MORTALITY = {
    TypeName   = "COMP_MORTALITY",
    ParentType = "COMPONENT",
    Properties = {
		{ Name="GraveyardIndex", Type="integer", Default=0,		Flags={"SAVE_GAME"} },
		{ Name="LastLoggedYear", Type="integer", Default=0,		Flags={"SAVE_GAME"} },
		{ Name="InitialYear", 	 Type="integer", Default=0,		Flags={"SAVE_GAME"} },
		{ Name="Entries",        Type="list<MortalDeathEntry>", Default={},	 Flags={"SAVE_GAME"} },
	}
}

-- ──────────────────────────────────────────────────────────────────────────
-- # COMP_MORTALITY: CREATE
-- ──────────────────────────────────────────────────────────────────────────
function COMP_MORTALITY:create()
	-- init in-memory queues:
	self.pendingMortality = {}
	self.pendingBirthdays = {}
	self.knownDeaths	  = {}
	self.throttleQueue    = {}
	self.throttleIndex    = 1
end

-- ──────────────────────────────────────────────────────────────────────────
-- # COMP_MORTALITY: ENABLED
-- ──────────────────────────────────────────────────────────────────────────
function COMP_MORTALITY:onEnabled()
  -- reset in-memory state; driver will seed the queue
  self.GraveyardIndex   = self.GraveyardIndex or 0
  self.LastLoggedYear   = self.LastLoggedYear   or 0
  self.InitialYear      = self.InitialYear      or 0
  self.throttleQueue    = {}
  self.throttleIndex    = 1
  self.pendingMortality = {}
  self.pendingBirthdays = {}
  self.knownDeaths      = {}
end

-- ──────────────────────────────────────────────────────────────────────────
-- # COMP_MORTALITY: THROTTLE
-- ──────────────────────────────────────────────────────────────────────────
function COMP_MORTALITY:buildThrottleQueue()
  local mgr   = self:getLevel():getComponentManager("COMP_VILLAGER")
  local comps = mgr:getAllEnabledComponent() or {}

  -- “materialize” into a Lua table
  local list = {}
  if comps.forEach then
    comps:forEach(function(c) insert(list, c) end)
  else
    for _, c in ipairs(comps) do insert(list, c) end
  end

  self.throttleQueue = list
  self.throttleIndex = 1
end

-- ──────────────────────────────────────────────────────────────────────────
-- # COMP_MORTALITY: UPDATE - per frame; throttled work
-- ──────────────────────────────────────────────────────────────────────────
function COMP_MORTALITY:update()
	if #self.throttleQueue == 0 then return end

	local endIdx = min(#self.throttleQueue,
                     self.throttleIndex + Config.INIT_CHUNK_SIZE - 1)
	local loop   = self:getLevel():find("COMP_MAIN_GAME_LOOP")

	for i = self.throttleIndex, endIdx do
		local vcomp = self.throttleQueue[i]
		if vcomp then
			local owner = vcomp:getOwner()
			if owner then
				self:processVillager(vcomp, loop)
			else
				mod:logWarning("[Mortality] Skipping dead or invalid component at queue index " .. i)
			end
		end
	end
	self.throttleIndex = endIdx + 1

	if self.throttleIndex > #self.throttleQueue then
	-- we've finished the batch; clear for next reseed
	self.throttleQueue    = {}
	self.throttleIndex    = 1
	self.pendingMortality = {}
	self.pendingBirthdays = {}
	-- **note**: knownDeaths stays intact so the driver can consume it
	end
end

-- ──────────────────────────────────────────────────────────────────────────
-- # COMP_MORTALITY: CORE LOGIC PROCESS
-- ──────────────────────────────────────────────────────────────────────────

function COMP_MORTALITY:processVillager(vcomp, loop) -- Extract the per villager work into one method
	local owner     = vcomp:getOwner()
	local ca        = owner:getOrCreateComponent("COMP_AGE")
	--local compAgent = owner:getComponent("COMP_AGENT")
	
	-- ── INITIALIZE & SKIP DEAD ────────────────────────────────────────────
	local initMsg   = ca:ensureInitialized(loop)
	if initMsg then insert(self.pendingMortality, initMsg) end
	if ca.IsDead then return end
	
	-- ── BIRTHDAY CHECK ─────────────────────────────────────────────────────
	local dayOfYear = getDayOfYear(loop)
	local bidx      = getBirthdayDayOfYear(ca)
	local weekStart = dayOfYear 
	local weekEnd   = dayOfYear + daysPerWeek - 1  -- or +6

	local hitBirthday
	if weekEnd < daysPerYear then
		-- simple case: stays within this year
		hitBirthday = (bidx >= weekStart and bidx <= weekEnd)
	else
		-- wraps past year-end: either at tail or head of year
		hitBirthday = (bidx >= weekStart) or (bidx <= (weekEnd % daysPerYear))
	end

	if hitBirthday then
		ca.Age = ca.Age + 1
		local birthStr = (Config.DATE_STYLE == "Standard")
			and formatMd(ca.BirthdayMonth, ca.BirthdayDay)
			or formatBirth({
				BirthdayMonth = ca.BirthdayMonth,
				BirthdayDay   = ca.BirthdayDay,
				YearOfBirth   = getCurrentYear(loop)
			}, Config.DATE_STYLE)
		insert(self.pendingBirthdays,
			format("%s turns %d on %s", owner.Name, ca.Age, birthStr))
    end
	
	-- ── DEATH CHECK ────────────────────────────────────────────────────────
	local ageC, jobC, eventC, total = ca:computeDeathChance(loop)
	if random() < total then
		-- determine when in the past week they die (logs & archives)
		local offset          = random(0, 6)
		local deathDayOfYear  = (dayOfYear - offset + daysPerYear) % daysPerYear

		-- mark component fields
		ca.IsDead        = true -- mark so we skip them next week
		ca.DeathDayIndex = deathDayOfYear

		 -- capture actual job live & pretty-format
		local cv     	= owner:getComponent("COMP_VILLAGER")
		local jobKey  = (cv and cv:hasJob() and cv:getAssetJob().JobName:upper()) or ""
		local prettyJob = (jobKey ~= "")
		  and (jobKey:sub(1,1) .. jobKey:sub(2):lower())
		  or "None"
		ca.DeathJob = prettyJob

		-- pick dominant cause
		local causeString
		if ageC  >= jobC and ageC  >= eventC then
			ca.DeathCauseType = "Age"
			causeString       = "Natural Causes"

		elseif jobC  >= ageC and jobC  >= eventC then
			ca.DeathCauseType = "Job"
			local jd          = JobDeathCauses[jobKey]
			causeString       = (jd and jd.Cause) or "Job Hazard"
		else
			ca.DeathCauseType = "Event"
			local defs        = getEventDefsForYear(ca.DeathYear)
			local causes      = {}
			for _, ev in ipairs(defs) do insert(causes, ev.Cause) end
			causeString       = concat(causes, " & ")
		end
		ca.DeathCause = causeString or "Unknown"

		-- compute absolute indices, then adjust if wrapped
		local startAbs = loop:getDay() - dayOfYear
		if deathDayOfYear > dayOfYear then
			startAbs = startAbs - daysPerYear
		end
		local deathAbsIdx = startAbs + deathDayOfYear
		local birthAbsIdx = (ca.YearOfBirth - baseYear) * daysPerYear + getBirthdayDayOfYear(ca)

		local bornMdY = getFullDateString(birthAbsIdx, Config.DATE_STYLE)
		local diedMdY = getFullDateString(deathAbsIdx, Config.DATE_STYLE)
		
		-- recompute death-year from the corrected absolute index
		local dY, dM, dD = getCalendarFast(deathAbsIdx)
		ca.DeathYear = dY
		local hadBday = (dM > ca.BirthdayMonth)	or (dM == ca.BirthdayMonth and dD >= ca.BirthdayDay)
		local ageAtDeath = dY - ca.YearOfBirth - (hadBday and 0 or 1)

		 -- archive data (use computed ageAtDeath)
		local entry = {
			name      = owner.Name,
			age       = ageAtDeath,
			bornMdY   = bornMdY,
			diedMdY   = diedMdY,
			jobTitle  = ca.DeathJob or "None",
			cause     = ca.DeathCause or "Unknown",
			year      = ca.DeathYear or getCurrentYear(loop),
		}
		-- archive to yearly summary; pass the owner so the driver can bury later
		self:recordDeath(entry, owner) -- archive to yearly summary
	end
end

-- ──────────────────────────────────────────────────────────────────────────
-- # COMP_MORTALITY: AUTOPSY
-- ──────────────────────────────────────────────────────────────────────────
function COMP_MORTALITY:recordDeath(d, owner)
	-- guard: don’t record the same death twice
	for _, e in ipairs(self.Entries) do
		if e.Name		== d.name
		and e.Year		== d.year
		and e.BornMdY	== d.bornMdY
		and e.DiedMdY	== d.diedMdY
		then return	end
	end
	-- assign a slot index
	local idx = self.GraveyardIndex or 0
	self.GraveyardIndex = idx + 1

	-- persist the data object unmodified
	local dataObj = foundation.createData{ DataType="MortalDeathEntry", 
		Name		= d.name,
		Age			= d.age,
		BornMdY		= d.bornMdY,
		DiedMdY		= d.diedMdY,
		JobTitle	= d.jobTitle,
		Cause		= d.cause,
		Year		= d.year }
	insert(self.Entries, dataObj)
	
	-- record only minimal
	insert(self.knownDeaths, {
		owner		= owner,
		graveIndex	= idx,
		name		= d.name,
		bornMdY		= d.bornMdY,
		diedMdY		= d.diedMdY,
		jobTitle	= d.jobTitle,
		cause		= d.cause,
	})
end

-- #################################################
-- # HOOK EXTERNAL API ONTO COMPONENT
-- #################################################
local CM = COMP_MORTALITY

CM.getDeathCount		= MF.getDeathCount
CM.getYearlyArchive		= MF.getYearlyArchive
CM.getYearlyAverage		= MF.getYearlyAverage
CM.getAverageLifespan	= MF.getAverageLifespan

-- #################################################
-- # REGISTER CLASSES
-- #################################################
mod:registerClass(COMP_AGE)
mod:registerClass(COMP_MORTALITY)
mod:registerPrefabComponent("PREFAB_MANAGER", { DataType="COMP_MORTALITY", Enabled=true })

mod:log(format("[Mortal Framework BETA v%s] Initialized successfully.", MF.VERSION))
