-- StormkeeperTracker.lua
-- Copyright (c) 2026 Your Name
-- Licensed under the MIT License. See LICENSE for details.

-- Initialize SavedVariables table
StormkeeperTrackerDB = StormkeeperTrackerDB or {}

local ADDON_NAME = "StormkeeperTracker"
local STORMKEEPER_SPELL_ID = 191634
local STORMKEEPER_ICON_ID = 839977
local LIGHTNING_BOLT_SPELL_ID = 188196
local CHAIN_LIGHTNING_SPELL_ID = 188443
local TEMPEST_SPELL_ID = 452201
local ARC_DISCHARGE_SPELL_ID = 455096

local TIER_SET_ITEM_IDS = { 249977, 249978, 249979, 249980, 249982 }
local TIER_SET_4PC_THRESHOLD = 4
local SK_BASE_CHARGES = 2
local SK_MAX_CHARGES = 4
local SK_DURATION = 15
local UPDATE_INTERVAL = 0.1

local previewActive = false
local defaults = {
    iconWidth   = 50,
    iconHeight = 50,
    fontSize   = 14,
    fontColorR = 1,
    fontColorG = 1,
    fontColorB = 1,
    debugMode = false,
}

-- ============================================================
-- UI Setup
-- ============================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "Frame", UIParent)
frame:SetSize(defaults.iconWidth, defaults.iconWidth)
frame:SetPoint("CENTER", UIParent, "CENTER")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint()
    StormkeeperTrackerDB.point = point
    StormkeeperTrackerDB.relativePoint = relativePoint
    StormkeeperTrackerDB.x = x
    StormkeeperTrackerDB.y = y
end)

local icon = frame:CreateTexture(nil, "BACKGROUND")
icon:SetAllPoints(frame)
icon:SetTexture(STORMKEEPER_ICON_ID)

local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
cooldown:SetAllPoints(frame)
cooldown:SetDrawEdge(true)
cooldown:SetDrawSwipe(true)
cooldown:SetSwipeColor(0, 0, 0, 0.7)

local chargeText = cooldown:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
chargeText:SetPoint("BOTTOM", frame, "TOP", 0, 0)
chargeText:SetTextColor(1, 1, 1, 1)

frame:Hide()

-- ============================================================
-- Config
-- ============================================================

local function InitConfig()
    -- Fill in any missing keys with defaults 
    for k, v in pairs(defaults) do
        if StormkeeperTrackerDB[k] == nil then
            StormkeeperTrackerDB[k] = v
        end
    end
end

local function ApplyConfig()
    local db = StormkeeperTrackerDB
    frame:SetSize(db.iconWidth, db.iconHeight)
    local fontFace, _, fontFlags = chargeText:GetFont()
    chargeText:SetFont("fonts/2002b.ttf", db.fontSize, fontFlags)
    chargeText:SetTextColor(db.fontColorR, db.fontColorG, db.fontColorB, 1)
end

-- ============================================================
-- State
-- ============================================================

local skCharges = nil
local skExpiration = nil
local timeSinceLastUpdate = 0

-- ============================================================
-- Logging
-- ============================================================
local LOG_LEVEL = {
    ERROR = 1,
    INFO  = 2,
    DEBUG = 3,
}

local LOG_COLORS = {
    [LOG_LEVEL.ERROR] = "|cffff3333",  -- Red
    [LOG_LEVEL.INFO] = "|cff00ccff",  -- Blue
    [LOG_LEVEL.DEBUG] = "|cffaaaaaa",  -- Grey
}

local function SKPrint(msg, level)
    level = level or LOG_LEVEL.INFO

    -- ERROR always prints regardless of debug mode
    if level > LOG_LEVEL.INFO and not StormkeeperTrackerDB.debugMode then 
        return
    end

    local color = LOG_COLORS[level] or LOG_COLORS[LOG_LEVEL.INFO]
    print(color .. "[SK Tracker]|r " .. msg)
end

-- ============================================================
-- Tracker UI Update
-- ============================================================

