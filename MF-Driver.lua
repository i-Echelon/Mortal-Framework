local MF     = MortalFramework
local C      = MF.Constants
local mod    = MF.mod

-- #################################################
-- # CONFIG: Mausoleum & Fallback Grave Settings
-- #################################################
local Config = {
  -- Fallback corner of map when mausoleum is full or missing
  FallbackX                = 1000,
  FallbackY                = 0.5,
  FallbackZ                = 1,
  -- Anchor building name (AssetBuilding.Name)
  AnchorBuildingName       = "RUSTIC_CHURCH",
  -- Distance from mausoleum center to graves
  MausoleumOffsetDistance  = 20,
  -- Maximum graves per mausoleum
  MaxGravesPerMausoleum    = 60,
}

-- #################################################
-- # COMPONENT: COMP_MORTALITY_DRIVER
-- #################################################
local COMP_MORTALITY_DRIVER = {
  TypeName   = "COMP_MORTALITY_DRIVER",
  ParentType = "COMPONENT",
  Properties = {
    { Name = "FallbackX", Type = "float", Default = Config.FallbackX },
    { Name = "FallbackY", Type = "float", Default = Config.FallbackY },
    { Name = "FallbackZ", Type = "float", Default = Config.FallbackZ },
  },
}

-- ────────────────────────────────────────────────────────────
-- # onEnabled: initialize counters & hooks
-- ────────────────────────────────────────────────────────────
function COMP_MORTALITY_DRIVER:onEnabled()
  self._mgr               = self:getLevel():getComponentManager("COMP_MORTALITY"):getFirstEnabled()
  self._mausoleumCounts   = {}  -- track graves placed per mausoleum
  local loop = self:getLevel():find("COMP_MAIN_GAME_LOOP")
  local mgr  = self._mgr
  if not (loop and mgr) then return end

  mgr:buildThrottleQueue()
  backfillAges(mgr, loop)

  -- Weekly: birthdays + deaths + burial
  self._weekHandle = event.register(self, loop.ON_NEW_WEEK, function()
    mgr:buildThrottleQueue()
    mgr:update()
    -- reset weekly birthdays
    formatList("[HAPPY BIRTHDAY]", mgr.pendingBirthdays)
    mgr.pendingBirthdays = {}
    -- process deaths
    local deathLines = {}
    for _, rec in ipairs(mgr.knownDeaths) do
      table.insert(deathLines, string.format(
        "R.I.P. %s | BORN: %s | DIED: %s | JOB: %s | CAUSE: %s",
        rec.name, rec.bornMdY, rec.diedMdY, rec.jobTitle, rec.cause
      ))
      if rec.owner then
        local ag = rec.owner:getComponent("COMP_AGENT")
        if ag and not ag.IsDying then ag:die() end
        self:buryVillager(rec.owner, rec.graveIndex)
      else
        mod:logWarning(string.format("Skipping burial: nil owner for '%s'", rec.name))
      end
    end
    formatList("[DEATH REPORT]", deathLines)
    mgr.knownDeaths = {}
  end)

  -- Monthly: yearly summary rollover
  self._yearHandle = event.register(self, loop.ON_NEW_MONTH, function()
    local y = getCurrentYear(loop)
    if y > mgr.LastLoggedYear then
      mod:log(string.format("HAPPY NEW YEAR %d!", y))
      if MF.Config.YEARLY_SUMMARY then self:printSummary(mgr.LastLoggedYear) end
      mgr.LastLoggedYear = y
    end
  end)
end

-- ────────────────────────────────────────────────────────────
-- # onDisabled: cleanup
-- ────────────────────────────────────────────────────────────
function COMP_MORTALITY_DRIVER:onDisabled()
  if self._weekHandle then event.unregister(self._weekHandle) end
  if self._yearHandle then event.unregister(self._yearHandle) end
end

