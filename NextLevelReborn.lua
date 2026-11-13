-- NextLevelReborn Forever 2.1.1
-- WoW Forever build: Interface 16001, level cap 60, Classic XP curve (4,084,700 total to 60).
-- Remake of Nextlevel - Classic (WoWInterface, 2019-09-20, Classic 1.13.2)
-- Original idea: after any XP or reputation gain, print how many more
-- gains like that one you need to level up / reach the next standing.
--
-- Forever build, derived from the Midnight / Season 2 (12.1.5, Interface 120105) rebuild:
-- * NO Combat Log. The original Classic version could lean on combat-log
--   XP lines; in Midnight COMBAT_LOG_EVENT_UNFILTERED and
--   CombatLogGetCurrentEventInfo() are gone for addons. This version never
--   touches them. XP is read from UnitXP() / UnitXPMax() on
--   PLAYER_XP_UPDATE, rep from GetFactionInfo() on UPDATE_FACTION plus
--   CHAT_MSG_COMBAT_FACTION_CHANGE for the exact gain amount.
-- * XP and reputation are NOT secret values outside instanced combat, so
--   UnitXP, UnitXPMax, GetXPExhaustion and GetFactionInfo still work.
--   Nothing here reads health, damage, cooldowns or auras in combat.
-- * No GetSpellInfo / other pre-C_ globals. No LibStub / Ace. Lua 5.1 only.
-- * Level cap is 90 in Midnight (was 60 in Classic). At 90 the XP half
--   auto-disables and only the rep / Renown half runs.
-- * Forever rep is Classic standings (Hated to Exalted), no Renown. The same generic ladder math covers it.
-- * Midnight rep is mostly Renown (account / Warband-shared, cap 20,
--   Paragon after 20), not the old 0-42000 standing ladder. The math below
--   is generic on bottomValue / topValue / earnedValue, so it works for
--   both: Renown steps are normally 2500 rep, classic standings keep
--   their own thresholds.
-- * Quest XP in 80-90 is huge vs kill XP (a dungeon quest is 85-90k,
--   a level-89 level costs 592,980). A single "last gain" number lies.
--   So kills and other gains are tracked separately, with a rolling
--   average of the last 10 kills.

local ADDON = "NextLevelReborn"
local PREFIX = "|cff33ff99NLR|r: "

local defaults = {
  xp = true,
  rep = true,
  xpPerHour = true,
  verbose = false, -- true: also print the raw +gain and % each time
}

local db = defaults
local f = CreateFrame("Frame")

-- Session state
local lastXP, lastMaxXP
local sessionXP, sessionStart = 0, nil
local killGains = {} -- rolling last 10 kill XP values
local lastKillXP, lastOtherXP = 0, 0
local lastKillChatAt = 0 -- GetTime() of last CHAT_MSG_COMBAT_XP_GAIN
local factionCache = {} -- [factionName] = earnedValue

-- ---------------------------------------------------------------- helpers
local function msg(text)
  DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. text)
end

local function fmt(n)
  -- 592980 -> "592,980"
  n = math.floor(n + 0.5)
  local s = tostring(n)
  local out = ""
  while #s > 3 do
    out = "," .. s:sub(-3) .. out
    s = s:sub(1, -4)
  end
  return s .. out
end

local function avg(t)
  if #t == 0 then return 0 end
  local sum = 0
  for i = 1, #t do sum = sum + t[i] end
  return sum / #t
end

local function pushKill(xp)
  table.insert(killGains, xp)
  if #killGains > 10 then table.remove(killGains, 1) end
  lastKillXP = xp
end

local function standingName(id)
  -- FACTION_STANDING_LABEL1..8 are globals: Hated .. Exalted
  local label = _G["FACTION_STANDING_LABEL" .. tostring(id)]
  return label or ("Standing " .. tostring(id))
end

local MAX_LEVEL = 60 -- Forever cap, permanently. Do not use MAX_PLAYER_LEVEL_TABLE here: Forever runs on the modern client, so the expansion table does not mean 60.

local function isMaxLevel()
  return UnitLevel("player") >= MAX_LEVEL
end