local function UpdateUI()
    if skCharges and skCharges > 0 then
        frame:Show()
        chargeText:SetText(tostring(skCharges))
        if skExpiration then
            local remaining = skExpiration - GetTime()
            cooldown:SetCooldown(GetTime() - (SK_DURATION - remaining), SK_DURATION)
        end
    else
        frame:Hide()
        cooldown:Clear()
    end
end

frame:SetScript("OnUpdate", function(self, elapsed)
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    if timeSinceLastUpdate >= UPDATE_INTERVAL then
        timeSinceLastUpdate = 0
        CheckExpiration()
    end
end)

-- ============================================================
-- Addon Settings Wrappers 
-- ============================================================

local function SetIconSize(width, height)
    width = math.max(20, math.min(100, tonumber(width) or defaults.iconWidth))
    height = math.max(20, math.min(100, tonumber(height) or defaults.iconHeight))
    StormkeeperTrackerDB.iconWidth = width
    StormkeeperTrackerDB.iconHeight = height
    ApplyConfig()
    SKPrint(string.format("Icon size set to %d,%d", width, height), LOG_LEVEL.DEBUG)
end

local function SetFontSize(value)
    value = math.max(8, math.min(56, tonumber(value) or defaults.fontSize))
    StormkeeperTrackerDB.fontSize = value
    ApplyConfig()
    SKPrint(string.format("Font size set to %d", value), LOG_LEVEL.DEBUG)
end

local function SetFontColor(r, g, b)
    r = math.max(0, math.min(1, tonumber(r) or 1))
    g = math.max(0, math.min(1, tonumber(g) or 1))
    b = math.max(0, math.min(1, tonumber(b) or 1))
    StormkeeperTrackerDB.fontColorR = r
    StormkeeperTrackerDB.fontColorG = g
    StormkeeperTrackerDB.fontColorB = b
    ApplyConfig()
    SKPrint("Font color updated.", LOG_LEVEL.DEBUG)
end

local function SetDebugMode(enabled)
    StormkeeperTrackerDB.debugMode = enabled
    SKPrint("Debug mode " .. (enabled and "enabled." or "disabled."), LOG_LEVEL.DEBUG)
end

-- ============================================================
-- Color Picker
-- ============================================================

local function OnColorChanged()
    local newR, newG, newB = ColorPickerFrame:GetColorRGB()
    SetFontColor(newR, newG, newB)
end

local function OnColorCancel()
    local newR, newG, newB = ColorPickerFrame:GetPreviousValues()
	SetFontColor(newR, newG, newB)
end

local function OpenFontColorPicker()
    local db = StormkeeperTrackerDB
    local previousR, previousG, previousB = db.fontColorR, db.fontColorG, db.fontColorB

    local options = {
        swatchFunc = OnColorChanged,
        opacityFunc = OnColorChanged,
        cancelFunc = OnColorCancel,
        hasOpacity = false,
        opacity = 1,
        r = previousR,
        g = previousG,
        b = previousB,
    }

    ColorPickerFrame:SetupColorPickerAndShow(options)
end

-- ============================================================
-- Settings Frame
-- ============================================================

local settingsFrame = nil

local PREVIEW_CYCLE_INTERVAL = 1.0  -- Seconds per charge step

local function StartPreviewLoop(f)
    local timeSinceStep = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        timeSinceStep = timeSinceStep + elapsed
        if timeSinceStep >= PREVIEW_CYCLE_INTERVAL then
            timeSinceStep = 0
            -- Cycle charges.
            local next = ((skCharges or 0) % SK_MAX_CHARGES) + 1
            skCharges    = next
            skExpiration = GetTime() + SK_DURATION
            UpdateUI()
        end
    end)
end

local function StopPreviewLoop(f)
    f:SetScript("OnUpdate", nil)
    -- Only clear state if a real SK aura isn't active
    if not previewActive then
        skCharges    = nil
        skExpiration = nil
        UpdateUI()
    end
end

