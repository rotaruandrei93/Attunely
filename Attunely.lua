-- Attunely 1.0 - Vanilla 1.12.1 / Turtle WoW / Capycraft
-- Everyone in the guild needs this addon installed for the data to show up.

local PREFIX = "ATTUNE"

-- pfQuest defines a stub global "pfUI" even when pfUI is disabled, so only use pfUI
-- styling when the real addon is loaded (set in the events below)
local pfUI = nil
local T = {}
local function InitTheme()
  if pfUI then
    T = {
      btnH = 22, showW = 110, botW = 90, searchH = 22, searchY = -32, searchW = 140, clrW = 22, slY = -38,
      fN = "GameFontNormalSmall", fH = "GameFontHighlightSmall", fD = "GameFontDisableSmall",
      extraH = 60, statusY = 40, postY = 12, postX = -14, closeOff = -4,
      pTx = 12, pTy = -10, pInfoX = 12, pInfoY = 10, pRowX = 12, pRowY = -28, pRowH = 14, pH = 50,
    }
  else
    T = {
      btnH = 24, showW = 130, botW = 120, searchH = 24, searchY = -31, searchW = 150, clrW = 28, slY = -37,
      fN = "GameFontNormal", fH = "GameFontHighlight", fD = "GameFontDisable",
      extraH = 66, statusY = 46, postY = 16, postX = -18, closeOff = -8,
      pTx = 18, pTy = -16, pInfoX = 18, pInfoY = 14, pRowX = 18, pRowY = -36, pRowH = 16, pH = 66,
    }
  end
end
local function DetectPfUI()
  if IsAddOnLoaded and IsAddOnLoaded("pfUI") then pfUI = getglobal("pfUI") else pfUI = nil end
  InitTheme()
end

-- ===== EDIT HERE to add/change attunements =====
-- item  = exact item name that proves the attunement (bags, bank or equipped)
-- quest = exact quest title; recorded automatically when YOU turn it in
-- qid   = quest ID, used to auto-detect past turn-ins (server list, pfQuest, Questie)
local RAIDS = {
  { key = "ony", label = "Onyxia",             item  = "Drakefire Amulet" },
  { key = "mc",  label = "Molten Core",        quest = "Attunement to the Core", qid = 7848 },
  { key = "bwl", label = "Blackwing Lair",     quest = "Blackhand's Command", qid = 7761 },
  { key = "es",  label = "Emerald Sanctum",    item  = "Gemstone of Ysera" },
  { key = "nax", label = "Naxxramas",          quest = "The Dread Citadel - Naxxramas", qid = 9121 },
  { key = "kut", label = "Upper Karazhan Tower Key", item  = "Upper Karazhan Tower Key" },
  { key = "ksm", label = "Karazhan Scepter",   item  = "Scepter of Medivh" },
}
-- ===============================================

-- Guild rank index allowed to use set/unset (0 = Guild Master, 1 = next rank down, ...).
-- Raise this number if more of your officer ranks should be allowed.
local OFFICER_MAX_RANK = 1

-- raid zone names: being saved to / standing inside one of these proves the attunement
local ZONES = {
  ony = "Onyxia's Lair",
  mc  = "Molten Core",
  bwl = "Blackwing Lair",
  es  = "Emerald Sanctum",
  nax = "Naxxramas",
}

local timers = {}
local replyDist = {}
local ShowStatus
local lastSent = nil
local lastReq = {}
local panel, title, info, rows, labels
local shownName = nil

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffAttune:|r " .. msg)
end

local function MyName() return UnitName("player") end

-- ===== per-character storage =====
-- AttuneDB.chars[charName] = { key = 1, ... }; AttuneDB.me points at the current character's table.
local bound = false
local function BindCharacter()
  local n = UnitName("player")
  if not n or n == "" or n == "Unknown" then return false end
  AttuneDB.chars = AttuneDB.chars or {}
  if not AttuneDB.chars[n] then
    AttuneDB.chars[n] = {}
    if AttuneDB.legacy then
      for k, v in pairs(AttuneDB.legacy) do AttuneDB.chars[n][k] = v end
      AttuneDB.legacy = nil
      Print("Imported your old manual/quest attunements into " .. n .. ". Ask an officer to fix any that are not right for this character.")
    end
  end
  AttuneDB.me = AttuneDB.chars[n]
  bound = true
  return true
end

local function FindRaid(key)
  key = string.lower(key or "")
  for i = 1, getn(RAIDS) do
    if RAIDS[i].key == key then return RAIDS[i] end
  end
  return nil
end


-- ===== officer checks =====
local pendingOverrides = {}

local function IsOfficerSelf()
  if not IsInGuild() then return false end
  local _, _, idx = GetGuildInfo("player")
  return idx ~= nil and idx <= OFFICER_MAX_RANK
end

local function RankOf(name)
  for i = 1, GetNumGuildMembers(true) do
    local n, _, ri = GetGuildRosterInfo(i)
    if n == name then return ri end
  end
  return nil
end

local function Capitalize(n)
  return string.upper(string.sub(n, 1, 1)) .. string.lower(string.sub(n, 2))
end

local function BuildStatus()
  local t = {}
  for i = 1, getn(RAIDS) do
    local v = 0
    if AttuneDB.me[RAIDS[i].key] then v = 1 end
    tinsert(t, RAIDS[i].key .. ":" .. v)
  end
  return table.concat(t, ",")
end

local function ParseStatus(s)
  local d = {}
  for k, v in string.gfind(s, "(%w+):(%d)") do
    d[k] = (v == "1")
  end
  return d
end

local function Send(msg)
  if IsInGuild() then SendAddonMessage(PREFIX, msg, "GUILD") end
end

local function MaybeBroadcast(force)
  local s = BuildStatus()
  if force or s ~= lastSent then
    Send("S~" .. s)
    lastSent = s
  end
end

local function AgeText(secs)
  if secs < 60 then return "just now" end
  if secs < 3600 then return math.floor(secs / 60) .. " min ago" end
  if secs < 86400 then return math.floor(secs / 3600) .. " h ago" end
  return math.floor(secs / 86400) .. " d ago"
end

-- ===== item scanning =====
local function ScanBags(bagList)
  for i = 1, getn(RAIDS) do
    local r = RAIDS[i]
    if r.item and not AttuneDB.me[r.key] then
      local pat = "[" .. r.item .. "]"
      for b = 1, getn(bagList) do
        local bag = bagList[b]
        for slot = 1, GetContainerNumSlots(bag) do
          local link = GetContainerItemLink(bag, slot)
          if link and string.find(link, pat, 1, true) then
            AttuneDB.me[r.key] = 1
          end
        end
      end
    end
  end
end

local function ScanEquipped()
  for i = 1, getn(RAIDS) do
    local r = RAIDS[i]
    if r.item and not AttuneDB.me[r.key] then
      local pat = "[" .. r.item .. "]"
      for slot = 0, 19 do
        local link = GetInventoryItemLink("player", slot)
        if link and string.find(link, pat, 1, true) then
          AttuneDB.me[r.key] = 1
        end
      end
    end
  end
end


-- ===== completed-quest auto-detect (best effort) =====
-- Tries every source that might know about past quest turn-ins.
-- Returns a list of source names that said "completed" for this quest id.
local function QuestDone(id)
  local found = nil
  -- 1) server list, if this client exposes one
  if type(GetQuestsCompleted) == "function" then
    local ok, t = pcall(GetQuestsCompleted)
    if ok and type(t) == "table" and t[id] then found = "server" end
  end
  -- 2) pfQuest history
  local h = getglobal("pfQuest_history")
  if type(h) == "table" and h[id] then found = found or "pfQuest" end
  -- 3) Questie (several versions store it in different places)
  local q = getglobal("Questie")
  if type(q) == "table" and type(q.db) == "table" and type(q.db.char) == "table"
     and type(q.db.char.complete) == "table" and q.db.char.complete[id] then
    found = found or "Questie"
  end
  local qc = getglobal("QuestieCompletedQuests")
  if type(qc) == "table" and qc[id] then found = found or "Questie" end
  local qs = getglobal("QuestieSeenQuests")
  if type(qs) == "table" and qs[id] == 1 then found = found or "Questie" end
  return found