-- ---------------------------------------------------------------- XP
local function onXPUpdate()
  if not db.xp then return end
  if IsXPUserDisabled() then return end
  if isMaxLevel() then return end

  local cur = UnitXP("player")
  local max = UnitXPMax("player")
  if not cur or not max or max <= 0 then return end

  if not lastXP then
    lastXP, lastMaxXP = cur, max
    return
  end

  local gained
  if cur >= lastXP then
    gained = cur - lastXP
  else
    -- Leveled up: remainder of old level + XP into the new one.
    -- lastMaxXP is the cost of the level we just finished.
    gained = (lastMaxXP - lastXP) + cur
  end
  lastXP, lastMaxXP = cur, max

  if gained <= 0 then return end
  sessionXP = sessionXP + gained

  local remaining = max - cur
  if remaining <= 0 then return end

  -- Kill vs everything else: a combat-XP chat line ~just before this
  -- update means the gain was a kill. Anything else (quest turn-in,
  -- exploration, Delve / Prey / dungeon bonus) is "other".
  local isKill = (GetTime() - lastKillChatAt) < 1.0
  if isKill then
    pushKill(gained)
  else
    lastOtherXP = gained
  end

  local killAvg = avg(killGains)
  local parts = {}

  if db.verbose then
    table.insert(parts, "+" .. fmt(gained) .. " XP (" .. fmt(cur) .. "/" .. fmt(max) .. ", " .. math.floor(cur / max * 100 + 0.5) .. "%)")
  end

  if isKill and gained > 0 then
    table.insert(parts, fmt(math.ceil(remaining / gained)) .. " more kills like that to level")
  elseif lastOtherXP > 0 then
    table.insert(parts, fmt(math.ceil(remaining / lastOtherXP)) .. " more gains like that to level")
  end

  -- The useful number while grinding: rolling kill average, not the
  -- one-off quest that just landed.
  if killAvg > 0 and not isKill then
    table.insert(parts, fmt(math.ceil(remaining / killAvg)) .. " kills at your recent average (" .. fmt(killAvg) .. " XP/kill)")
  elseif killAvg > 0 and isKill and #killGains > 1 then
    table.insert(parts, "avg " .. fmt(killAvg) .. " XP/kill")
  end

  if db.xpPerHour and sessionStart then
    local elapsed = GetTime() - sessionStart
    if elapsed > 60 then
      local perHour = sessionXP / elapsed * 3600
      if perHour > 0 then
        local secs = remaining / perHour * 3600
        local h = math.floor(secs / 3600)
        local m = math.floor((secs % 3600) / 60)
        table.insert(parts, fmt(perHour) .. " XP/hr, ~" .. h .. "h " .. m .. "m to level")
      end
    end
  end

  -- Rested: GetXPExhaustion() is bonus XP banked, not XP in the bar.
  local rested = GetXPExhaustion()
  if rested and rested > 0 and db.verbose then
    table.insert(parts, "rested " .. fmt(rested) .. " XP banked")
  end

  if #parts > 0 then
    msg(table.concat(parts, "  |  "))
  end
end

-- ---------------------------------------------------------------- Reputation
local function scanFactions()
  -- Snapshot every visible faction so UPDATE_FACTION diffs have a baseline.
  -- GetFactionInfo(index) returns: name, description, standingId,
  -- bottomValue, topValue, earnedValue, atWarWith, canToggleAtWar,
  -- isHeader, isCollapsed, hasRep, isWatched, isChild
  for i = 1, GetNumFactions() do
    local name, _, _, _, _, earned = GetFactionInfo(i)
    if name and earned then
      factionCache[name] = earned
    end
  end
end

local function reportRepGain(name, gained)
  if not db.rep then return end
  if not name or not gained or gained == 0 then return end

  -- Find this faction's current ladder position.
  for i = 1, GetNumFactions() do
    local fname, _, standingId, bottom, top, earned = GetFactionInfo(i)
    if fname == name and earned then
      factionCache[name] = earned
      local remaining, target
      if gained > 0 then
        remaining = top - earned
        target = standingName(standingId + 1)
        -- At Exalted / Renown 20 the ladder tops out; top == earned
        -- means Paragon progress instead, which still has a topValue.
        if remaining <= 0 then
          -- Paragon / maxed: just report the gain, no "to next" math.
          msg(name .. ": +" .. fmt(gained) .. " rep (max standing, Paragon progress)")
          return
        end
      else
        -- Losing rep: how much further to drop a standing.
        remaining = earned - bottom
        target = standingName(standingId - 1)
        if remaining <= 0 then
          msg(name .. ": " .. fmt(gained) .. " rep (lowest standing)")
          return
        end
      end

      local needed = math.ceil(remaining / math.abs(gained))
      local dir = gained > 0 and "more gains like that to " or "more losses like that to "
      msg(name .. ": " .. (gained > 0 and "+" or "") .. fmt(gained) .. " rep  |  " .. fmt(needed) .. dir .. target .. " (" .. fmt(remaining) .. " to go)")
      return
    end
  end

  -- Faction not in the visible list (collapsed header etc.): no ladder,
  -- still report the gain so it isn't silently lost.
  msg(name .. ": " .. (gained > 0 and "+" or "") .. fmt(gained) .. " rep")
end

local function onFactionUpdate()
  if not db.rep then return end
  for i = 1, GetNumFactions() do
    local name, _, _, _, _, earned = GetFactionInfo(i)
    if name and earned then
      local old = factionCache[name]
      if old and earned ~= old then
        reportRepGain(name, earned - old)
      end
      factionCache[name] = earned
    end
  end
end

