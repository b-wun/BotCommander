-- ============================================================================
-- 1. MAIN CONTAINER & FRAME SETUP
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

-- Top Target/Context Display (Centered)
local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
statusText:SetPoint("TOP", frame, "TOP", 0, -10)

-- Filter States (Default values until SavedVariables load)
local filterBotResponses = true   -- Incoming bot chatter ("following", etc.)
local filterMasterMessages = true -- Outgoing chat log commands sent by addon
local filterChatBubbles = true    -- World-space speech bubbles over head
local filterAddonMessages = false -- Local [BC] chat prints

-- Guaranteed Local Chat Print Helper (Respects filterAddonMessages)
local function PrintLocal(msg)
    if filterAddonMessages then return end
    local chat = SELECTED_CHAT_FRAME or DEFAULT_CHAT_FRAME or ChatFrame1
    if chat then
        chat:AddMessage("|cff33ff99[BC]|r " .. msg)
    end
end

local function UpdateTargetStatus()
    if UnitExists("target") and UnitIsPlayer("target") and UnitIsFriend("player", "target") and not UnitIsUnit("target", "player") then
        local targetName = UnitName("target")
        local _, classFileName = UnitClass("target")
        
        local colorStr = "ffffffff"
        if classFileName and RAID_CLASS_COLORS[classFileName] then
            local c = RAID_CLASS_COLORS[classFileName]
            colorStr = string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
        end
        
        statusText:SetText("|c" .. colorStr .. targetName .. "|r (/whisper)")
    elseif GetNumRaidMembers() > 0 then
        statusText:SetText("|cffff7f00Raid|r (/raid)")
    elseif GetNumPartyMembers() > 0 then
        statusText:SetText("|cff00ffffParty|r (/party)")
    else
        statusText:SetText("|cffffffffSolo / Local|r (/say)")
    end
end

-- Event Listener for Auto-Updating Target Status
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", UpdateTargetStatus)
UpdateTargetStatus()

-- Bot Confirmation Keywords
local botKeywords = { "following", "fleeing", "staying" }

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

-- Chat Message Filter
local function BotMessageFilter(self, event, msg, sender, ...)
    local playerName = UnitName("player")
    -- CHAT_MSG_WHISPER_INFORM passes the target's name as 'sender'
    local isOutgoing = (sender == playerName) or (event == "CHAT_MSG_WHISPER_INFORM")

    -- 1. Filter Master Messages (Suppress outgoing addon commands from chat log)
    if isOutgoing then
        if filterMasterMessages and IsRecentOutgoing(msg) then
            return true -- Silently drop outgoing echo
        end
        return false, msg, sender, ...
    end

    -- 2. Filter Bot Responses (Suppress incoming bot confirmations)
    if filterBotResponses then
        local lowerMsg = string.lower(msg)
        for _, word in ipairs(botKeywords) do
            if string.find(lowerMsg, word) then
                return true -- Silently drop matching bot replies
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