end


-- resolve quest IDs from a title using pfQuest's own database (handles Turtle-specific IDs)
local idCache = {}
local function IdsForTitle(title)
  if idCache[title] then return idCache[title] end
  local ids = {}
  local db = getglobal("pfDB")
  if type(db) == "table" and type(db["quests"]) == "table" then
    for _, sub in pairs(db["quests"]) do
      if type(sub) == "table" then
        for id, v in pairs(sub) do
          if type(id) == "number" and type(v) == "table" and v["T"] == title then
            ids[id] = true
          end
        end
      end
    end
  end
  idCache[title] = ids
  return ids
end

local function QuestDoneAny(r)
  local src = r.qid and QuestDone(r.qid)
  if src then return src, r.qid end
  if r.quest then
    for id in pairs(IdsForTitle(r.quest)) do
      src = QuestDone(id)
      if src then return src, id end
    end
  end
  return nil
end

local function ScanQuests(quiet)
  if type(QueryQuestsCompleted) == "function" then pcall(QueryQuestsCompleted) end
  for i = 1, getn(RAIDS) do
    local r = RAIDS[i]
    if r.quest and not AttuneDB.me[r.key] then
      local src = QuestDoneAny(r)
      if src then
        AttuneDB.me[r.key] = 1
        if not quiet then Print(r.label .. " attunement found via " .. src .. ".") end
      end
    end
  end
end

local function ScanZone()
  local z = GetRealZoneText()
  if not z then return end
  for key, name in pairs(ZONES) do
    if z == name and not AttuneDB.me[key] then
      AttuneDB.me[key] = 1
      local r = FindRaid(key)
      Print((r and r.label or key) .. " attunement recorded (you are inside).")
    end
  end
end

local function ScanLockouts()
  if not GetNumSavedInstances then return end
  for i = 1, GetNumSavedInstances() do
    local name = GetSavedInstanceInfo(i)
    if name then
      for key, zone in pairs(ZONES) do
        if name == zone and not AttuneDB.me[key] then
          AttuneDB.me[key] = 1
          local r = FindRaid(key)
          Print((r and r.label or key) .. " attunement found (you have a raid lockout).")
        end
      end
    end
  end
end

local function ScanAll()
  ScanBags({-2, 0, 1, 2, 3, 4})  -- -2 = keyring
  ScanEquipped()
  ScanQuests(false)
  ScanZone()
  ScanLockouts()
end

-- ===== quest turn-in hook =====
local origGetQuestReward = GetQuestReward
GetQuestReward = function(choice)
  local qtitle = GetTitleText()
  origGetQuestReward(choice)
  if qtitle and AttuneDB then
    for i = 1, getn(RAIDS) do
      local r = RAIDS[i]
      if r.quest and qtitle == r.quest and not AttuneDB.me[r.key] then
        AttuneDB.me[r.key] = 1
        Print(r.label .. " attunement recorded.")
        timers.scan = GetTime() + 2
      end
    end
  end
end

-- ===== guild panel =====
local function Refresh()
  if not panel then return end
  local sel = GetGuildRosterSelection()
  if not sel or sel < 1 then return end
  local name = GetGuildRosterInfo(sel)
  if not name then return end
  title:SetText(name)
  local d, t
  if name == MyName() then
    d = ParseStatus(BuildStatus())
  elseif AttuneDB.cache[name] then
    d = AttuneDB.cache[name].d
    t = AttuneDB.cache[name].t
  end
  for i = 1, getn(RAIDS) do
    if not d then
      rows[i]:SetText("|cff888888?|r")
    elseif d[RAIDS[i].key] then
      rows[i]:SetText("|cff00ff00Attuned|r")
    else
      rows[i]:SetText("|cffff3333No|r")
    end
  end
  if name == MyName() then
    info:SetText("You (live)")
  elseif d then
    info:SetText("Updated " .. AgeText(time() - t))
  else
    info:SetText("No data (needs addon, be online)")
  end
end

local function Request(name)
  local now = GetTime()
  if lastReq[name] and now - lastReq[name] < 15 then return end
  lastReq[name] = now
  Send("R~" .. name)
end

local offL, offR, offY = 0, 0, -3

local function Anchor()
  local parent = GuildMemberDetailFrame
  if not parent or not panel then return end
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", offL, offY)
  panel:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", offR, offY)
end

-- pfUI only: nudge the panel until its visible background lines up with
-- the guild detail window's visible background
local function Align()
  local parent = GuildMemberDetailFrame
  if not parent or not panel or not pfUI then return end
  local ref = parent.backdrop or parent
  local pb = panel.backdrop or panel
  local rl, rr, rb = ref:GetLeft(), ref:GetRight(), ref:GetBottom()
  local pl, pr, pt = pb:GetLeft(), pb:GetRight(), pb:GetTop()
  if not (rl and rr and rb and pl and pr and pt) then return end
  local dl, dr, dy = rl - pl, rr - pr, (rb - 3) - pt
  if math.abs(dl) > 0.5 or math.abs(dr) > 0.5 or math.abs(dy) > 0.5 then
    offL = offL + dl
    offR = offR + dr
    offY = offY + dy
    Anchor()
  end
end

-- automatic theme: pfUI installed -> pfUI look, otherwise normal Blizzard look
local function ApplyTheme()
  if not panel then return end
  if pfUI then
    panel:SetBackdrop(nil)
    if not panel.backdrop and pfUI.api and pfUI.api.CreateBackdrop then
      pcall(pfUI.api.CreateBackdrop, panel, nil, nil, 0.75)
    end
    if panel.backdrop then
      panel.backdrop:Show()
      -- copy transparency/colors of the detail window when pfUI exposes them
      local ref = GuildMemberDetailFrame and GuildMemberDetailFrame.backdrop
      if ref and ref.GetBackdropColor then
        local ok, r, g, b, a = pcall(ref.GetBackdropColor, ref)
        if ok and r and g and b and a then panel.backdrop:SetBackdropColor(r, g, b, a) end
      end
      if ref and ref.GetBackdropBorderColor then
        local ok, r, g, b, a = pcall(ref.GetBackdropBorderColor, ref)
        if ok and r and g and b then panel.backdrop:SetBackdropBorderColor(r, g, b, a or 1) end
      end
    else
      panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
      })
      panel:SetBackdropColor(0.1, 0.1, 0.1, 0.75)
      panel:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    end
    Anchor()
    Align()
  else
    offL, offR, offY = 0, 0, 30  -- raise to shrink the gap, lower to widen it
    if panel.backdrop then panel.backdrop:Hide() end
    panel:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    panel:SetBackdropColor(1, 1, 1, 1)
    panel:SetBackdropBorderColor(1, 1, 1, 1)
    Anchor()
  end
end

