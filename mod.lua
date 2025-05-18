-- MortalFramework - Entrypoint
MortalFramework = MortalFramework or {}
local MF        = MortalFramework

MF.VERSION = "4.4.0.7"

-- ──────────────────────────────────────────────
-- # CONFIGURATION & CONSTANTS
-- ──────────────────────────────────────────────
MF.Config = {
	DEBUG_MODE				= true,
	DATE_STYLE				= "Standard", -- "Fantasy", "Julian", or "Standard"
	ENABLE_BIRTHDAYS		= true, -- toggle birthday checks
	ENABLE_MORTALITY		= true, -- toggle death checks
	ENABLE_WEEKLY_LOG		= true, -- optional “Week X” stamp
	MIN_AGE					= 19,
	MAX_AGE					= 24,
	YEARLY_SUMMARY			= true,
	SAVE_SUMMARY_TO_FILE	= true,
	ARCHIVE_SAVE_LABEL		= "Save_Name",
	INIT_CHUNK_SIZE			= 20, -- how many villagers to init per tick/week
	DEBUG_AGE_CHECK			= true,
}

MF.Constants = {
	BASE_YEAR       = 1200, --starting year Anno Domino
	DAYS_PER_WEEK   = 7,
	MONTHS_PER_YEAR = 12,
	DAYS_PER_MONTH  = 28,
}

MF.Constants.DAYS_PER_YEAR =
	MF.Constants.MONTHS_PER_YEAR *
		MF.Constants.DAYS_PER_MONTH
-- ──────────────────────────────────────────────────────────────────────────
local mod = foundation.createMod();
MF.mod = mod

mod:log(string.format("[Mortal Framework] v%s initializing...", MF.VERSION))
-- LOAD MODULES
mod:dofile("MF-Utility.lua")
mod:dofile("MF-Internal.lua")
mod:dofile("MF-External.lua")

mod:log(string.format("[Mortal Framework v%s] All Modules loaded successfully.", MF.VERSION))
-- ──────────────────────────────────────────────────────────────────────────
-- = OVERRIDES
-- =============
local SPEED_HACK           = true
local SPEED_HACK_DURATION  = 6
local FAMILY_BOOST         = true
local FAMILY_BOOST_SIZE    = 50

if SPEED_HACK then mod:overrideAsset({ Id = "DEFAULT_BALANCING", DayDurationInSeconds = SPEED_HACK_DURATION }) end
if FAMILY_BOOST then mod:overrideAsset({ Id = "DEFAULT_BALANCING", InitialFamilyCount = FAMILY_BOOST_SIZE }) end
-- ──────────────────────────────────────────────────────────────────────────
--test driver mod
mod:dofile("MF-Driver.lua")
--mod:dofile("Test-Driver.lua")