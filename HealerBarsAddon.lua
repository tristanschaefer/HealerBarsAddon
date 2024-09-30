local HealerBarsAddon = CreateFrame("Frame")
local inspectFrame = CreateFrame("Frame")
local healerFrames = {}
local barPositions = {}
local inspectedSpecs = {}
local inspectQueue = {}
local unitGUID = {}
local inspecting = false
local lock = false -- Mutex to lock access to inspecting state

-- Event handlers
HealerBarsAddon:RegisterEvent("GROUP_ROSTER_UPDATE")
HealerBarsAddon:RegisterEvent("UNIT_POWER_UPDATE")
HealerBarsAddon:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Function to safely set inspecting with lock
local function SafeSetInspecting(state)
    if not lock then
        lock = true
        inspecting = state
        lock = false
    end
end

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
    -- Safely set inspecting to true using the lock
    SafeSetInspecting(false)
    inspectQueue = {}  -- Clear the queue
    local index = 1
    for unit, isHealer in pairs(inspectedSpecs) do
        if not healerFrames[unit] and isHealer then
            CreateHealerManaBar(unit, index)
            index = index + 1
        end
    end
end

-- Function to validate a unit's specialization ID
local function ValidateSpecID(unit)
    local specID = GetInspectSpecialization(unit)
    if specID and specID > 0 then  -- Check if specID is valid
        -- Add additional specID validation logic here if necessary
        if healerClasses[specID] then
            inspectedSpecs[unit] = true
        else
            inspectedSpecs[unit] = false
            RemoveNonHealers(unit)
        end
    end
end

-- Function to start processing the inspect queue
local function ProcessInspectQueue()
    if inspecting then return end

    -- Stop processing if all units have been inspected
    if #inspectQueue == 0 then
        OnAllInspectsCompleted()
        return
    end

    SafeSetInspecting(true)
    inspectFrame:RegisterEvent("INSPECT_READY")  -- Register event only when processing queue

    local unit = table.remove(inspectQueue, 1)

    if unit and CanInspect(unit) then
        NotifyInspect(unit)  -- Start inspecting the unit
    else
        SafeSetInspecting(false)
        inspectFrame:UnregisterEvent("INSPECT_READY")  -- Unregister if no valid unit to inspect
    end
end

-- Function to scan all group members and queue them for inspection
local function ScanGroupForHealers()
    local groupType = IsInRaid() and "raid" or "party"
    local numGroupMembers = GetNumGroupMembers()-1

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
            unitGUID[UnitGUID(unit)] = unit
            table.insert(inspectQueue, unit)
        end
        ProcessInspectQueue()
    end
end

-- Event handler for when inspection is complete
local function OnInspectComplete(self, event, guid)
    local unit = unitGUID[guid]
    if unit then
        ValidateSpecID(unit)
        SafeSetInspecting(false)  -- Safely reset inspecting
        ProcessInspectQueue()  -- Process the next unit
    end
end

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

inspectFrame:SetScript("OnEvent", OnInspectComplete)