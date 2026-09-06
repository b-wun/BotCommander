-- ============================================================================
-- 1. STATE VARIABLES & CORE HELPERS
-- ============================================================================

-- Filter States (Defaults until SavedVariables load)
local filterBotResponses = true   -- Incoming bot chatter ("following", etc.)
local filterMasterMessages = true -- Outgoing chat log commands sent by addon
local filterChatBubbles = true    -- World-space speech bubbles over head
local filterAddonMessages = false -- Local [BC] chat prints

-- Bot Confirmation Keywords
local botKeywords = { "following", "fleeing", "staying" }

-- Guaranteed Local Chat Print Helper (Respects filterAddonMessages)
local function PrintLocal(msg)
    if filterAddonMessages then return end
    local chat = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME or ChatFrame1
    if chat then
        chat:AddMessage("|cff33ff99[BC]|r " .. msg)
    end
end

-- Outgoing Command Tracker (Timestamp expiration avoids filter race conditions)
local recentOutgoingCommands = {}

local function QueueOutgoingAddonMessage(msg)
    if not msg or msg == "" then return end
    local clean = string.gsub(msg, "^%s*(.-)%s*$", "%1")
    recentOutgoingCommands[clean] = GetTime() + 3.0 -- Keep active for 3 seconds
end

local function IsRecentOutgoing(msg)
    if not msg then return false end
    local clean = string.gsub(msg, "^%s*(.-)%s*$", "%1")
    local expiry = recentOutgoingCommands[clean]
    if expiry then
        if GetTime() <= expiry then
            return true
        else
            recentOutgoingCommands[clean] = nil
        end
    end
    return false
end

-- ============================================================================
-- 2. COMMAND DISPATCHER & UI HELPERS
-- ============================================================================

-- Role Modifier Key Detector & Display Label
local function GetRoleInfo()
    local isCtrl = IsControlKeyDown()
    local isShift = IsShiftKeyDown()
    local isAlt = IsAltKeyDown()

    -- Compound Modifiers
    if isCtrl and isShift then
        return "@meleedps ", "MDPS "
    elseif isAlt and isShift then
        return "@rangeddps ", "RDPS "
    elseif isAlt and isCtrl then
        return "@ranged ", "Ranged "
    -- Single Modifiers
    elseif isCtrl then
        return "@tank ", "Tank "
    elseif isShift then
        return "@dps ", "DPS "
    elseif isAlt then
        return "@heal ", "Heal "
    end

    return "", ""
end

-- Backward compatibility wrapper for existing grid button calls
local function GetRolePrefix()
    local prefix, _ = GetRoleInfo()
    return prefix
end

-- Native Bot Command Dispatcher (Whisper > Raid > Party > Say)
local function SendBotCommand(chatMsg, overridePrefix)
    if not chatMsg or chatMsg == "" then return end

    local prefix = overridePrefix or GetRolePrefix()
    local finalMsg = prefix .. chatMsg

    -- Queue command for outgoing echo & bubble suppression
    QueueOutgoingAddonMessage(finalMsg)

    -- If a role modifier is held (prefix ~= ""), force Group Broadcast
    if prefix ~= "" then
        if GetNumRaidMembers() > 0 then
            SendChatMessage(finalMsg, "RAID")
        elseif GetNumPartyMembers() > 0 then
            SendChatMessage(finalMsg, "PARTY")
        else
            SendChatMessage(finalMsg, "SAY")
        end

    -- Normal Behavior: Direct target whisper takes precedence when NO modifier is held
    elseif UnitExists("target") and UnitIsPlayer("target") and UnitIsFriend("player", "target") and not UnitIsUnit("target", "player") then
        local targetName = UnitName("target")
        SendChatMessage(finalMsg, "WHISPER", nil, targetName)
    elseif GetNumRaidMembers() > 0 then
        SendChatMessage(finalMsg, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendChatMessage(finalMsg, "PARTY")
    else
        SendChatMessage(finalMsg, "SAY")
    end
end

-- Delayed Dispatch Helper (Preserves role prefix across frame delays)
local function SendBotCommandDelayed(chatMsg, delay, overridePrefix)
    local prefix = overridePrefix or GetRolePrefix()
    local timerFrame = CreateFrame("Frame")
    local totalElapsed = 0
    timerFrame:SetScript("OnUpdate", function(self, elapsed)
        totalElapsed = totalElapsed + elapsed
        if totalElapsed >= (delay or 0.15) then
            SendBotCommand(chatMsg, prefix)
            self:SetScript("OnUpdate", nil)
        end
    end)
end

-- Target Name Formatter
local function GetFormattedTargetName()
    if not UnitExists("target") then return "target" end
    
    local name = UnitName("target")
    if UnitIsPlayer("target") then
        local _, classFileName = UnitClass("target")
        if classFileName and RAID_CLASS_COLORS[classFileName] then
            local c = RAID_CLASS_COLORS[classFileName]
            return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name)
        end
    else
        if UnitIsEnemy("player", "target") then
            return "|cffff3333" .. name .. "|r"
        elseif UnitIsFriend("player", "target") then
            return "|cff33ff33" .. name .. "|r"
        else
            return "|cffffffff22" .. name .. "|r"
        end
    end
    return name