-- ────────────────────────────────────────────────────────────
-- # buryVillager: mausoleum or fallback
-- ###########################################################
function COMP_MORTALITY_DRIVER:buryVillager(owner, idx)
  if not owner then return end
  local level = self:getLevel()

  -- find the mausoleum building component
  local anchorComp
  level:getComponentManager("COMP_BUILDING"):getAllEnabledComponent():forEach(function(c)
    if c.AssetBuilding and c.AssetBuilding.Name == Config.AnchorBuildingName then
      anchorComp = c
    end
  end)

  -- determine burial location
  if anchorComp then
    -- track graves placed for this mausoleum
    local buildingObj = anchorComp:getOwner()
	-- key by the building *instance* so it’s stable
	local count = self._mausoleumCounts[buildingObj] or 0
    if count < Config.MaxGravesPerMausoleum then
      -- place next grave around center in 270° arc (excluding front)
      local angleStart = math.rad(45)
      local angleArc   = math.rad(270)
      local angle      = angleStart + (count * angleArc / Config.MaxGravesPerMausoleum)
      local cosA, sinA = math.cos(angle), math.sin(angle)
      local pos        = buildingObj:getGlobalPosition()
      local gx = pos[1] + cosA * Config.MausoleumOffsetDistance
      local gz = pos[3] + sinA * Config.MausoleumOffsetDistance
      -- drop to ground
      local hit = {}
      local gy = pos[2]
      if level:rayCast({gx,1000,gz}, {gx,-1000,gz}, hit) then gy = hit.Position[2] end
      -- teleport grave
      owner:setGlobalPosition{ gx, gy + 0.5, gz }
      mod:log(string.format("[MAUSOLEUM] Grave %d of %d @ %.1f, %.1f", count+1, Config.MaxGravesPerMausoleum, gx, gz))
      self._mausoleumCounts[buildingObj] = count + 1
      return
    end
    -- else mausoleum full -> fall through to fallback
  end
  
	-- fallback: now use idx to lay out the old corner graves in a 10×grid:
    local gx = Config.FallbackX + (idx % 10) * 2.5
    local gz = Config.FallbackZ + math.floor(idx/10) * 2.5
    local hit, gy = {}, Config.FallbackY
    if level:rayCast({gx,1000,gz}, {gx,-1000,gz}, hit) then gy = hit.Position[2] end
    owner:setGlobalPosition{ gx, gy + 0.5, gz }
    mod:log(string.format("[FALLBACK] Grave @ %.1f, %.1f", gx, gz))
  end

-- ────────────────────────────────────────────────────────────
-- # METHOD: Print Yearly Summary
-- ────────────────────────────────────────────────────────────
function COMP_MORTALITY_DRIVER:printSummary(reportYear)
  local mgr = self._mgr
  if not mgr then return end

  local entries = {}
  for _, e in ipairs(mgr.Entries) do
    if e.Year == reportYear then table.insert(entries, e) end
  end
  if #entries == 0 then return end

  local avgLife = MF.getYearlyAverage(mgr, reportYear)
  local header  = string.format(
    "=== Year %d Summary ===\nAverage Lifespan: %.2f years\n",
    reportYear, avgLife
  )
  local deaths = formatDeathTable(entries)
  local causes = formatCauseSummary(entries)
  local text   = header .. deaths .. "\n\n" .. causes

  if MF.Config.SAVE_SUMMARY_TO_FILE then
    saveSummaryFile(mod, MF.Config.ARCHIVE_SAVE_LABEL, reportYear, text)
  end
  debugLog("\n" .. text)
end


-- ────────────────────────────────────────────────────────────
-- # REGISTER & ATTACH
-- ────────────────────────────────────────────────────────────
mod:registerClass(COMP_MORTALITY_DRIVER)
mod:registerPrefabComponent("PREFAB_MANAGER", {
  DataType = "COMP_MORTALITY_DRIVER",
  Enabled  = true
})