local function CreatePanel()
  local parent = GuildMemberDetailFrame or FriendsFrame
  panel = CreateFrame("Frame", "AttuneGuildPanel", parent)
  panel:SetHeight(50 + getn(RAIDS) * 14)
  if GuildMemberDetailFrame then
    -- two anchors (set in ApplyTheme) = same width as the detail window
    panel:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -2)
    panel:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", 0, -2)
  else
    panel:SetWidth(240)
    panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, -40)
  end
  title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", T.pTx, T.pTy)
  rows = {}
  labels = {}
  for i = 1, getn(RAIDS) do
    local y = -28 - (i - 1) * 14
    local l = panel:CreateFontString(nil, "OVERLAY", T.fH)
    l:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    l:SetText(RAIDS[i].label)
    labels[i] = l
    local v = panel:CreateFontString(nil, "OVERLAY", T.fN)
    v:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, y)
    rows[i] = v
  end
  info = panel:CreateFontString(nil, "OVERLAY", T.fD)
  info:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", T.pInfoX, T.pInfoY)

  panel:SetScript("OnShow", function()
    shownName = nil
    ApplyTheme()
  end)
  panel:SetScript("OnUpdate", function()
    this.t = (this.t or 0) + arg1
    if this.t < 0.3 then return end
    this.t = 0
    Align()
    local sel = GetGuildRosterSelection()
    local name = nil
    if sel and sel > 0 then name = GetGuildRosterInfo(sel) end
    if name ~= shownName then
      shownName = name
      Refresh()
      if name and name ~= MyName() then Request(name) end
    end
  end)
end

-- ===== right-click menu: Attunements > submenu =====
local function RequestUnit(name)
  Send("R~" .. name)
  if GetNumRaidMembers() > 0 then
    SendAddonMessage(PREFIX, "R~" .. name, "RAID")
  elseif GetNumPartyMembers() > 0 then
    SendAddonMessage(PREFIX, "R~" .. name, "PARTY")
  end
end

local function AskThrottled(name)
  local now = GetTime()
  if lastReq[name] and now - lastReq[name] < 10 then return end
  lastReq[name] = now
  RequestUnit(name)
end

local function UpdateMenuTexts(name)
  local d, t
  if name == MyName() then
    d = ParseStatus(BuildStatus())
  elseif AttuneDB.cache[name] then
    d = AttuneDB.cache[name].d
    t = AttuneDB.cache[name].t
  end
  for i = 1, getn(RAIDS) do
    local st
    if not d then
      st = "|cff888888?|r"
    elseif d[RAIDS[i].key] then
      st = "|cff00ff00Attuned|r"
    else
      st = "|cffff3333No|r"
    end
    UnitPopupButtons["ATTUNE_" .. RAIDS[i].key].text = RAIDS[i].label .. ": " .. st
  end
  local line
  if name == MyName() then
    line = "You (live)"
  elseif d then
    line = "Updated " .. AgeText(time() - t)
  else
    line = "No data (needs addon)"
  end
  UnitPopupButtons["ATTUNE_info"].text = "|cff888888" .. line .. "|r"
end

if UnitPopupButtons and UnitPopupMenus and UnitPopup_ShowMenu then
  UnitPopupButtons["ATTUNE"] = { text = "Attunements", dist = 0, nested = 1 }
  UnitPopupButtons["ATTUNE_info"] = { text = "", dist = 0 }
  local sub = { "ATTUNE_info" }
  for i = 1, getn(RAIDS) do
    UnitPopupButtons["ATTUNE_" .. RAIDS[i].key] = { text = RAIDS[i].label, dist = 0 }
    tinsert(sub, "ATTUNE_" .. RAIDS[i].key)
  end
  UnitPopupMenus["ATTUNE"] = sub

  local menus = { "SELF", "PARTY", "PLAYER", "RAID", "RAID_PLAYER", "FRIEND" }
  for m = 1, getn(menus) do
    local list = UnitPopupMenus[menus[m]]
    if list then
      local pos = getn(list) + 1
      for i = 1, getn(list) do
        if list[i] == "CANCEL" then pos = i end
      end
      tinsert(list, pos, "ATTUNE")
    end
  end

  -- refresh the submenu text (and ask the player) every time a popup is built
  local origShowMenu = UnitPopup_ShowMenu
  UnitPopup_ShowMenu = function(dropdown, which, unit, name, userData)
    if AttuneDB then
      local n = name
      if not n and unit then n = UnitName(unit) end
      if not n and dropdown then n = dropdown.name end
      if n and n ~= "" then
        if (UIDROPDOWNMENU_MENU_LEVEL or 1) == 1 and n ~= MyName() then AskThrottled(n) end
        UpdateMenuTexts(n)
      end
    end
    return origShowMenu(dropdown, which, unit, name, userData)
  end

  -- the submenu rows are display only
  local origPopupClick = UnitPopup_OnClick
  UnitPopup_OnClick = function()
    if this.value and string.find(this.value, "^ATTUNE") then return end
    return origPopupClick()
  end
end

-- ===== visible raids (options can hide some) =====
local SHORT = { ony = "Ony", mc = "MC", bwl = "BWL", es = "ES", nax = "Naxx", kut = "KUK", ksm = "KSM" }

local function Visible()
  local t = {}
  for i = 1, getn(RAIDS) do
    if not AttuneDB.opt.hidden[RAIDS[i].key] then tinsert(t, RAIDS[i]) end
  end
  return t
end

-- re-lay the guild panel rows so hidden raids leave no gap
local function LayoutPanel()
  if not panel or not rows then return end
  local n = 0
  for i = 1, getn(RAIDS) do
    if AttuneDB.opt.hidden[RAIDS[i].key] then
      labels[i]:Hide()
      rows[i]:Hide()
    else
      local y = T.pRowY - n * T.pRowH
      labels[i]:ClearAllPoints()
      labels[i]:SetPoint("TOPLEFT", panel, "TOPLEFT", T.pRowX, y)
      rows[i]:ClearAllPoints()
      rows[i]:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -T.pRowX, y)
      labels[i]:Show()
      rows[i]:Show()
      n = n + 1
    end
  end
  panel:SetHeight(T.pH + n * T.pRowH)
end

local function ApplyPanelOption()
  if not panel then return end
  if AttuneDB.opt.noPanel then panel:Hide() else panel:Show() end
end

-- ===== roster window + minimap button =====
local ROW_H, VISIBLE, NAME_W, COL_W = 18, 15, 130, 54
local roster, scroll, searchBox, raidBtn, showBtn, statusFS, hdrName
local hdrs, rowFrames = {}, {}
local list = {}
local searchText = ""
local raidIdx = 0            -- 0 = all raids, otherwise index into RAIDS
local showMode = 1           -- 1 everyone, 2 missing, 3 attuned (only with a raid picked)
local onlyOnline, onlyGroup, onlyData = false, false, false
local sortKey, sortDesc = "name", false
local SHOW_NAMES = { "Everyone", "Missing", "Attuned" }
local RefreshRoster, LayoutRoster

local function SkinFrame(f)
  if pfUI then
    f:SetBackdrop(nil)
    if not f.backdrop and pfUI.api and pfUI.api.CreateBackdrop then
      pcall(pfUI.api.CreateBackdrop, f, nil, nil, 0.75)
    end
    if f.backdrop then
      f.backdrop:Show()
    else
      f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
      })
      f:SetBackdropColor(0.1, 0.1, 0.1, 0.75)
      f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    end
  else
    if f.backdrop then f.backdrop:Hide() end
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:SetBackdropColor(1, 1, 1, 1)
    f:SetBackdropBorderColor(1, 1, 1, 1)
  end
  if f.header and f.title then
    f.title:ClearAllPoints()
    if pfUI then
      f.header:Hide()
      f.title:SetText("Attunely - Guild Attunements")
      f.title:SetPoint("TOP", f, "TOP", 0, -12)
    else
      f.header:Show()
      f.title:SetText("Guild Attunements")
      f.title:SetPoint("TOP", f.header, "TOP", 0, -14)
    end
  end
end

local function SkinButton(b)
  if pfUI and pfUI.api and pfUI.api.SkinButton then pcall(pfUI.api.SkinButton, b) end
end

local function SkinClose(b)
  if pfUI and pfUI.api and pfUI.api.SkinCloseButton then
    pcall(pfUI.api.SkinCloseButton, b, roster, -6, -6)
  end
end

local function SkinCheck(b)
  if pfUI and pfUI.api and pfUI.api.SkinCheckbox then pcall(pfUI.api.SkinCheckbox, b) end