-- ---------------------------------------------------------------- Events
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_XP_UPDATE")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:RegisterEvent("UPDATE_FACTION")
f:RegisterEvent("UPDATE_EXHAUSTION")
f:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
f:RegisterEvent("CHAT_MSG_COMBAT_FACTION_CHANGE")

f:SetScript("OnEvent", function(self, event, arg1, ...)
  if event == "PLAYER_ENTERING_WORLD" then
    if not sessionStart then
      sessionStart = GetTime()
      lastXP, lastMaxXP = UnitXP("player"), UnitXPMax("player")
      scanFactions()
      if isMaxLevel() then
        msg("loaded for level 60: XP tracking off, reputation tracking on. /nlr for options.")
      else
        msg("loaded: kill a mob or turn in a quest and I will tell you how many more to level. /nlr for options.")
      end
    end
  elseif event == "PLAYER_XP_UPDATE" then
    onXPUpdate()
  elseif event == "PLAYER_LEVEL_UP" then
    -- PLAYER_XP_UPDATE already did the wrap math; just celebrate + reset.
    local level = arg1
    sessionXP = 0
    sessionStart = GetTime()
    killGains = {}
    lastKillXP, lastOtherXP = 0, 0
    lastXP, lastMaxXP = UnitXP("player"), UnitXPMax("player")
    msg("Level " .. tostring(level) .. "! Counters reset for the new level.")
  elseif event == "UPDATE_FACTION" then
    onFactionUpdate()
  elseif event == "UPDATE_EXHAUSTION" then
    -- Rested changed; nothing to print unless verbose XP fires next gain.
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    -- "You gain 250 experience." Marks the next PLAYER_XP_UPDATE as a kill.
    lastKillChatAt = GetTime()
  elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
    -- "Your reputation with Silvermoon Court has increased by 250."
    -- Parse the exact gain; UPDATE_FACTION diff is the fallback.
    -- arg1 is the localized chat line, so match numbers, not English words
    -- where possible: the faction name is between "with " and " has" in
    -- enUS; other locales fall back to the UPDATE_FACTION diff above.
    if arg1 then
      local gain = tonumber(arg1:match("by (%d+)"))
      local loss = tonumber(arg1:match("decreased by (%d+)"))
      local name = arg1:match("with (.+) has increased")
        or arg1:match("with (.+) has decreased")
      if name and (gain or loss) then
        -- Only report here if the cache hasn't already caught this exact
        -- change; onFactionUpdate will skip it because earned == cached.
        local old = factionCache[name]
        if old then
          -- Let UPDATE_FACTION do the reporting to avoid double messages;
          -- this event just primes the cache check. No-op by design.
        else
          reportRepGain(name, gain and gain or -loss)
        end
      end
    end
  end
end)

-- ---------------------------------------------------------------- Slash commands
SLASH_NEXTLEVELREBORN1 = "/nlr"
SLASH_NEXTLEVELREBORN2 = "/nextlevel"
SlashCmdList["NEXTLEVELREBORN"] = function(input)
  input = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if input == "" or input == "help" then
    msg("Commands: /nlr xp | /nlr rep | /nlr xp/hr | /nlr verbose | /nlr status | /nlr reset")
    msg("XP and rep messages print after each gain. At level 60 only rep runs.")
    return
  end
  if input == "xp" then
    db.xp = not db.xp
    msg("XP messages " .. (db.xp and "on" or "off") .. ".")
  elseif input == "rep" then
    db.rep = not db.rep
    msg("Reputation messages " .. (db.rep and "on" or "off") .. ".")
  elseif input == "xp/hr" or input == "xphr" then
    db.xpPerHour = not db.xpPerHour
    msg("XP/hr estimate " .. (db.xpPerHour and "on" or "off") .. ".")
  elseif input == "verbose" then
    db.verbose = not db.verbose
    msg("Verbose " .. (db.verbose and "on" or "off") .. " (prints raw +gain, %, rested).")
  elseif input == "status" then
    local cur, max = UnitXP("player"), UnitXPMax("player")
    msg("Level " .. UnitLevel("player") .. ", XP " .. fmt(cur) .. "/" .. fmt(max) .. ", session +" .. fmt(sessionXP) .. " XP, kill avg " .. fmt(avg(killGains)) .. " (" .. #killGains .. " kills tracked).")
  elseif input == "reset" then
    sessionXP = 0
    sessionStart = GetTime()
    killGains = {}
    lastKillXP, lastOtherXP = 0, 0
    scanFactions()
    msg("Session counters reset.")
  else
    msg("Unknown option '" .. input .. "'. Try /nlr help")
  end
end

-- ---------------------------------------------------------------- SavedVariables
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
  if name == "NextLevelReborn" then
    if type(NextLevelRebornDB) == "table" then
      for k, v in pairs(defaults) do
        if NextLevelRebornDB[k] == nil then NextLevelRebornDB[k] = v end
      end
      db = NextLevelRebornDB
    else
      NextLevelRebornDB = db
    end
    loader:UnregisterEvent("ADDON_LOADED")
  end
end)