local function BuildSettingsFrame()
    local f = CreateFrame("Frame", ADDON_NAME .. "SettingsFrame", UIParent, "BackdropTemplate")
    f:SetSize(300, 500)
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetFrameStrata("DIALOG")
    f:Hide()

    -- Native dark panel backdrop
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile     = true,
        tileSize = 32,
        edgeSize = 32,
        insets   = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    -- Title bar text
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOP", f, "TOP", 0, -16)
    title:SetText("Stormkeeper Tracker")

    -- Divider line under title
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface/DialogFrame/UI-DialogBox-Header")
    divider:SetSize(220, 10)
    divider:SetPoint("TOP", title, "BOTTOM", 0, -8)

    -- Helper to create a labeled row with consistent vertical spacing
    local function CreateLabel(parent, text, anchorTo, offsetY)
        local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, offsetY)
        label:SetText(text)
        return label
    end

    -- Icon Width slider
    local iconWidthLabel = CreateLabel(f, "Icon Width", divider, -16)

    local iconWidthSlider = CreateFrame("Slider", nil, f, "UISliderTemplateWithLabels")
    iconWidthSlider:SetSize(220, 16)
    iconWidthSlider:SetPoint("TOPLEFT", iconWidthLabel, "BOTTOMLEFT", 0, -8)
    iconWidthSlider:SetMinMaxValues(20, 100)
    iconWidthSlider:SetValueStep(1)
    iconWidthSlider:SetObeyStepOnDrag(true)
    iconWidthSlider:SetValue(StormkeeperTrackerDB.iconWidth)
    iconWidthSlider.Low:SetText("20")
    iconWidthSlider.High:SetText("100")

    local iconWidthValue = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    iconWidthValue:SetPoint("LEFT", iconWidthSlider, "RIGHT", 8, 0)
    iconWidthValue:SetText(tostring(StormkeeperTrackerDB.iconWidth))

    iconWidthSlider:SetScript("OnValueChanged", function(self, value)
        local snapped = math.floor(value + 0.5)
        iconWidthValue:SetText(tostring(snapped))
        SetIconSize(snapped, StormkeeperTrackerDB.iconHeight)
    end)

    -- Icon Height slider 
    local iconHeightLabel = CreateLabel(f, "Icon Height", iconWidthSlider, -16)

    local iconHeightSlider = CreateFrame("Slider", nil, f, "UISliderTemplateWithLabels")
    iconHeightSlider:SetSize(220, 16)
    iconHeightSlider:SetPoint("TOPLEFT", iconHeightLabel, "BOTTOMLEFT", 0, -8)
    iconHeightSlider:SetMinMaxValues(20, 100)
    iconHeightSlider:SetValueStep(1)
    iconHeightSlider:SetObeyStepOnDrag(true)
    iconHeightSlider:SetValue(StormkeeperTrackerDB.iconHeight)
    iconHeightSlider.Low:SetText("20")
    iconHeightSlider.High:SetText("100")

    local iconHeightValue = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    iconHeightValue:SetPoint("LEFT", iconHeightSlider, "RIGHT", 8, 0)
    iconHeightValue:SetText(tostring(StormkeeperTrackerDB.iconHeight))

    iconHeightSlider:SetScript("OnValueChanged", function(self, value)
        local snapped = math.floor(value + 0.5)
        iconHeightValue:SetText(tostring(snapped))
        SetIconSize(StormkeeperTrackerDB.iconWidth, snapped)
    end)

    --  Font Size slider
    local fontSizeLabel = CreateLabel(f, "Font Size", iconHeightSlider, -16)

    local fontSizeSlider = CreateFrame("Slider", nil, f, "UISliderTemplateWithLabels")
    fontSizeSlider:SetSize(220, 16)
    fontSizeSlider:SetPoint("TOPLEFT", fontSizeLabel, "BOTTOMLEFT", 0, -8)
    fontSizeSlider:SetMinMaxValues(8, 56)
    fontSizeSlider:SetValueStep(1)
    fontSizeSlider:SetObeyStepOnDrag(true)
    fontSizeSlider:SetValue(StormkeeperTrackerDB.fontSize)
    fontSizeSlider.Low:SetText("8")
    fontSizeSlider.High:SetText("56")

    local fontSizeValue = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fontSizeValue:SetPoint("LEFT", fontSizeSlider, "RIGHT", 8, 0)
    fontSizeValue:SetText(tostring(StormkeeperTrackerDB.fontSize))

    fontSizeSlider:SetScript("OnValueChanged", function(self, value)
        local snapped = math.floor(value + 0.5)
        fontSizeValue:SetText(tostring(snapped))
        SetFontSize(snapped)
    end)

    -- Font Color button
    local colorButton = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    colorButton:SetSize(140, 24)
    colorButton:SetPoint("TOPLEFT", fontSizeSlider, "BOTTOMLEFT", -8, -20)
    colorButton:SetText("Choose Font Color...")
    colorButton:SetScript("OnClick", function() OpenFontColorPicker() end)

    -- Small color swatch preview next to the button
    local colorSwatch = f:CreateTexture(nil, "OVERLAY")
    colorSwatch:SetSize(20, 20)
    colorSwatch:SetPoint("LEFT", colorButton, "RIGHT", 8, 0)
    colorSwatch:SetColorTexture(
        StormkeeperTrackerDB.fontColorR,
        StormkeeperTrackerDB.fontColorG,
        StormkeeperTrackerDB.fontColorB,
        1
    )

    -- Keep the swatch in sync when the color picker updates
    -- Hook SetFontColor to also refresh the swatch
    local originalSetFontColor = SetFontColor
    SetFontColor = function(r, g, b)
        originalSetFontColor(r, g, b)
        colorSwatch:SetColorTexture(r, g, b, 1)
    end

    --  Debug Mode checkbox 
    local debugCheckbox = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    debugCheckbox:SetPoint("TOPLEFT", colorButton, "BOTTOMLEFT", -4, -12)
    debugCheckbox:SetChecked(StormkeeperTrackerDB.debugMode)
    debugCheckbox.text:SetText("Debug Mode")
    debugCheckbox:SetScript("OnClick", function(self)
        SetDebugMode(self:GetChecked())
    end)

    -- Preview checkbox 
    local previewCheckbox = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    previewCheckbox:SetPoint("TOPLEFT", debugCheckbox, "BOTTOMLEFT", 0, -8)
    previewCheckbox:SetChecked(false)
    previewCheckbox.text:SetText("Preview")
    previewCheckbox:SetScript("OnClick", function(self)
        if self:GetChecked() then
            previewActive = true
            StartPreviewLoop(f)
        else
            previewActive = false
            StopPreviewLoop(f)
        end
    end)

    -- Uncheck and stop preview when the settings frame is closed
    f:HookScript("OnHide", function()
        if previewCheckbox:GetChecked() then
            previewCheckbox:SetChecked(false)
            previewActive = false
            StopPreviewLoop(f)
        end
    end)
    -- Close button
    local closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    closeButton:SetScript("OnClick", function() f:Hide() end)

    return f