end

local scrollSkinned, searchSkinned = false, false

local function SkinEdit(e)
  if searchSkinned or not (pfUI and pfUI.api and pfUI.api.CreateBackdrop) then return end
  searchSkinned = true
  local n = e:GetName() or "AttuneRosterSearch"
  local parts = { "Left", "Middle", "Right" }
  for i = 1, getn(parts) do
    local t = getglobal(n .. parts[i])
    if t then t:Hide() end
  end
  pcall(pfUI.api.CreateBackdrop, e, nil, true)
  e:SetTextInsets(5, 5, 4, 4)
end

local function SkinScroll()
  if scrollSkinned or not (pfUI and pfUI.api) then return end
  local sb = getglobal("AttuneRosterScrollScrollBar")
  if not sb then return end
  scrollSkinned = true
  local up = getglobal("AttuneRosterScrollScrollBarScrollUpButton")
  local dn = getglobal("AttuneRosterScrollScrollBarScrollDownButton")
  if pfUI.api.SkinArrowButton then
    if up then pcall(pfUI.api.SkinArrowButton, up, "up", 16) end
    if dn then pcall(pfUI.api.SkinArrowButton, dn, "down", 16) end
  end
  if pfUI.api.CreateBackdrop then pcall(pfUI.api.CreateBackdrop, sb, nil, true) end
  pcall(function()
    sb:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local th = sb:GetThumbTexture()
    if th then
      th:SetVertexColor(0.45, 0.45, 0.45, 1)
      th:SetWidth(10)
      th:SetHeight(24)
    end
  end)
end

local function ClassHex(class)
  local c = nil
  if RAID_CLASS_COLORS and class then c = RAID_CLASS_COLORS[string.upper(class)] end
  if not c then return "|cffffffff" end
  return string.format("|cff%02x%02x%02x", math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5))
end

local function AttRank(e, key)
  if not e.d then return 0 end
  if e.d[key] then return 2 end
  return 1
end

local function SortList()
  local key, desc = sortKey, sortDesc
  if key ~= "name" and AttuneDB.opt.hidden[key] then key = "name" end
  table.sort(list, function(a, b)
    if key ~= "name" then
      local av, bv = AttRank(a, key), AttRank(b, key)
      if av ~= bv then
        if desc then return av < bv end
        return av > bv
      end
    elseif desc then
      return a.name > b.name
    end
    return a.name < b.name
  end)
end

local function GroupSet()
  local g = {}
  g[MyName()] = true
  for i = 1, GetNumRaidMembers() do
    local n = UnitName("raid" .. i)
    if n then g[n] = true end
  end
  for i = 1, GetNumPartyMembers() do
    local n = UnitName("party" .. i)
    if n then g[n] = true end
  end
  return g
end

local function CountWithData()
  local total = GetNumGuildMembers(true) or 0
  local c = 0
  for i = 1, total do
    local name = GetGuildRosterInfo(i)
    if name and (name == MyName() or (AttuneDB.cache[name] and AttuneDB.cache[name].d)) then c = c + 1 end
  end
  return c, total
end

local function BuildList()
  list = {}
  local filter = string.lower(searchText or "")
  local gs = nil
  if onlyGroup then gs = GroupSet() end
  local key = nil
  if raidIdx > 0 and RAIDS[raidIdx] then key = RAIDS[raidIdx].key end
  local total = GetNumGuildMembers(true) or 0
  local withData = 0
  for i = 1, total do
    local name, _, _, level, class, _, _, _, online = GetGuildRosterInfo(i)
    if name then
      local d, t
      if name == MyName() then
        d = ParseStatus(BuildStatus())
      elseif AttuneDB.cache[name] then
        d = AttuneDB.cache[name].d
        t = AttuneDB.cache[name].t
      end
      if d then withData = withData + 1 end
      local ok = true
      if filter ~= "" and not string.find(string.lower(name), filter, 1, true) then ok = false end
      if ok and onlyOnline and not online then ok = false end
      if ok and onlyData and not d then ok = false end
      if ok and gs and not gs[name] then ok = false end
      if ok and key and showMode == 2 and (not d or d[key]) then ok = false end
      if ok and key and showMode == 3 and (not d or not d[key]) then ok = false end
      if ok then
        tinsert(list, { name = name, level = level, class = class, online = online, d = d, t = t })
      end
    end
  end
  SortList()
  return total, withData
end

local function ResetScroll()
  local sb = getglobal("AttuneRosterScrollScrollBar")
  if sb then sb:SetValue(0) end
  if scroll then scroll.offset = 0 end
end

local function UpdateButtonTexts()
  if raidBtn then
    if raidIdx == 0 then raidBtn:SetText("Raid: All") else raidBtn:SetText("Raid: " .. RAIDS[raidIdx].label) end
  end
  if showBtn then showBtn:SetText("Show: " .. SHOW_NAMES[showMode]) end
end

local function CycleRaid(dir)
  local n = getn(RAIDS)
  local i = raidIdx
  for _ = 1, n + 1 do
    i = i + dir
    if i > n then i = 0 elseif i < 0 then i = n end
    if i == 0 or not AttuneDB.opt.hidden[RAIDS[i].key] then break end
  end
  raidIdx = i
  if raidIdx == 0 then showMode = 1 end
  UpdateButtonTexts()
  ResetScroll()
  RefreshRoster()
end

-- names missing the selected raid, among everyone passing the current filters except the Show mode
local function OutputMissing(post)
  if raidIdx == 0 then
    Print("Pick a raid with the Raid button first.")
    return
  end
  local r = RAIDS[raidIdx]
  local names = {}
  for i = 1, getn(list) do
    local e = list[i]
    if e.d and not e.d[r.key] then tinsert(names, e.name) end
  end
  table.sort(names)
  local head = "Missing " .. r.label .. " (" .. getn(names) .. "): "
  if getn(names) == 0 then head = head .. "nobody (among players with data)" end
  local chan = "GUILD"
  if GetNumRaidMembers() > 0 then chan = "RAID" elseif GetNumPartyMembers() > 0 then chan = "PARTY" end
  local lines = {}
  local line = head
  for i = 1, getn(names) do
    local add = names[i]
    if i < getn(names) then add = add .. ", " end
    if string.len(line) + string.len(add) > 230 then
      tinsert(lines, line)
      line = ""
    end
    line = line .. add
  end
  tinsert(lines, line)
  for i = 1, getn(lines) do
    if post then SendChatMessage(lines[i], chan) else Print(lines[i]) end
  end
end

RefreshRoster = function()
  if not roster or not roster:IsVisible() then return end
  local total, withData = BuildList()
  local n = getn(list)
  FauxScrollFrame_Update(scroll, n, VISIBLE, ROW_H)
  local off = scroll.offset or 0
  local vis = Visible()
  for i = 1, VISIBLE do
    local row = rowFrames[i]
    local e = list[off + i]
    if e then
      row.entry = e
      local hex = ClassHex(e.class)
      row.nameFS:SetText(hex .. e.name .. "|r")
      if e.online then row:SetAlpha(1) else row:SetAlpha(0.55) end
      for j = 1, getn(row.cells) do
        local cell = row.cells[j]
        if j <= getn(vis) then
          local key = vis[j].key
          if not e.d then
            cell:SetText("|cff888888?|r")
          elseif e.d[key] then
            cell:SetText("|cff00ff00Yes|r")
          else
            cell:SetText("|cffff3333No|r")
          end
          cell:Show()
        else
          cell:Hide()
        end
      end
      row:Show()
    else
      row.entry = nil
      row:Hide()
    end
  end
  local nameHex = "|cffffffff"
  if sortKey == "name" then nameHex = "|cffffd200" end
  hdrName:SetText(nameHex .. "Name|r")
  for j = 1, getn(vis) do
    local hex = "|cffffffff"
    if sortKey == vis[j].key then hex = "|cffffd200" end
    hdrs[j]:SetText(hex .. (SHORT[vis[j].key] or string.sub(vis[j].label, 1, 5)) .. "|r")
  end
  statusFS:SetText("Showing " .. n .. " of " .. total .. " guild members  -  " .. withData .. " have the addon")