-- Non-Destructive Chat Bubble Scanner (Alpha-only toggle, prevents scale distortion)
local bubbleScanner = CreateFrame("Frame")
bubbleScanner:SetScript("OnUpdate", function(self, elapsed)
    if not filterChatBubbles then return end

    local children = { WorldFrame:GetChildren() }
    for _, child in ipairs(children) do
        if child:IsShown() and not child:GetName() then
            -- Exclude Nameplates (Nameplates contain StatusBars)
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

                            -- Check outgoing master command matches
                            if filterMasterMessages and IsRecentOutgoing(text) then
                                shouldHide = true
                            end

                            -- Check incoming bot keyword matches
                            if not shouldHide and filterBotResponses then
                                for _, word in ipairs(botKeywords) do
                                    if string.find(lowerText, word) then
                                        shouldHide = true
                                        break
                                    end
                                end
                            end

                            -- Alpha-only hiding (preserves scale matrix & backdrop dimensions)
                            if shouldHide then
                                child:SetAlpha(0)
                                for j = 1, child:GetNumRegions() do
                                    local r = select(j, child:GetRegions())
                                    if r then r:SetAlpha(0) end
                                end
                            else
                                -- Restore visibility for normal messages on recycled frames
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

-- Horn Toggle Button & Context Menu Setup
local filterBtn = CreateFrame("Button", nil, frame)
filterBtn:SetSize(16, 16)
filterBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
filterBtn:SetFrameLevel(closeBtn:GetFrameLevel() + 1)

local filterTex = filterBtn:CreateTexture(nil, "OVERLAY")
filterTex:SetTexture("Interface\\Icons\\inv_misc_horn_01")
filterTex:SetAllPoints(filterBtn)

local function UpdateFilterIcon()
    if filterBotResponses and filterMasterMessages and filterChatBubbles and filterAddonMessages then
        -- Dimmed icon ONLY when ALL 4 options are active (total silence)
        filterTex:SetVertexColor(0.4, 0.4, 0.4, 0.6)
    else
        -- Bright icon if at least one message/bubble type is unfiltered
        filterTex:SetVertexColor(1, 1, 1, 1)
    end
end

-- Native Dropdown Frame for Options Menu
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
-- 2. SMART DISPATCHER & BUTTON HELPERS
-- ============================================================================

-- Native Bot Command Dispatcher (Whisper > Raid > Party > Say)
local function SendBotCommand(chatMsg)
    if not chatMsg or chatMsg == "" then return end

    -- Queue command for outgoing echo & bubble suppression
    QueueOutgoingAddonMessage(chatMsg)

    if UnitExists("target") and UnitIsPlayer("target") and UnitIsFriend("player", "target") and not UnitIsUnit("target", "player") then
        local targetName = UnitName("target")
        SendChatMessage(chatMsg, "WHISPER", nil, targetName)
    elseif GetNumRaidMembers() > 0 then
        SendChatMessage(chatMsg, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendChatMessage(chatMsg, "PARTY")
    else
        SendChatMessage(chatMsg, "SAY")
    end
end

-- Delayed Dispatch Helper
local function SendBotCommandDelayed(chatMsg, delay)
    local timerFrame = CreateFrame("Frame")
    local totalElapsed = 0
    timerFrame:SetScript("OnUpdate", function(self, elapsed)
        totalElapsed = totalElapsed + elapsed
        if totalElapsed >= (delay or 0.15) then
            SendBotCommand(chatMsg)
            self:SetScript("OnUpdate", nil)
        end
    end)
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
        -- Hostile (Red), Neutral (Yellow), Friendly NPC (Green)
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
-- ============================================================================
-- 3. COMMAND BUTTONS (Grid Layout)
-- ============================================================================

-- Grid Coordinates
local col1 = 12       -- Left column X
local col2 = 90       -- Middle column X
local col3 = 168      -- Right column X
local btnW3 = 70      -- Width for 3-button rows

local hCol1 = 12      -- Left half X
local hCol2 = 129     -- Right half X
local btnW2 = 109     -- Width for 2-button rows

-- Row 1: Follow, Stay, Flee (Y: -30)
CreateGridButton(frame, "Follow", col1, -30, btnW3, function(self)
    PrintLocal("Follow")
    SendBotCommand("follow")
end)

CreateGridButton(frame, "Stay", col2, -30, btnW3, function(self)
    PrintLocal("Stay")
    SendBotCommand("stay")
end)

CreateGridButton(frame, "Flee", col3, -30, btnW3, function(self)
    PrintLocal("Flee")
    SendBotCommand("flee")
end)

-- Row 2: Attack, Pull, Pull Back (Y: -58)
-- Sends 'follow' on frame zero, then fires combat command 300ms later
CreateGridButton(frame, "Attack", col1, -58, btnW3, function(self)
    PrintLocal("Attack " .. GetFormattedTargetName() .. " (Clearing Stay)")
    SendBotCommand("follow")
    SendBotCommandDelayed("attack", 0.3)
end)

CreateGridButton(frame, "Pull", col2, -58, btnW3, function(self)
    PrintLocal("Pull " .. GetFormattedTargetName() .. " (Clearing Stay)")
    SendBotCommand("follow")
    SendBotCommandDelayed("pull", 0.3)
end)

CreateGridButton(frame, "Pull Back", col3, -58, btnW3, function(self)
    PrintLocal("Pull back from " .. GetFormattedTargetName() .. " (Clearing Stay)")
    SendBotCommand("follow")
    SendBotCommandDelayed("pull back", 0.3)
end)

-- Row 3: Pause, Unpause (Y: -86)
CreateGridButton(frame, "Pause", hCol1, -86, btnW2, function(self)
    PrintLocal("Pause (Strategy: +passive)")
    SendBotCommand("co +passive")
end)

CreateGridButton(frame, "Unpause", hCol2, -86, btnW2, function(self)
    PrintLocal("Unpause (Strategy: -passive)")
    SendBotCommand("co -passive")
end)

-- Row 4: Emergency Recovery (Y: -114)
CreateGridButton(frame, "Release", col1, -114, btnW3, function(self)
    PrintLocal("Releasing bot spirits")
    SendBotCommand("release")
end)

CreateGridButton(frame, "Revive", col2, -114, btnW3, function(self)
    PrintLocal("Reviving dead bots")
    SendBotCommand("revive")
end)

CreateGridButton(frame, "Summon", col3, -114, btnW3, function(self)
    PrintLocal("Summoning bots to location")
    SendBotCommand("summon")
end)
-- ============================================================================
-- 4. SLASH COMMAND (/botc)
-- ============================================================================
SLASH_BOTCOMMANDER1 = "/botc"
SlashCmdList["BOTCOMMANDER"] = function()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- ============================================================================
-- 5. MINIMAP BUTTON (Click to Toggle, Drag to Reposition)
-- ============================================================================
local minimapBtn = CreateFrame("Button", "BotCommanderMinimapBtn", Minimap)
minimapBtn:SetSize(33, 33)
minimapBtn:SetFrameStrata("MEDIUM")
minimapBtn:SetFrameLevel(8)

-- Icon (Command / Battle Stance icon)
local icon = minimapBtn:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\Icons\\Ability_Warrior_OffensiveStance")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", 0, 0)

-- Circular Border Overlay
local border = minimapBtn:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(54, 54)
border:SetPoint("TOPLEFT", 0, 0)

-- Position around the minimap ring
local btnAngle = 45

local function UpdateButtonPosition()
    local radius = 80
    local x = math.cos(math.rad(btnAngle)) * radius
    local y = math.sin(math.rad(btnAngle)) * radius
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end
UpdateButtonPosition()

-- Circular Dragging
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

-- Click Action (Toggle Main Frame)
minimapBtn:SetScript("OnClick", function()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end)

-- Hover Tooltip
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