end

local function ToggleSettingsFrame()
    if not settingsFrame then
        settingsFrame = BuildSettingsFrame()
    end
    if settingsFrame:IsShown() then
        settingsFrame:Hide()
    else
        settingsFrame:Show()
    end
end

-- ============================================================
-- Minimap Button
-- ============================================================

local function SetupMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1"):NewDataObject(ADDON_NAME, {
        type  = "launcher",
        label = "Stormkeeper Tracker",
        icon  = "Interface\\Icons\\spell_nature_lightningshield",

        OnClick = function(_, button)
            if button == "LeftButton" then
                ToggleSettingsFrame()
            end
        end,

        OnTooltipShow = function(tt)
            tt:AddLine("|cffffd700Stormkeeper Tracker|r")
            tt:AddLine("|cffffff00Left-click|r to toggle settings.")
            tt:AddLine("|cffffff00/skt|r for slash commands.")
        end,
    })

    local LibDBIcon = LibStub("LibDBIcon-1.0")
    LibDBIcon:Register(ADDON_NAME, LDB, StormkeeperTrackerDB.minimapIcon)
end

-- ============================================================
-- Slash Commands
-- ============================================================

local function OnSlashCommand(msg)
    local cmd, val1, val2, val3 = strsplit(" ", msg)
    cmd = cmd and cmd:lower() or ""

    if cmd == "size" and val1 and val2 then
        SetIconSize(val1, val2)

    elseif cmd == "size" and val1 then
        SetIconSize(val1, val1)

    elseif cmd == "fontsize" and val1 then
        SetFontSize(val1)

    elseif cmd == "fontcolor" then
        OpenFontColorPicker()

    elseif cmd == "debug" then
        SetDebugMode(not StormkeeperTrackerDB.debugMode)

    elseif cmd == "settings" or cmd == "config" then
        ToggleSettingsFrame()

    elseif cmd == "reset" then
        for k, v in pairs(defaults) do
            StormkeeperTrackerDB[k] = v
        end
        ApplyConfig()
        SKPrint("Settings reset to defaults.", LOG_LEVEL.ERROR)

    else
        SKPrint("Commands:", LOG_LEVEL.INFO)
        SKPrint("/skt size <number> <number> (20-100)", LOG_LEVEL.INFO)
        SKPrint("/skt size <number>          (20-100)", LOG_LEVEL.INFO)
        SKPrint("/skt fontsize <number>      (8-56)", LOG_LEVEL.INFO)
        SKPrint("/skt fontcolor              (opens color picker)", LOG_LEVEL.INFO)
        SKPrint("/skt debug                  (toggle debug messages)", LOG_LEVEL.INFO)        
        SKPrint("/skt settings               (Open settings panel)", LOG_LEVEL.INFO)
        SKPrint("/skt reset                  (Resets display and position)", LOG_LEVEL.INFO)
    end