end

LayoutRoster = function()
  if not roster then return end
  local vis = Visible()
  local nv = getn(vis)
  local w = NAME_W + nv * COL_W + 58
  if w < 550 then w = 550 end
  local totalW = w - 58
  roster:SetWidth(w)
  scroll:SetWidth(totalW)
  hdrName:SetWidth(NAME_W)
  for j = 1, getn(RAIDS) do
    local h = hdrs[j]
    if j <= nv then
      h.key = vis[j].key
      h.tip = vis[j].label
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", roster, "TOPLEFT", 14 + NAME_W + (j - 1) * COL_W, -88)
      h:Show()
    else
      h:Hide()
    end
  end
  for i = 1, VISIBLE do
    local row = rowFrames[i]
    row:SetWidth(totalW)
    for j = 1, getn(row.cells) do
      row.cells[j]:ClearAllPoints()
      row.cells[j]:SetPoint("CENTER", row, "LEFT", NAME_W + (j - 1) * COL_W + COL_W / 2, 0)
    end
  end
end

-- helpers grouped in one table: Lua 5.0 allows at most 32 upvalues per function
local H = {
  SkinFrame = SkinFrame,
  SkinButton = SkinButton,
  SkinClose = SkinClose,
  SkinCheck = SkinCheck,
  SkinEdit = SkinEdit,
  SkinScroll = SkinScroll,
  Send = Send,
  AgeText = AgeText,
  MyName = MyName,
  Print = Print,
  CycleRaid = CycleRaid,
  OutputMissing = OutputMissing,
  ResetScroll = ResetScroll,
  UpdateButtonTexts = UpdateButtonTexts,
  ROW_H = ROW_H,
  VISIBLE = VISIBLE,
  NAME_W = NAME_W,
  COL_W = COL_W,
}