end

-- Grid Button Helper supporting Direct Strings and Custom Functions
local function CreateGridButton(parent, text, xOffset, yOffset, width, chatMsg)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width, 24)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    btn:SetText(text)
    btn:SetScript("OnClick", function(self)
        if type(chatMsg) == "function" then
            chatMsg(self)
        elseif type(chatMsg) == "string" then
            SendBotCommand(chatMsg)
        end
    end)
    return btn
end

-- ============================================================================
-- 3. MAIN CONTAINER & FRAME SETUP
-- ============================================================================

local frame = CreateFrame("Frame", "BotCommanderFrame", UIParent)
frame:SetSize(250, 150)
frame:SetPoint("CENTER", 0, 0)
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
frame:SetBackdropColor(0, 0, 0, 0.85)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

-- Close Button
local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

-- Top Target/Context Display Container (Enables Hover Tooltip)
local statusBtn = CreateFrame("Button", nil, frame)
statusBtn:SetSize(140, 20)
statusBtn:SetPoint("TOP", frame, "TOP", 0, -6)

local statusText = statusBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
statusText:SetPoint("CENTER", statusBtn, "CENTER", 0, 0)

-- Header Hover Tooltip (Role Keybindings Legend)
statusBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:SetText("Command Dispatch Context", 1, 1, 1)
    GameTooltip:AddLine("Commands automatically target your active context.", 0.8, 0.8, 0.8)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Hold Modifier Keys to Target Roles:", 0.3, 1, 0.6)
    GameTooltip:AddLine("CTRL: Tank (@tank)", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("SHIFT: DPS (@dps)", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("ALT: Heal (@heal)", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("CTRL + SHIFT: MDPS (@meleedps)", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("ALT + SHIFT: RDPS (@rangeddps)", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("ALT + CTRL: Ranged (@ranged)", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)

statusBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Updates context text dynamically with role prefixes (e.g., "DPS Party")
local function UpdateTargetStatus()
    local prefix, roleLabel = GetRoleInfo()
    local prefixStr = (roleLabel ~= "") and ("|cffffd100" .. roleLabel .. "|r ") or ""

    -- If NO modifier is held, default to individual target whisper if valid
    if prefix == "" and UnitExists("target") and UnitIsPlayer("target") and UnitIsFriend("player", "target") and not UnitIsUnit("target", "player") then
        local targetName = UnitName("target")
        local _, classFileName = UnitClass("target")
        
        local colorStr = "ffffffff"
        if classFileName and RAID_CLASS_COLORS[classFileName] then
            local c = RAID_CLASS_COLORS[classFileName]
            colorStr = string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
        end
        
        statusText:SetText("|c" .. colorStr .. targetName .. "|r")
    -- If a modifier IS held (or no valid target exists), display group broadcast context
    elseif GetNumRaidMembers() > 0 then
        statusText:SetText(prefixStr .. "|cffff7f00Raid|r")
    elseif GetNumPartyMembers() > 0 then
        statusText:SetText(prefixStr .. "|cff00ffffParty|r")
    else
        statusText:SetText(prefixStr .. "|cffffffffSolo|r")
    end
end

-- Event Listener for Auto-Updating Target & Modifier Key State
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("MODIFIER_STATE_CHANGED") -- Live modifier key detection
eventFrame:SetScript("OnEvent", UpdateTargetStatus)
UpdateTargetStatus()

-- Header Drink Button (Top-Left)
local drinkBtn = CreateFrame("Button", nil, frame)
drinkBtn:SetSize(18, 18)
drinkBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6)

local drinkTex = drinkBtn:CreateTexture(nil, "ARTWORK")
drinkTex:SetAllPoints()
drinkTex:SetTexture("Interface\\Icons\\INV_Drink_05")
drinkBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

drinkBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Order Bots to Drink", 1, 1, 1)
    GameTooltip:AddLine("Tells mana/resource-based bots to sit and drink.", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)

drinkBtn:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

drinkBtn:SetScript("OnClick", function(self)
    PrintLocal("Drink")
    SendBotCommand("drink")
end)

-- Horn Toggle Button & Context Menu Setup (Top-Right)
local filterBtn = CreateFrame("Button", nil, frame)
filterBtn:SetSize(16, 16)
filterBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
filterBtn:SetFrameLevel(closeBtn:GetFrameLevel() + 1)

local filterTex = filterBtn:CreateTexture(nil, "OVERLAY")
filterTex:SetTexture("Interface\\Icons\\inv_misc_horn_01")
filterTex:SetAllPoints(filterBtn)

local function UpdateFilterIcon()
    if filterBotResponses and filterMasterMessages and filterChatBubbles and filterAddonMessages then
        filterTex:SetVertexColor(0.4, 0.4, 0.4, 0.6)
    else
        filterTex:SetVertexColor(1, 1, 1, 1)
    end
end

local menuFrame = CreateFrame("Frame", "BotCommanderFilterMenu", frame, "UIDropDownMenuTemplate")

filterBtn:SetScript("OnClick", function(self)
    local menuList = {
        { text = "Chat Filter Options", isTitle = true, notCheckable = true },
        { 
            text = "Bot Responses", 
            checked = function() return filterBotResponses end, 
            func = function() 
                filterBotResponses = not filterBotResponses 
                BotCommanderDB.filterBotResponses = filterBotResponses
                UpdateFilterIcon()
            end, 
            keepShownOnClick = true 
        },
        { 
            text = "Master Messages", 
            checked = function() return filterMasterMessages end, 
            func = function() 
                filterMasterMessages = not filterMasterMessages 
                BotCommanderDB.filterMasterMessages = filterMasterMessages
                UpdateFilterIcon()
            end, 
            keepShownOnClick = true 
        },
        { 
            text = "Chat Bubbles", 
            checked = function() return filterChatBubbles end, 
            func = function() 
                filterChatBubbles = not filterChatBubbles 
                BotCommanderDB.filterChatBubbles = filterChatBubbles
                UpdateFilterIcon()
            end, 
            keepShownOnClick = true 
        },
        { 
            text = "Addon Messages", 
            checked = function() return filterAddonMessages end, 
            func = function() 
                filterAddonMessages = not filterAddonMessages 
                BotCommanderDB.filterAddonMessages = filterAddonMessages
                UpdateFilterIcon()
            end, 
            keepShownOnClick = true 
        },
    }
    EasyMenu(menuList, menuFrame, self, 0, 0, "MENU")
end)

filterBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
    GameTooltip:AddLine("Configure Chat Filters")
    GameTooltip:AddLine("Click to toggle message suppression settings", 1, 1, 1)
    GameTooltip:Show()
end)

filterBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- SavedVariables Listener (Loads saved settings on startup)
local dbFrame = CreateFrame("Frame")
dbFrame:RegisterEvent("ADDON_LOADED")
dbFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "BotCommander" then
        BotCommanderDB = BotCommanderDB or {}
        
        if BotCommanderDB.filterBotResponses == nil then BotCommanderDB.filterBotResponses = true end
        if BotCommanderDB.filterMasterMessages == nil then BotCommanderDB.filterMasterMessages = true end
        if BotCommanderDB.filterChatBubbles == nil then BotCommanderDB.filterChatBubbles = true end
        if BotCommanderDB.filterAddonMessages == nil then BotCommanderDB.filterAddonMessages = false end

        filterBotResponses = BotCommanderDB.filterBotResponses
        filterMasterMessages = BotCommanderDB.filterMasterMessages
        filterChatBubbles = BotCommanderDB.filterChatBubbles
        filterAddonMessages = BotCommanderDB.filterAddonMessages
        
        UpdateFilterIcon()
        self:UnunregisterEvent("ADDON_LOADED")
    end
end)

-- ============================================================================
-- 4. CHAT & SPEECH BUBBLE FILTERS
-- ============================================================================

-- Chat Message Filter
local function BotMessageFilter(self, event, msg, sender, ...)
    local playerName = UnitName("player")
    local isOutgoing = (sender == playerName) or (event == "CHAT_MSG_WHISPER_INFORM")

    if isOutgoing then
        if filterMasterMessages and IsRecentOutgoing(msg) then
            return true
        end
        return false, msg, sender, ...
    end

    if filterBotResponses then
        local lowerMsg = string.lower(msg)
        for _, word in ipairs(botKeywords) do
            if string.find(lowerMsg, word) then
                return true
            end
        end
    end

    return false, msg, sender, ...
end

-- Register Filters Across Incoming & Outgoing Channels
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", BotMessageFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", BotMessageFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY", BotMessageFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_PARTY_LEADER", BotMessageFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID", BotMessageFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_RAID_LEADER", BotMessageFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", BotMessageFilter)

-- Non-Destructive Chat Bubble Scanner (Alpha-only toggle)
local bubbleScanner = CreateFrame("Frame")
bubbleScanner:SetScript("OnUpdate", function(self, elapsed)
    if not filterChatBubbles then return end

    local children = { WorldFrame:GetChildren() }
    for _, child in ipairs(children) do
        if child:IsShown() and not child:GetName() then
            local isNameplate = false
            for i = 1, child:GetNumChildren() do
                local sub = select(i, child:GetChildren())
                if sub and sub:GetObjectType() == "StatusBar" then
                    isNameplate = true
                    break
                end
            end

            if not isNameplate then
                for i = 1, child:GetNumRegions() do
                    local region = select(i, child:GetRegions())
                    if region and region:GetObjectType() == "FontString" then
                        local text = region:GetText()
                        if text and text ~= "" then
                            local lowerText = string.lower(text)
                            local shouldHide = false

                            if filterMasterMessages and IsRecentOutgoing(text) then
                                shouldHide = true
                            end

                            if not shouldHide and filterBotResponses then
                                for _, word in ipairs(botKeywords) do
                                    if string.find(lowerText, word) then
                                        shouldHide = true
                                        break
                                    end
                                end
                            end

                            if shouldHide then
                                child:SetAlpha(0)
                                for j = 1, child:GetNumRegions() do
                                    local r = select(j, child:GetRegions())
                                    if r then r:SetAlpha(0) end
                                end
                            else
                                child:SetAlpha(1)
                                for j = 1, child:GetNumRegions() do
                                    local r = select(j, child:GetRegions())
                                    if r then r:SetAlpha(1) end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- ============================================================================
-- 5. COMMAND BUTTONS (Grid Layout)
-- ============================================================================

local col1 = 12       -- Left column X
local col2 = 90       -- Middle column X
local col3 = 168      -- Right column X
local btnW3 = 70      -- Width for 3-button rows

local hCol1 = 12      -- Left half X
local hCol2 = 129     -- Right half X
local btnW2 = 109     -- Width for 2-button rows

-- Row 1: Follow, Stay, Flee (Y: -30)
CreateGridButton(frame, "Follow", col1, -30, btnW3, function(self)
    local prefix = GetRolePrefix()
    PrintLocal(prefix .. "Follow")
    SendBotCommand("follow", prefix)
end)

CreateGridButton(frame, "Stay", col2, -30, btnW3, function(self)
    local prefix = GetRolePrefix()
    PrintLocal(prefix .. "Stay")
    SendBotCommand("stay", prefix)
end)

CreateGridButton(frame, "Flee", col3, -30, btnW3, function(self)
    local prefix = GetRolePrefix()
    PrintLocal(prefix .. "Flee")
    SendBotCommand("flee", prefix)
end)

-- Row 2: Attack, Pull, Pull Back (Y: -58)
CreateGridButton(frame, "Attack", col1, -58, btnW3, function(self)
    local prefix = GetRolePrefix()
    PrintLocal(prefix .. "Attack " .. GetFormattedTargetName() .. " (Clearing Stay)")
    SendBotCommand("follow", prefix)
    SendBotCommandDelayed("attack", 0.3, prefix)
end)

CreateGridButton(frame, "Pull", col2, -58, btnW3, function(self)
    local prefix = GetRolePrefix()
    PrintLocal(prefix .. "Pull " .. GetFormattedTargetName() .. " (Clearing Stay)")
    SendBotCommand("follow", prefix)
    SendBotCommandDelayed("pull", 0.3, prefix)
end)

CreateGridButton(frame, "Pull Back", col3, -58, btnW3, function(self)
    local prefix = GetRolePrefix()
    PrintLocal(prefix .. "Pull back from " .. GetFormattedTargetName() .. " (Clearing Stay)")
    SendBotCommand("follow", prefix)
    SendBotCommandDelayed("pull back", 0.3, prefix)
end)

-- Row 3: Pause, Unpause (Y: -86)
CreateGridButton(frame, "Pause", hCol1, -86, btnW2, function(self)
    local prefix = GetRolePrefix()
    PrintLocal(prefix .. "Pause (Strategy: +passive)")
    SendBotCommand("co +passive", prefix)
end)

CreateGridButton(frame, "Unpause", hCol2, -86, btnW2, function(self)
    local prefix = GetRolePrefix()
    PrintLocal(prefix .. "Unpause (Strategy: -passive)")
    SendBotCommand("co -passive", prefix)
end)

-- Row 4: Emergency Recovery (Y: -114)
CreateGridButton(frame, "Release", col1, -114, btnW3, function(self)
    local prefix = GetRolePrefix()
    PrintLocal(prefix .. "Releasing bot spirits")
    SendBotCommand("release", prefix)
end)

CreateGridButton(frame, "Revive", col2, -114, btnW3, function(self)
    local prefix = GetRolePrefix()
    PrintLocal(prefix .. "Reviving dead bots")
    SendBotCommand("revive", prefix)
end)

CreateGridButton(frame, "Summon", col3, -114, btnW3, function(self)
    local prefix = GetRolePrefix()
    PrintLocal(prefix .. "Summoning bots to location")
    SendBotCommand("summon", prefix)
end)

-- ============================================================================
-- 6. SLASH COMMAND & MINIMAP BUTTON
-- ============================================================================

SLASH_BOTCOMMANDER1 = "/botc"
SlashCmdList["BOTCOMMANDER"] = function()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

local minimapBtn = CreateFrame("Button", "BotCommanderMinimapBtn", Minimap)
minimapBtn:SetSize(33, 33)
minimapBtn:SetFrameStrata("MEDIUM")
minimapBtn:SetFrameLevel(8)

local icon = minimapBtn:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\Icons\\Ability_Warrior_OffensiveStance")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", 0, 0)

local border = minimapBtn:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(54, 54)
border:SetPoint("TOPLEFT", 0, 0)

local btnAngle = 45

local function UpdateButtonPosition()
    local radius = 80
    local x = math.cos(math.rad(btnAngle)) * radius
    local y = math.sin(math.rad(btnAngle)) * radius
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end
UpdateButtonPosition()

minimapBtn:RegisterForDrag("LeftButton")
minimapBtn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local mx, my = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        local cx, cy = Minimap:GetCenter()
        local dx, dy = (mx / scale) - cx, (my / scale) - cy
        btnAngle = math.deg(math.atan2(dy, dx))
        UpdateButtonPosition()
    end)
end)

minimapBtn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)

minimapBtn:SetScript("OnClick", function()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end)

minimapBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Bot Commander")
    GameTooltip:AddLine("Left-Click: Toggle Panel", 1, 1, 1)
    GameTooltip:AddLine("Left-Drag: Reposition Icon", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)

minimapBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)
