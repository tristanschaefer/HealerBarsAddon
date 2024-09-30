local HealerBarsAddon = CreateFrame("Frame")
local f = CreateFrame("Frame")
local healerFrames = {}
local barPositions = {}
local inspectedSpecs = {}
local inspectQueue = {}
local inspecting = false
local inspectedUnits = 0

-- Event handler
HealerBarsAddon:RegisterEvent("GROUP_ROSTER_UPDATE")
HealerBarsAddon:RegisterEvent("UNIT_POWER_UPDATE")
HealerBarsAddon:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Define healer classes
local healerClasses = {
    [105] = true, -- rdruid
    [65] = true, -- hpal
    [256] = true, -- disc
    [257] = true, -- hpriest
    [270] = true, -- mw monk
    [264] = true, -- rsham
    [1468] = true -- pres evok
}

-- Function to update mana for a specific healer
local function UpdateHealerMana(healerUnit)

    local frame = healerFrames[healerUnit]

    if frame then
        local mana = UnitPower(healerUnit, 0)
        local maxMana = UnitPowerMax(healerUnit, 0)
        local manaPercent = math.floor((mana / maxMana) * 100)

        -- Update mana value
        frame:SetValue(mana)

        -- Update text with current mana percentage
        if frame.text then
            frame.text:SetText(string.format("%s - %d%%", UnitName(healerUnit), manaPercent))
        end

        -- Set bar color based on class color
        local _, class = UnitClass(healerUnit)
        local classColor = RAID_CLASS_COLORS[class]
        if classColor then
            frame:SetStatusBarColor(classColor.r, classColor.g, classColor.b)
        else
            -- Default color if classColor is not found
            frame:SetStatusBarColor(0.5, 0.5, 0.5) -- Gray
        end
    end

end

-- Function to create a new progress bar for a healer
local function CreateHealerManaBar(healerUnit, healerIndex)
    local frame = CreateFrame("StatusBar", nil, UIParent)
    frame:SetSize(200, 40)
    frame:SetPoint("TOPLEFT", 20, -20 * healerIndex)

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

        -- Enable frame dragging
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(self)
            self:StartMoving()
        end)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            -- Save position and color after moving
            local x, y = self:GetCenter()
            barPositions[healerUnit] = {x = x, y = y, color = {frame:GetStatusBarColor()}}
        end)

        -- Restore position and color if available
        if barPositions[healerUnit] then
            frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", barPositions[healerUnit].x, barPositions[healerUnit].y)
            frame:SetStatusBarColor(unpack(barPositions[healerUnit].color))
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
local function RemoveNonHealers(healerUnit)
    if healerFrames[healerUnit] then
        healerFrames[healerUnit]:Hide()
        healerFrames[healerUnit] = nil  -- This will remove the key-value pair from the table
    end
end

-- Function to handle all inspections being completed
local function OnAllInspectsCompleted()
    print("all done")
    local index = 1
    for unit, _ in pairs(inspectedSpecs) do
        if not healerFrames[unit] then
            CreateHealerManaBar(unit, index)
            index = index + 1
        end
    end
end

-- Function to validate a unit's specialization ID
local function ValidateSpecID(unit)
    local specID = GetInspectSpecialization(unit)
    if specID and specID > 0 then  -- Check if specID is valid
        local _, specName = GetSpecializationInfoByID(specID)
        -- Add additional specID validation logic here if necessary
        if healerClasses[specID] then
            inspectedSpecs[unit] = true
        else
            inspectedSpecs[unit] = true
            RemoveNonHealers(unit)
        end
    end
end

-- Function to get specialization by inspecting a party member
local function InspectUnitRequest(unit)
    if not UnitExists(unit) then
        return false
    end

    local guid = UnitGUID(unit)

    -- Initiate an inspection
    if CanInspect(unit) then
        NotifyInspect(unit)
    end
end

-- Function to start inspecting the next unit in the queue
local function ProcessInspectQueue()

    if inspecting or #inspectQueue == 0 then return end

    -- Stop processing if all units have been inspected
    if inspectedUnits >= GetNumGroupMembers() then
        return
    end

    inspecting = true
    local unit = table.remove(inspectQueue, 1)
    InspectUnitRequest(unit)
end

-- Function to scan all group members and queue them for inspection
local function ScanGroupForHealers()
    local groupType = IsInRaid() and "raid" or "party"
    local numGroupMembers = GetNumGroupMembers()-1

    -- Reset the inspected units counter
    inspectedUnits = 1

    -- Get the player's current specialization index
    local specIndex = GetSpecialization()

    if specIndex then
        -- Get detailed information for the player's current specialization
        local specID, specName, _, _, _, role = GetSpecializationInfo(specIndex)
        if specID and healerClasses[specID] and not inspectedSpecs["player"] then
            inspectedSpecs["player"] = true
            CreateHealerManaBar("player", 0)
        end
        if not healerClasses[specID] then
            inspectedSpecs["player"] = false
            RemoveNonHealers("player")
        end
    end

    if numGroupMembers > 0 then
        -- Queue up all group members for inspection
        for i = 1, numGroupMembers do
            local unit = groupType .. i  -- "raid1", "raid2", etc.
            table.insert(inspectQueue, unit)
        end
    end
    -- Start processing the inspect queue
    ProcessInspectQueue()
end

-- Event handler for INSPECT_READY
f:RegisterEvent("INSPECT_READY")
f:SetScript("OnEvent", function(self, event, guid)
    if event == "INSPECT_READY" then
        -- Find the corresponding unit for the given GUID
        local unit
        for i = 1, GetNumGroupMembers()-1 do
            local groupType = IsInRaid() and "raid" or "party"
            local testUnit = groupType .. i
            if UnitGUID(testUnit) == guid then
                unit = testUnit
                break
            end
        end
        print(unit)

        if unit then
            -- Validate the unit's specialization ID
            ValidateSpecID(unit)
        end

        -- Increment the inspected units counter
        inspectedUnits = inspectedUnits + 1

        -- Check if all units have been inspected
        if inspectedUnits >= GetNumGroupMembers() then
            OnAllInspectsCompleted()
        end

        -- Move to the next unit in the queue
        inspecting = false
        ProcessInspectQueue()
    end
end)

HealerBarsAddon:SetScript("OnEvent", function(self, event, healerUnit, power)
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or "PLAYER_SPECIALIZATION_CHANGED" then
        ScanGroupForHealers()
    end

    if event == "UNIT_POWER_UPDATE" and power == "MANA" then
        if healerFrames[healerUnit] then
            UpdateHealerMana(healerUnit)
        end
    end
end)