local function CreateRoster()
  roster = CreateFrame("Frame", "AttuneRosterFrame", UIParent)
  roster:SetWidth(520)
  roster:SetHeight(106 + H.VISIBLE * H.ROW_H + T.extraH)
  roster:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  roster:SetFrameStrata("DIALOG")
  roster:SetMovable(true)
  roster:EnableMouse(true)
  roster:EnableMouseWheel(true)
  roster:RegisterForDrag("LeftButton")
  roster:SetScript("OnDragStart", function() this:StartMoving() end)
  roster:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  roster:Hide()
  tinsert(UISpecialFrames, "AttuneRosterFrame")

  local t = roster:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOP", roster, "TOP", 0, -12)
  t:SetText("Attunely - Guild Attunements")
  roster.title = t
  local hd = roster:CreateTexture(nil, "ARTWORK")
  hd:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
  hd:SetWidth(256)
  hd:SetHeight(64)
  hd:SetPoint("TOP", roster, "TOP", 0, 12)
  roster.header = hd

  local close = CreateFrame("Button", "AttuneRosterClose", roster, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", roster, "TOPRIGHT", T.closeOff, T.closeOff)
  H.SkinClose(close)

  if not pfUI then
    local lb = CreateFrame("Frame", nil, roster)
    lb:SetPoint("TOPLEFT", roster, "TOPLEFT", 12, -84)
    lb:SetPoint("TOPRIGHT", roster, "TOPRIGHT", -12, -84)
    lb:SetHeight(H.VISIBLE * H.ROW_H + 26)
    lb:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = false, edgeSize = 14,
      insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    lb:SetBackdropColor(0, 0, 0, 0.6)
    lb:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    roster.listBg = lb
  end
  scroll = CreateFrame("ScrollFrame", "AttuneRosterScroll", roster, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", roster, "TOPLEFT", 14, -106)
  scroll:SetHeight(H.VISIBLE * H.ROW_H)
  scroll:SetWidth(400)
  scroll:SetScript("OnVerticalScroll", function()
    FauxScrollFrame_OnVerticalScroll(H.ROW_H, RefreshRoster)
  end)
  local sbar = getglobal("AttuneRosterScrollScrollBar")
  if sbar then
    sbar:ClearAllPoints()
    sbar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, -18)
    sbar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 18)
  end
  roster:SetScript("OnMouseWheel", function()
    local sb = getglobal("AttuneRosterScrollScrollBar")
    if sb then sb:SetValue(sb:GetValue() - arg1 * H.ROW_H * 2) end
  end)

  -- search
  local sl = roster:CreateFontString(nil, "OVERLAY", T.fN)
  sl:SetPoint("TOPLEFT", roster, "TOPLEFT", 16, T.slY)
  sl:SetText("Search:")
  searchBox = CreateFrame("EditBox", "AttuneRosterSearch", roster, "InputBoxTemplate")
  searchBox:SetWidth(T.searchW)
  searchBox:SetHeight(T.searchH)
  searchBox:SetPoint("TOPLEFT", roster, "TOPLEFT", 68, T.searchY)
  searchBox:SetAutoFocus(false)
  searchBox:SetMaxLetters(24)
  if pfUI then
    if ChatFontNormal then searchBox:SetFontObject(ChatFontNormal) end
  elseif GameFontHighlight then
    searchBox:SetFontObject(GameFontHighlight)
  end
  searchBox:SetScript("OnTextChanged", function()
    searchText = this:GetText() or ""
    if not pfUI then
      local cb = getglobal("AttuneRosterClear")
      if cb then if searchText ~= "" then cb:Show() else cb:Hide() end end
    end
    H.ResetScroll()
    RefreshRoster()
  end)
  searchBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  searchBox:SetScript("OnEnterPressed", function() this:ClearFocus() end)

  local clr
  if pfUI then
    clr = CreateFrame("Button", "AttuneRosterClear", roster, "UIPanelButtonTemplate")
    clr:SetWidth(T.clrW)
    clr:SetHeight(T.btnH)
    clr:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
    clr:SetText("x")
    clr:SetScript("OnClick", function()
      searchBox:SetText("")
      searchBox:ClearFocus()
    end)
    H.SkinButton(clr)
  else
    searchBox:SetTextInsets(6, 24, 0, 0)
    clr = CreateFrame("Button", "AttuneRosterClear", roster)
    clr:SetWidth(20)
    clr:SetHeight(20)
    clr:SetFrameLevel(searchBox:GetFrameLevel() + 3)
    clr:SetPoint("RIGHT", searchBox, "RIGHT", -4, 0)
    local cfs = clr:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cfs:SetPoint("CENTER", clr, "CENTER", 0, 1)
    cfs:SetText("x")
    clr:SetScript("OnEnter", function() cfs:SetTextColor(1, 1, 1) end)
    clr:SetScript("OnLeave", function() cfs:SetTextColor(1, 0.82, 0) end)
    clr:SetScript("OnClick", function()
      searchBox:SetText("")
      searchBox:ClearFocus()
    end)
    clr:Hide()
  end

  raidBtn = CreateFrame("Button", "AttuneRosterRaid", roster, "UIPanelButtonTemplate")
  raidBtn:SetWidth(150)
  raidBtn:SetHeight(T.btnH)
  if pfUI then raidBtn:SetPoint("LEFT", clr, "RIGHT", 8, 0) else raidBtn:SetPoint("LEFT", searchBox, "RIGHT", 10, 0) end
  raidBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  raidBtn:SetScript("OnClick", function()
    if arg1 == "RightButton" then H.CycleRaid(-1) else H.CycleRaid(1) end
  end)
  raidBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText("Raid filter")
    GameTooltip:AddLine("Left-click: next raid, right-click: previous.", 1, 1, 1)
    GameTooltip:Show()
  end)
  raidBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  H.SkinButton(raidBtn)

  showBtn = CreateFrame("Button", "AttuneRosterShow", roster, "UIPanelButtonTemplate")
  showBtn:SetWidth(T.showW)
  showBtn:SetHeight(T.btnH)
  showBtn:SetPoint("LEFT", raidBtn, "RIGHT", 6, 0)
  showBtn:SetScript("OnClick", function()
    if raidIdx == 0 then
      H.Print("Pick a raid first, then choose Everyone / Missing / Attuned.")
      return
    end
    showMode = showMode + 1
    if showMode > 3 then showMode = 1 end
    H.UpdateButtonTexts()
    H.ResetScroll()
    RefreshRoster()
  end)
  H.SkinButton(showBtn)

  local function MakeCheck(name, text, x, setter)
    local cb = CreateFrame("CheckButton", name, roster, "UICheckButtonTemplate")
    cb:SetWidth(24)
    cb:SetHeight(24)
    cb:SetPoint("TOPLEFT", roster, "TOPLEFT", x, -58)
    local fs = getglobal(name .. "Text")
    if fs then fs:SetText(text) end
    if fs and not pfUI and GameFontNormal then fs:SetFontObject(GameFontNormal) end
    cb:SetScript("OnClick", function()
      setter(this:GetChecked() and true or false)
      H.ResetScroll()
      RefreshRoster()
    end)
    H.SkinCheck(cb)
    return cb
  end
  MakeCheck("AttuneChkOnline", "Online only", 14, function(v) onlyOnline = v end)
  MakeCheck("AttuneChkGroup", "Group only", 130, function(v) onlyGroup = v end)
  MakeCheck("AttuneChkData", "With addon data", 246, function(v) onlyData = v end)

  -- headers
  hdrName = CreateFrame("Button", nil, roster)
  hdrName:SetHeight(16)
  hdrName:SetWidth(H.NAME_W)
  hdrName:SetPoint("TOPLEFT", roster, "TOPLEFT", 14, -88)
  local hf = hdrName:CreateFontString(nil, "OVERLAY", T.fN)
  hf:SetPoint("LEFT", hdrName, "LEFT", 4, 0)
  hdrName.SetText = function(self, txt) hf:SetText(txt) end
  hdrName:SetScript("OnClick", function()
    if sortKey == "name" then sortDesc = not sortDesc else sortKey = "name"; sortDesc = false end
    RefreshRoster()
  end)
  for j = 1, getn(RAIDS) do
    local h = CreateFrame("Button", nil, roster)
    h:SetWidth(H.COL_W)
    h:SetHeight(16)
    local fs = h:CreateFontString(nil, "OVERLAY", T.fN)
    fs:SetPoint("CENTER", h, "CENTER", 0, 0)
    h.SetText = function(self, txt) fs:SetText(txt) end
    h:SetScript("OnClick", function()
      if sortKey == this.key then sortDesc = not sortDesc else sortKey = this.key; sortDesc = false end
      RefreshRoster()
    end)
    h:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_TOP")
      GameTooltip:SetText(this.tip or "")
      GameTooltip:AddLine("Click to sort.", 1, 1, 1)
      GameTooltip:Show()
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hdrs[j] = h
  end

  -- rows
  for i = 1, H.VISIBLE do
    local row = CreateFrame("Button", nil, roster)
    row:SetHeight(H.ROW_H)
    row:SetWidth(400)
    row:SetPoint("TOPLEFT", roster, "TOPLEFT", 14, -106 - (i - 1) * H.ROW_H)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.nameFS = row:CreateFontString(nil, "OVERLAY", T.fH)
    row.nameFS:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.cells = {}
    for j = 1, getn(RAIDS) do
      row.cells[j] = row:CreateFontString(nil, "OVERLAY", T.fH)
    end
    row:SetScript("OnEnter", function()
      local e = this.entry
      if not e then return end
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:SetText(e.name)
      GameTooltip:AddLine("Level " .. (e.level or "?") .. " " .. (e.class or ""), 1, 1, 1)
      if e.name == H.MyName() then
        GameTooltip:AddLine("You (live)", 0.6, 0.6, 0.6)
      elseif e.t then
        GameTooltip:AddLine("Data updated " .. H.AgeText(time() - e.t), 0.6, 0.6, 0.6)
      else
        GameTooltip:AddLine("No data (needs the addon, be online)", 0.6, 0.6, 0.6)
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:Hide()
    rowFrames[i] = row
  end

  -- bottom bar
  statusFS = roster:CreateFontString(nil, "OVERLAY", T.fD)
  statusFS:SetPoint("BOTTOMLEFT", roster, "BOTTOMLEFT", 16, T.statusY)

  local post = CreateFrame("Button", "AttuneRosterPost", roster, "UIPanelButtonTemplate")
  post:SetWidth(T.botW)
  post:SetHeight(T.btnH)
  post:SetPoint("BOTTOMRIGHT", roster, "BOTTOMRIGHT", T.postX, T.postY)
  post:SetText("Post missing")
  post:SetScript("OnClick", function() H.OutputMissing(true) end)
  post:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText("Post missing")
    GameTooltip:AddLine("Sends the names missing the selected raid to raid/party/guild chat.", 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  post:SetScript("OnLeave", function() GameTooltip:Hide() end)
  H.SkinButton(post)

  local prt = CreateFrame("Button", "AttuneRosterPrint", roster, "UIPanelButtonTemplate")
  prt:SetWidth(T.botW)
  prt:SetHeight(T.btnH)
  prt:SetPoint("RIGHT", post, "LEFT", -4, 0)
  prt:SetText("Print missing")
  prt:SetScript("OnClick", function() H.OutputMissing(false) end)
  H.SkinButton(prt)

  local ref = CreateFrame("Button", "AttuneRosterRefresh", roster, "UIPanelButtonTemplate")
  ref:SetWidth(T.botW)
  ref:SetHeight(T.btnH)
  ref:SetPoint("RIGHT", prt, "LEFT", -4, 0)
  ref:SetText("Refresh")
  ref:SetScript("OnClick", function()
    GuildRoster()
    H.Send("Q")
    H.Print("Asked the guild to resend attunements.")
  end)
  H.SkinButton(ref)

  H.SkinEdit(searchBox)
  H.SkinScroll()
  roster:SetScript("OnShow", function()
    H.SkinFrame(roster)
    LayoutRoster()
    H.UpdateButtonTexts()
    RefreshRoster()
  end)

  H.UpdateButtonTexts()
  LayoutRoster()
end

local function ToggleRoster()
  if not roster then CreateRoster() end
  if roster:IsVisible() then
    roster:Hide()
  else
    roster:Show()
    GuildRoster()
  end
end

-- ===== options (minimap right-click) =====
local mmButton

local function ApplyHidden()
  if raidIdx > 0 and AttuneDB.opt.hidden[RAIDS[raidIdx].key] then
    raidIdx = 0
    showMode = 1
  end
  LayoutPanel()
  if roster then
    LayoutRoster()
    UpdateButtonTexts()
    RefreshRoster()
  end
end

local function PlaceMinimapButton()
  if not mmButton then return end
  local angle = AttuneDB.mm.angle or 200
  local rad = math.rad(angle)
  local r = (Minimap:GetWidth() / 2) + 5
  local x, y = math.cos(rad) * r, math.sin(rad) * r
  if pfUI then
    -- pfUI minimap is square: slide along the edge
    local m = math.max(math.abs(x), math.abs(y))
    if m > 0 then
      x = x * r / m
      y = y * r / m
    end
  end
  mmButton:ClearAllPoints()
  mmButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function ApplyMinimapVisibility()
  if not mmButton then return end
  if AttuneDB.mm.hide then mmButton:Hide() else mmButton:Show() end
end

local function ToggleRaidHidden(key)
  if AttuneDB.opt.hidden[key] then AttuneDB.opt.hidden[key] = nil else AttuneDB.opt.hidden[key] = true end
  ApplyHidden()
end

local optionsMenu

local function InitOptionsMenu()
  local info = { text = "Attunely", isTitle = 1 }
  UIDropDownMenu_AddButton(info)
  info = { text = "Open roster", notCheckable = 1, func = function() ToggleRoster() end }
  UIDropDownMenu_AddButton(info)
  info = {
    text = "Request data now", notCheckable = 1,
    func = function()
      GuildRoster()
      Send("Q")
      Print("Asked the guild to resend attunements.")
    end
  }
  UIDropDownMenu_AddButton(info)
  local pchecked = nil
  if not AttuneDB.opt.noPanel then pchecked = 1 end
  info = {
    text = "Show guild panel extra", checked = pchecked, keepShownOnClick = 1,
    func = function()
      if AttuneDB.opt.noPanel then AttuneDB.opt.noPanel = nil else AttuneDB.opt.noPanel = true end
      ApplyPanelOption()
    end
  }
  UIDropDownMenu_AddButton(info)
  info = { text = "Raids to show (click to toggle):", isTitle = 1 }
  UIDropDownMenu_AddButton(info)
  for i = 1, getn(RAIDS) do
    local key = RAIDS[i].key
    local checked = nil
    if not AttuneDB.opt.hidden[key] then checked = 1 end
    info = { text = RAIDS[i].label, checked = checked, keepShownOnClick = 1, func = function() ToggleRaidHidden(key) end }
    UIDropDownMenu_AddButton(info)
  end
  info = {
    text = "Hide minimap button", notCheckable = 1,
    func = function()
      AttuneDB.mm.hide = true
      ApplyMinimapVisibility()
      Print("Minimap button hidden. Type /attune minimap to bring it back.")
    end
  }
  UIDropDownMenu_AddButton(info)
end

local function ShowOptionsMenu()
  if not optionsMenu then
    optionsMenu = CreateFrame("Frame", "AttuneOptionsMenu", UIParent, "UIDropDownMenuTemplate")
  end
  UIDropDownMenu_Initialize(optionsMenu, InitOptionsMenu, "MENU")
  ToggleDropDownMenu(1, nil, optionsMenu, "cursor")
end

local function CreateMinimapButton()
  if mmButton or not Minimap then return end
  mmButton = CreateFrame("Button", "AttuneMinimapButton", Minimap)
  mmButton:SetWidth(31)
  mmButton:SetHeight(31)
  mmButton:SetFrameStrata("MEDIUM")
  mmButton:SetFrameLevel(8)
  local icon = mmButton:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Key_03")
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  icon:SetWidth(20)
  icon:SetHeight(20)
  icon:SetPoint("CENTER", mmButton, "CENTER", 0, 1)
  local border = mmButton:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetWidth(53)
  border:SetHeight(53)
  border:SetPoint("TOPLEFT", mmButton, "TOPLEFT", 0, 0)
  mmButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  mmButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  mmButton:RegisterForDrag("LeftButton")
  mmButton:SetScript("OnClick", function()
    if arg1 == "RightButton" then ShowOptionsMenu() else ToggleRoster() end
  end)
  mmButton:SetScript("OnDragStart", function() this.dragging = true end)
  mmButton:SetScript("OnDragStop", function() this.dragging = false end)
  mmButton:SetScript("OnUpdate", function()
    if not this.dragging then return end
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local sc = Minimap:GetEffectiveScale()
    cx, cy = cx / sc, cy / sc
    AttuneDB.mm.angle = math.deg(math.atan2(cy - my, cx - mx))
    PlaceMinimapButton()
  end)
  mmButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:SetText("Attunely")
    local vis = Visible()
    local d = ParseStatus(BuildStatus())
    for i = 1, getn(vis) do
      if d[vis[i].key] then
        GameTooltip:AddDoubleLine(vis[i].label, "Attuned", 1, 1, 1, 0, 1, 0)
      else
        GameTooltip:AddDoubleLine(vis[i].label, "No", 1, 1, 1, 1, 0.2, 0.2)
      end
    end
    local c, total = CountWithData()
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(c .. " of " .. total .. " guild members have data", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Left-click: guild roster", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: options", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag: move button", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  mmButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
  PlaceMinimapButton()
  ApplyMinimapVisibility()
end

-- ===== events =====
local core = CreateFrame("Frame")
core:RegisterEvent("ADDON_LOADED")
core:RegisterEvent("PLAYER_ENTERING_WORLD")
core:RegisterEvent("BAG_UPDATE")
core:RegisterEvent("BANKFRAME_OPENED")
core:RegisterEvent("CHAT_MSG_ADDON")
core:RegisterEvent("UPDATE_INSTANCE_INFO")
core:RegisterEvent("ZONE_CHANGED_NEW_AREA")
core:RegisterEvent("GUILD_ROSTER_UPDATE")

core:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == "Attunely" then
    DetectPfUI()
    AttuneDB = AttuneDB or {}
    AttuneDB.cache = AttuneDB.cache or {}
    AttuneDB.opt = AttuneDB.opt or {}
    AttuneDB.opt.hidden = AttuneDB.opt.hidden or {}
    AttuneDB.mm = AttuneDB.mm or { angle = 200 }
    if not AttuneDB.chars then
      -- old (account-wide) data: keep only quest-based entries, item ones get rescanned per character
      local old = AttuneDB.me or {}
      AttuneDB.legacy = {}
      for i = 1, getn(RAIDS) do
        if not RAIDS[i].item and old[RAIDS[i].key] then AttuneDB.legacy[RAIDS[i].key] = 1 end
      end
      AttuneDB.chars = {}
    end
    AttuneDB.me = {}  -- throwaway until the character is known
    CreatePanel()
    LayoutPanel()
    ApplyPanelOption()
    CreateMinimapButton()
  elseif event == "PLAYER_ENTERING_WORLD" then
    DetectPfUI()
    ApplyTheme()
    if not bound then
      if BindCharacter() then timers.login = GetTime() + 10 end
    else
      timers.scan = GetTime() + 2
    end
    if RequestRaidInfo then RequestRaidInfo() end
  elseif event == "GUILD_ROSTER_UPDATE" then
    timers.roster = GetTime() + 0.5
  elseif event == "ZONE_CHANGED_NEW_AREA" then
    if bound then timers.scan = GetTime() + 2 end
  elseif event == "UPDATE_INSTANCE_INFO" then
    if bound then timers.scan = GetTime() + 1 end
  elseif event == "BAG_UPDATE" then
    if not bound then return end
    timers.scan = GetTime() + 2
  elseif event == "BANKFRAME_OPENED" then
    if not bound then return end
    ScanBags({-1, 5, 6, 7, 8, 9, 10})
    timers.scan = GetTime() + 1
  elseif event == "CHAT_MSG_ADDON" then
    if arg1 ~= PREFIX or arg4 == MyName() then return end
    local kind = string.sub(arg2, 1, 1)
    local body = string.sub(arg2, 3)
    if kind == "S" then
      AttuneDB.cache[arg4] = { t = time(), d = ParseStatus(body) }
      Refresh()
      timers.roster = GetTime() + 0.3
    elseif kind == "R" then
      if string.lower(body) == string.lower(MyName()) then
        timers.reply = GetTime() + 0.5
        if arg3 then replyDist[arg3] = true end
      end
    elseif kind == "O" then
      local _, _, who, key, v = string.find(body, "^([^~]+)~(%w+):(%d)$")
      if who and string.lower(who) == string.lower(MyName()) and FindRaid(key) then
        tinsert(pendingOverrides, { sender = arg4, key = key, v = v })
        GuildRoster()
        timers.override = GetTime() + 3
      end
    elseif kind == "Q" then
      timers.reply = GetTime() + 2 + math.random() * 10
    end
  end
end)

core:SetScript("OnUpdate", function()
  if not AttuneDB or not bound then return end
  local now = GetTime()
  if timers.login and now >= timers.login then
    timers.login = nil
    ScanAll()
    MaybeBroadcast(true)
    Send("Q")
  end
  if timers.scan and now >= timers.scan then
    timers.scan = nil
    ScanAll()
    MaybeBroadcast(false)
  end
  if timers.override and now >= timers.override then
    timers.override = nil
    for i = 1, getn(pendingOverrides) do
      local o = pendingOverrides[i]
      local rank = RankOf(o.sender)
      local r = FindRaid(o.key)
      if rank and rank <= OFFICER_MAX_RANK and r then
        if o.v == "1" then AttuneDB.me[o.key] = 1 else AttuneDB.me[o.key] = nil end
        Print(o.sender .. " set " .. r.label .. " to " .. (o.v == "1" and "attuned" or "not attuned") .. " for you.")
      else
        Print("Ignored an attunement change from " .. o.sender .. " (not an officer).")
      end
    end
    pendingOverrides = {}
    MaybeBroadcast(true)
  end
  if timers.roster and now >= timers.roster then
    timers.roster = nil
    RefreshRoster()
  end
  if timers.reply and now >= timers.reply then
    timers.reply = nil
    ScanAll()
    MaybeBroadcast(true)
    for dist in pairs(replyDist) do
      if dist ~= "GUILD" then
        SendAddonMessage(PREFIX, "S~" .. BuildStatus(), dist)
      end
    end
    replyDist = {}
  end

end)

-- ===== slash commands =====
ShowStatus = function(label, d, t)
  Print(label .. (t and (" (" .. AgeText(time() - t) .. ")") or ""))
  for i = 1, getn(RAIDS) do
    local s = "|cffff3333No|r"
    if d[RAIDS[i].key] then s = "|cff00ff00Attuned|r" end
    DEFAULT_CHAT_FRAME:AddMessage("  " .. RAIDS[i].label .. ": " .. s)
  end
end

SLASH_ATTUNE1 = "/attune"
SLASH_ATTUNE2 = "/attunely"
SlashCmdList["ATTUNE"] = function(msg)
  msg = msg or ""
  local _, _, cmd, rest = string.find(msg, "^(%S*)%s*(.-)$")
  cmd = string.lower(cmd or "")
  if cmd == "" then
    ScanAll()
    ShowStatus("You", ParseStatus(BuildStatus()))
  elseif cmd == "set" or cmd == "unset" then
    if not IsOfficerSelf() then
      Print("Only guild officers can use set/unset. Ask an officer.")
      return
    end
    local _, _, k, who = string.find(rest, "^(%S+)%s*(%S*)$")
    local r = FindRaid(k)
    if not r then
      Print("Usage: /attune " .. cmd .. " <key> [player]   Keys: ony mc bwl es nax kut ksm")
      return
    end
    if who == "" or string.lower(who) == string.lower(MyName()) then
      if cmd == "set" then AttuneDB.me[r.key] = 1 else AttuneDB.me[r.key] = nil end
      Print(r.label .. ": " .. cmd)
      MaybeBroadcast(true)
    else
      who = Capitalize(who)
      local v = 0
      if cmd == "set" then v = 1 end
      Send("O~" .. who .. "~" .. r.key .. ":" .. v)
      Print("Sent: " .. cmd .. " " .. r.label .. " for " .. who .. " (they must be online with the addon).")
    end
  elseif cmd == "who" then
    local r = FindRaid(rest)
    if not r then
      Print("Usage: /attune who <key>   Keys: ony mc bwl es nax kut ksm")
      return
    end
    local has, miss = {}, {}
    for name, e in pairs(AttuneDB.cache) do
      if e.d[r.key] then tinsert(has, name) else tinsert(miss, name) end
    end
    table.sort(has)
    table.sort(miss)
    Print(r.label .. " attuned (" .. getn(has) .. "): " .. table.concat(has, ", "))
    Print(r.label .. " NOT attuned (" .. getn(miss) .. "): " .. table.concat(miss, ", "))
  elseif cmd == "alts" then
    local names = {}
    for n in pairs(AttuneDB.chars) do tinsert(names, n) end
    table.sort(names)
    for i = 1, getn(names) do
      local list = {}
      for j = 1, getn(RAIDS) do
        if AttuneDB.chars[names[i]][RAIDS[j].key] then tinsert(list, RAIDS[j].label) end
      end
      Print(names[i] .. ": " .. (getn(list) > 0 and table.concat(list, ", ") or "none"))
    end
  elseif cmd == "probe" then
    Print("Quest sources on this client:")
    Print("  GetQuestsCompleted: " .. (type(GetQuestsCompleted) == "function" and "yes" or "no"))
    local h = getglobal("pfQuest_history")
    local n = 0
    if type(h) == "table" then for _ in pairs(h) do n = n + 1 end end
    Print("  pfQuest_history: " .. (type(h) == "table" and ("yes, " .. n .. " entries") or "no"))
    Print("  pfDB quest names: " .. ((type(getglobal("pfDB")) == "table" and type(getglobal("pfDB")["quests"]) == "table") and "yes" or "no"))
    Print("  Questie: " .. (type(getglobal("Questie")) == "table" and "yes" or "no"))
    for i = 1, getn(RAIDS) do
      local r = RAIDS[i]
      if r.quest then
        local list = ""
        for id in pairs(IdsForTitle(r.quest)) do
          list = list .. id .. (type(h) == "table" and h[id] and "(in history) " or "(not in history) ")
        end
        if list == "" then list = "no id found for this title" end
        Print("  " .. r.label .. " '" .. r.quest .. "': " .. list)
      end
    end
  elseif cmd == "hist" then
    local h = getglobal("pfQuest_history")
    local db = getglobal("pfDB")
    if type(h) ~= "table" then Print("No pfQuest history.") return end
    local list = {}
    for id, v in pairs(h) do tinsert(list, id) end
    table.sort(list)
    Print("pfQuest history, " .. getn(list) .. " quests. Searching for 'attun', 'core', 'command':")
    for i = 1, getn(list) do
      local id = list[i]
      local name = ""
      if type(db) == "table" and type(db["quests"]) == "table" then
        for _, sub in pairs(db["quests"]) do
          if type(sub) == "table" and type(sub[id]) == "table" and sub[id]["T"] then name = sub[id]["T"] end
        end
      end
      local l = string.lower(name)
      if string.find(l, "attun") or string.find(l, "core") or string.find(l, "command") then
        Print("  " .. id .. ": " .. name)
      end
    end
  elseif cmd == "debug" then
    Print("pfUI: " .. tostring(pfUI ~= nil) .. "  detail.backdrop: " .. tostring(GuildMemberDetailFrame and GuildMemberDetailFrame.backdrop ~= nil) .. "  roster.backdrop: " .. tostring(AttuneRosterFrame and AttuneRosterFrame.backdrop ~= nil))
  elseif cmd == "roster" then
    ToggleRoster()
  elseif cmd == "minimap" then
    AttuneDB.mm.hide = not AttuneDB.mm.hide
    ApplyMinimapVisibility()
    if AttuneDB.mm.hide then Print("Minimap button hidden.") else Print("Minimap button shown.") end
  elseif cmd == "refresh" then
    Send("Q")
    Print("Asked the guild to resend attunements.")
  else
    local name = string.upper(string.sub(cmd, 1, 1)) .. string.lower(string.sub(cmd, 2))
    local e = AttuneDB.cache[name]
    if e then
      ShowStatus(name, e.d, e.t)
    else
      Print("No data for " .. name .. ". Try /attune refresh")
    end
  end
end
