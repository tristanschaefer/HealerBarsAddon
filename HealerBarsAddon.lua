local HealerBarsAddon = CreateFrame("Frame")
local healerFrames = {} -- store healer frames here based on unit name "player", "party1", etc
local barPositions = {} -- store bar positions here and color
local healerTable = {} -- store ordering of frame in descending order based on unit name
local healerBarHide = false
SLASH_HEALERBARS1 = "/healerbars"  -- This allows you to use /healerbars in-game
SLASH_HEALERBARS2 = "/hb"           -- Optional: alias for the command
HealerBarsAddonDB = HealerBarsAddonDB or {}


-- Event handlers
HealerBarsAddon:RegisterEvent("GROUP_ROSTER_UPDATE")
HealerBarsAddon:RegisterEvent("UNIT_POWER_UPDATE")
HealerBarsAddon:RegisterEvent("PLAYER_ENTERING_WORLD")
HealerBarsAddon:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

local function WipeTables()
    for unit,frame in pairs(healerFrames) do
        healerFrames[unit]:Hide()
    end
    wipe(healerFrames)
    wipe(healerTable)
end

-- Function to save the bar positions to the saved variable
local function SaveBarPositions()
    -- Clear the previous saved positions
    HealerBarsAddonDB.barPositions = {}

    for unit, frame in pairs(healerFrames) do
        local x, y = frame:GetCenter()
        HealerBarsAddonDB.barPositions = { x = x, y = y }
    end
end

-- Function to update mana for a specific healer
local function UpdateHealerMana(healerUnit)

    local frame = healerFrames[healerUnit]

    if frame then
        local mana = UnitPower(healerUnit, 0)
        local maxMana = UnitPowerMax(healerUnit, 0)
        local manaPercent = math.floor((mana / maxMana) * 100)

        -- Update mana value
        frame:SetValue(mana)
        local healerName = UnitName(healerUnit)
        if #healerName > 14 then
            healerName = string.sub(healerName,1,14)
        end
        -- Update text with current mana percentage
        if frame.text then
            frame.text:SetText(string.format("%s - %d%%", healerName, manaPercent))
        end

        -- Set bar color based on class color
        local _, class = UnitClass(healerUnit)
        if class then
            local classColor = RAID_CLASS_COLORS[class]
            if classColor then
                frame:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
            else
                -- Default color if classColor is not found
                frame:SetStatusBarColor(0.5, 0.5, 0.5) -- Gray
            end
        end
    end

end

-- Function to create a new progress bar for a healer
local function CreateHealerManaBar(healerUnit, healerIndex)
    -- Avoid overflow if raid has too many healers
    if healerIndex > 10 then
        return
    end
    local frame = CreateFrame("StatusBar", nil, UIParent)
    frame:SetSize(185, 35)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(2)
    -- Create background texture
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(frame)
    background:SetColorTexture(0, 0, 0)  -- Black background

    -- Set clean bar style
    frame:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    frame:GetStatusBarTexture():SetHorizTile(false)
    frame:SetMinMaxValues(0, UnitPowerMax(healerUnit, 0))
    frame:SetValue(UnitPower(healerUnit, 0))

    if healerIndex == 0 then
        -- Enable frame dragging
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        if HealerBarsAddonDB.barPositions then
            local position = HealerBarsAddonDB.barPositions
            local x, y = position.x, position.y
            frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        else
            frame:SetPoint("TOPLEFT", 20, -20)  -- Default position if not saved
        end
        frame:SetScript("OnDragStart", function(self)
            self:StartMoving()
        end)

        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            -- Save position and color after moving
            local x, y = self:GetCenter()
            barPositions[healerUnit] = {x = x, y = y, color = {frame:GetStatusBarColor()}}
            SaveBarPositions()          -- Call the function to save positions
        end)
    else
        local previousUnit = healerTable[healerIndex]
        if healerFrames[previousUnit] then
            frame:SetPoint("TOPLEFT", healerFrames[previousUnit], "BOTTOMLEFT", 0, -5)  -- Adjust the vertical spacing as needed
        else
            frame:SetPoint("TOPLEFT", 20, -20)  -- Default position if not saved
        end
    end

    -- Add healer's name and class color
    local healerName = UnitName(healerUnit)
    if healerName then
        local _, class = UnitClass(healerUnit)
        local classColor = RAID_CLASS_COLORS[class]

        local text = frame:CreateFontString(nil, "OVERLAY")
        text:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
        text:SetPoint("CENTER", frame)
        text:SetTextColor(1, 1, 1)

        -- Store the text object in the frame
        frame.text = text

        -- Set bar color based on class color
        if classColor then
            frame:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
        end

        -- Create an icon for the healer's class
        local icon = frame:CreateTexture(nil, "OVERLAY")
        icon:SetSize(40, 40)  -- Set the size of the icon
        icon:SetPoint("RIGHT", frame, "LEFT", 0, 0)  -- Position it to the left of the bar

        -- Set the icon texture based on the class
        if classColor then
            icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")  -- Use a default texture, replace with your icon path
            icon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))  -- Set the texture coordinates for the class icon
        end

        -- Ensure frame is shown
        frame:Show()

        healerFrames[healerUnit] = frame

        -- Update text with initial mana percentage
        UpdateHealerMana(healerUnit)
    end