end

SLASH_STORMKEEPERTRACKER1 = "/skt"
SlashCmdList["STORMKEEPERTRACKER"] = OnSlashCommand

-- ============================================================
-- Helpers
-- ============================================================

local function GetTierPiecesEquipped()
    local count = 0
    for _, itemId in ipairs(TIER_SET_ITEM_IDS) do
        if C_Item.IsEquippedItem(itemId) then
            count = count + 1
        end
    end
    return count
end

local function GetInitialCharges()
    if GetTierPiecesEquipped() >= TIER_SET_4PC_THRESHOLD then
        return SK_BASE_CHARGES + 1
    end
    return SK_BASE_CHARGES
end

local function HasArcDischarge()
    return C_SpellBook.IsSpellKnown(ARC_DISCHARGE_SPELL_ID)
end

local function SyncFromAura()
    local i = 1
    while true do
        local aura = C_UnitAuras.GetBuffDataByIndex("player", i)
        if not aura then break end
        if aura.spellId == STORMKEEPER_SPELL_ID then
            return aura.applications, aura.expirationTime
        end
        i = i + 1
    end
    return nil, nil
end

function CheckExpiration()
    if skExpiration and GetTime() >= skExpiration then
        skCharges = nil
        skExpiration = nil
        UpdateUI()
        SKPrint("Stormkeeper expired.", LOG_LEVEL.DEBUG)
    end
end

local function ResetExpiration()
    skExpiration = GetTime() + SK_DURATION
end

local function AddCharge(amount, reason)
    CheckExpiration()
    skCharges = skCharges and math.min(skCharges + amount, SK_MAX_CHARGES) or amount
    ResetExpiration()
    UpdateUI()
    SKPrint(string.format("%s — %d charge(s)", reason, skCharges), LOG_LEVEL.DEBUG)
end

local function ConsumeCharge(reason)
    CheckExpiration()
    if not skCharges or skCharges <= 0 then return end
    skCharges = skCharges - 1
    if skCharges == 0 then
        skCharges = nil
        skExpiration = nil
        SKPrint(string.format("%s — Stormkeeper faded.", reason), LOG_LEVEL.DEBUG)
    else
        SKPrint(string.format("%s — %d charge(s) remaining", reason, skCharges), LOG_LEVEL.DEBUG)
    end
    UpdateUI()