end

-- Function to remove frames that aren't relevant
local function RemoveNonHealer(healerUnit)
    if healerFrames[healerUnit] then
        healerFrames[healerUnit]:Hide()
        healerFrames[healerUnit] = nil  -- This will remove the key-value pair from the table
    end
end

-- Function to verify input healer
local function CheckIfHealer(unit)
    if unit == "player" then
        local specIndex = GetSpecialization() -- Get the current specialization index
        if specIndex then
            local role = GetSpecializationRole(specIndex) -- Get the role of the current specialization
            if role == "HEALER" and not healerFrames[unit] then
                return true
            else
                RemoveNonHealer(unit)
            end
        end
    else
        if UnitGroupRolesAssigned(unit) == "HEALER" and not healerFrames[unit] then
            return true
        else
            RemoveNonHealer(unit)
        end
    end
    return false
end

local function PopulateHealerManaBars()
    for index = 1, #healerTable do
        -- Create only up to 10
        if index <= 10 then
            local healerUnit = healerTable[index]
            CreateHealerManaBar(healerUnit, index - 1)
        end
    end
end

-- Function to scan all group members and queue them for inspection
local function ScanGroupForHealers()
    local groupType = IsInRaid() and "raid" or "party"
    local numGroupMembers = GetNumGroupMembers()-1

    wipe(healerTable)

    if CheckIfHealer("player") then
        table.insert(healerTable,"player")
    end

    if numGroupMembers > 0 then
        -- Queue up all group members for inspection
        for i = 1, numGroupMembers do
            local unit = groupType .. i  -- "raid1", "raid2", etc.
            if CheckIfHealer(unit) then
                table.insert(healerTable,unit)
            end
        end
    end
end

local function InitializeHealerManaBars()
    WipeTables() -- Call the wipe function to reset frames
    ScanGroupForHealers() -- scans for healers and adds to healerTable
    PopulateHealerManaBars() -- creates the mana bars for healers
end

-- Localize the command handler function
local function HealerBarsCommandHandler(msg)
    if msg == "reset" then
        HealerBarsAddonDB = {}
        InitializeHealerManaBars()
    elseif msg == "show" then
        healerBarHide = false
        InitializeHealerManaBars()
    elseif msg == "hide" then
        healerBarHide = true
        for unit, frame in pairs(healerFrames) do
            frame:Hide() -- Hide all healer frames
        end
    else
        print("Usage: /healerbars [reset | show | hide ]")
        print("Usage: /hb [reset | show | hide]")
    end
end

-- Register the command handler
SlashCmdList["HEALERBARS"] = HealerBarsCommandHandler

-- Event handler for addon events
HealerBarsAddon:SetScript("OnEvent", function(self, event, healerUnit, power)
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        if healerBarHide == false then
            InitializeHealerManaBars()
        end
    elseif event == "UNIT_POWER_UPDATE" and power == "MANA" then
        if healerFrames[healerUnit] then
            UpdateHealerMana(healerUnit)
        end
    end
end)