end

local function DisableAddon()
    -- Stop all event callbacks
    frame:UnregisterAllEvents()

    -- Clear the OnUpdate script to remove it from the update queue
    frame:SetScript("OnUpdate", nil)

    -- Clear remaining scripts
    frame:SetScript("OnEvent", nil)
    frame:SetScript("OnDragStart", nil)
    frame:SetScript("OnDragStop", nil)

    -- Disable mouse interaction and hide the frame
    frame:EnableMouse(false)
    frame:Hide()

    SLASH_STORMKEEPERTRACKER1 = nil    

    SKPrint("Not a Shaman or Stormkeeper is not known — addon disabled.", LOG_LEVEL.ERROR)
end

-- ============================================================
-- Event Handlers
-- ============================================================

local function OnSpellCast(unit, _, spellId)
    if unit ~= "player" then return end

    if spellId == STORMKEEPER_SPELL_ID then
        previewActive = false
        local charges = GetInitialCharges()
        if not InCombatLockdown() then
            local auraCharges, auraExpiration = SyncFromAura()
            if auraCharges then
                charges      = auraCharges
                skExpiration = auraExpiration
                skCharges    = skCharges and math.min(skCharges + charges, SK_MAX_CHARGES) or charges
                UpdateUI()
                SKPrint(string.format("Stormkeeper %s — %d charge(s). Out of combat; taken from aura info.",
                    skCharges == charges and "gained" or "refreshed", skCharges))
                return
            end
        end
        AddCharge(charges, "Stormkeeper cast")

    elseif spellId == TEMPEST_SPELL_ID then
        if HasArcDischarge() then
            AddCharge(1, "Tempest cast (Arc Discharge)")
        elseif skCharges then
            SKPrint(string.format("Tempest cast — %d charge(s) unchanged", skCharges), LOG_LEVEL.DEBUG)
        end

    elseif spellId == LIGHTNING_BOLT_SPELL_ID then
        ConsumeCharge("Lightning Bolt consumed a charge")

    elseif spellId == CHAIN_LIGHTNING_SPELL_ID then
        ConsumeCharge("Chain Lightning consumed a charge")
    end
end

local function OnLeaveCombat()
    local charges, expiration = SyncFromAura()
    skCharges = charges
    skExpiration = expiration
    UpdateUI()
    if skCharges then
        SKPrint(string.format("Resynced — %d charge(s) remaining", skCharges), LOG_LEVEL.DEBUG)
    else
        SKPrint("Resynced — Stormkeeper not active.", LOG_LEVEL.DEBUG)
    end
end

local function OnPlayerEnteringWorld(isInitialLogin, isReloadingUi)
    local _, classFile, _ = UnitClass("player")

    if classFile ~= "SHAMAN" or not C_SpellBook.IsSpellKnown(STORMKEEPER_SPELL_ID) then
        DisableAddon()
        return
    end

    InitConfig()
    
    SetupMinimapButton()

    if StormkeeperTrackerDB.point then
        frame:ClearAllPoints()
        frame:SetPoint(
            StormkeeperTrackerDB.point,
            UIParent,
            StormkeeperTrackerDB.relativePoint,
            StormkeeperTrackerDB.x,
            StormkeeperTrackerDB.y
        )
    end

    ApplyConfig()

    local charges, expiration = SyncFromAura()
    skCharges    = charges
    skExpiration = expiration
    UpdateUI()

    SKPrint(string.format(
        "Loaded. Tier pieces: %d | Arc Discharge: %s",
        GetTierPiecesEquipped(), tostring(HasArcDischarge())), 
        LOG_LEVEL.DEBUG)
end

-- ============================================================
-- Event Registration
-- ============================================================

frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnSpellCast(...)
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnLeaveCombat()
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnPlayerEnteringWorld()
    end
end)

