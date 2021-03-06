BuffCheck3 = {}
BuffCheck3.debugmode = true;

BuffCheck3_DefaultFrameSize = 100

-- saved variables
BuffCheck3_Textures = {}
BuffCheck3_SavedConsumes = {}
BuffCheck3_Config = {}

-- [link] = count
BuffCheck3.BagContents = {}

-- OnUpdate variables
BuffCheck3_TimeSinceLastUpdate = 0
BuffCheck3.OnUpdateCount = 0
BuffCheck3.WasInCombat = false
BuffCheck3.WasSpellTargeting = false

BuffCheck3_PrintFormat = "|c00f7f26c%s|r"

-- ConsumeFrame
BuffCheck3.AllConsumeButtons = {}
BuffCheck3.ActiveConsumes = {}
BuffCheck3.InactiveConsumes = {}

-- ConsumeList
BuffCheck3.AvailableButtons = {}
BuffCheck3.AddedButtons = {}

BuffCheck3.LockedBackdrop = {
    bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
    tileSize = 32,
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true,
    tileEdge = false,
    edgeSize = 1,
    insets = {
        top = 12,
        right = 12,
        left = 11,
        bottom = 11
    }
}
BuffCheck3.UnlockedBackdrop = {
    bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
    tileSize = 32,
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true,
    tileEdge = true,
    edgeSize = 32,
    insets = {
        top = 12,
        right = 12,
        left = 11,
        bottom = 11
    }
}

-- work around for GetItemSpell() returning only "Food" for food buffs
BuffCheck3.FoodBuffList = {
    "Well Fed",
    "Increased Stamina",
    "Increased Intellect",
    "Increased Agility",
    "Brain Food",
    "Blessed Sunfruit",
    "Blessed Sunfruit Juice",
    "Mana Regeneration"
}

SLASH_BUFFCHECK1 = "/bc"
SLASH_BUFFCHECK2 = "/buffcheck"
function SlashCmdList.BUFFCHECK(args)
    words = {}
    for word in args:gmatch("%w+") do table.insert(words, word) end

    for i = 1, table.getn(words) do
        words[i] = strlower(words[i])
    end

    if BuffCheck3:HasValue(words, "update") then
        BuffCheck3:ShowConsumeList()
    elseif BuffCheck3:HasValue(words, "show") then
        BuffCheck3:ShowFrame(true)
    elseif BuffCheck3:HasValue(words, "hide") then
        BuffCheck3:ShowFrame(false)
    elseif BuffCheck3:HasValue(words, "lock") then
        BuffCheck3:LockFrame(true)
    elseif BuffCheck3:HasValue(words, "unlock") then
        BuffCheck3:LockFrame(false)
    elseif BuffCheck3:HasValue(words, "vertical") then
        BuffCheck3:VerticalFrame(true)
    elseif BuffCheck3:HasValue(words, "horizontal") then
        BuffCheck3:VerticalFrame(false)
    elseif BuffCheck3:HasValue(words, "resize") then
        local size = BuffCheck3:GetSizeFromArgs(words)
        if size then
            BuffCheck3:ResizeFrame(size)
        else
            BuffCheck3:SendMessage("Missing Size")
        end
    elseif BuffCheck3:HasValue(words, "missing") then
        BuffCheck3:PrintMissing()
    else
        BuffCheck3:SendMessage("Options: update, show, hide, lock, unlock, vertical, horizontal, resize, missing")
    end
end

function BuffCheck3:GetSizeFromArgs(args)
    if(args[2] and tonumber(args[2]) ~= nil) then
        return tonumber(args[2])
    end
    return nil
end

function BuffCheck3:OnLoad(self)
    self:RegisterEvent("ADDON_LOADED")
    -- self:RegisterEvent("PLAYER_AURAS_CHANGED") -- deprecated event
    self:RegisterEvent("UNIT_INVENTORY_CHANGED")
    self:RegisterEvent("BAG_UPDATE")
end

function BuffCheck3:CleanupSavedConsumes()
    -- old versions used itemlinks for SavedConsumes
    -- no longer compatible so needs to be removed
    local toremove = {}
    for i, consume in ipairs(BuffCheck3_SavedConsumes) do
        if string.find(consume, "%[") then
            table.insert(toremove, i)
        end
    end
    local i = table.getn(toremove)
    while i > 0 do
        table.remove(BuffCheck3_SavedConsumes, toremove[i])
        i = i - 1
    end
end

function BuffCheck3:Init()
    BuffCheck3:CleanupSavedConsumes()

    BuffCheck3:ResizeFrame(BuffCheck3_Config["scale"])

    BuffCheck3:LockFrame(BuffCheck3_Config["locked"], false)

    BuffCheck3:ShowFrame(BuffCheck3_Config["showing"])
    
    BuffCheck3:VerticalFrame(BuffCheck3_Config["vertical"])

    BuffCheck3:UpdateBagContents()

    -- set the OnUpdate event
    BuffCheck3UpdateFrame:SetScript("OnUpdate", BuffCheck3_OnUpdate)


    BuffCheck3:SendMessage("Init Successful")
end

function BuffCheck3:OnEvent(event, arg1)
    if event == "ADDON_LOADED" and arg1 == "BuffCheck3" then
        BuffCheck3:Init()
    elseif event == "BAG_UPDATE" then
        BuffCheck3:UpdateBagContents()
        BuffCheck3:UpdateItemCounts()
    end
end

--=================================================================
-- OnUpdate handler - crucial to this addon

function BuffCheck3_OnUpdate(self, elapsed)
    BuffCheck3_TimeSinceLastUpdate = BuffCheck3_TimeSinceLastUpdate + elapsed
    if BuffCheck3_TimeSinceLastUpdate > 0.5 then
        BuffCheck3_TimeSinceLastUpdate = 0
        BuffCheck3.OnUpdateCount = BuffCheck3.OnUpdateCount + 1

        local incombat = UnitAffectingCombat("player")

        if incombat then
            -- make all the buttons opaque
            BuffCheck3.WasInCombat = true
            for _, f in pairs(BuffCheck3.AllConsumeButtons) do
                f:SetAlpha(0.4)
            end
        else
            -- add/remove buttons as buffs update
            BuffCheck3:UpdateFrame()
        end

        -- fix all the opaque buttons
        if not incombat and BuffCheck3.WasInCombat then
            BuffCheck3.WasInCombat = false
            for _, f in pairs(BuffCheck3.AllConsumeButtons) do
                f:SetAlpha(1)
            end
        end

        -- show in raids
        BuffCheck3:CheckGroupUpdate()

        -- WeaponFrame stuff - hide em if no longer trying to apply enchant
        if BuffCheck3.WasSpellTargeting and not SpellIsTargeting() then
            BuffCheck3.WasSpellTargeting = false
            BuffCheck3WeaponFrame:Hide()
        end
        if not BuffCheck3.WasSpellTargeting and SpellIsTargeting() then
            BuffCheck3.WasSpellTargeting = true
        end

        -- check for item gcd
        for _, f in pairs(BuffCheck3.InactiveConsumes) do
            -- NOTE: GetItemCooldown only takes itemID
            local _, link = GetItemInfo(f.consume)
            if link then
                local start, duration = GetItemCooldown(BuffCheck3:LinkToID(link))
                f.cooldown(start, duration)
            end
        end

        -- check for soon to expire
        BuffCheck3:CheckExpirationTimes()
    end
end

--=================================================================
-- Consume List Functions

function BuffCheck3_MoveToAvailable(self)
    local index = BuffCheck3:GetIndexInTable(BuffCheck3_SavedConsumes, self.consume)
    if index == -1 then
        BuffCheck3:SendMessage("Error - could not find " .. tostring(consume) .. " in BuffCheck3_SavedConsumes")
        return
    end
    table.remove(BuffCheck3_SavedConsumes, index)
    table.insert(BuffCheck3.AvailableButtons, self)
    local index = BuffCheck3:GetIndexInTable(BuffCheck3.AddedButtons, self)
    if index ~= -1 then
        table.remove(BuffCheck3.AddedButtons, index)
    end
    BuffCheck3:HideConsumeFrameButton(self.consume)
    BuffCheck3:ShowConsumeButtons()
    -- update the frame
    BuffCheck3:UpdateFrame()
end

function BuffCheck3_MoveToAdded(self)
    table.insert(BuffCheck3_SavedConsumes, self.consume)
    table.insert(BuffCheck3.AddedButtons, self)
    local index = BuffCheck3:GetIndexInTable(BuffCheck3.AvailableButtons, self)
    if index ~= -1 then
        table.remove(BuffCheck3.AvailableButtons, index)
    end
    BuffCheck3:ShowConsumeButtons()
    -- update the frame
    BuffCheck3:UpdateFrame()
end

function BuffCheck3:ShowConsumeList()
    BuffCheck3:UpdateBagContents()
    BuffCheck3:UpdateConsumeList()
    BuffCheck3ConsumeList:Show()
end

function BuffCheck3:HideConsumeList()
    BuffCheck3ConsumeList:Hide()
end

function BuffCheck3:ConsumeListButtonExists(consume)
    for _, f in pairs(BuffCheck3.AvailableButtons) do
        if f.consume == consume then
            return true
        end
    end
    for _, f in pairs(BuffCheck3.AddedButtons) do
        if f.consume == consume then
            return true
        end
    end
    return false
end

function BuffCheck3:CreateConsumeListButton(consume)
    local parent = getglobal("BuffCheck3ConsumeList")
    local fname = "BuffCheck3ConsumeButton" .. (table.getn(BuffCheck3.AvailableButtons)
        + table.getn(BuffCheck3.AddedButtons))

    -- more info on the item
    local link, quality, texture = BuffCheck3:FindTextureInfo(consume)

    -- create the button
    f = CreateFrame("Button", fname, parent, "BuffCheck3ConsumeRowTemplate")
    f.consume = consume

    -- set text
    local ftext = getglobal(fname.."Name")
    ftext:SetText(consume)
    local r,g,b = GetItemQualityColor(quality)
    ftext:SetTextColor(r,g,b)

    -- set icon
    local icon = getglobal(fname.."Icon")
    icon:SetTexture(texture)
    icon:SetVertexColor(1,1,1)

    return f
end

-- main purpose is to create buttons and add em to the correct list
function BuffCheck3:UpdateConsumeList()
    -- create a button for each consume
    for consume, _ in pairs(BuffCheck3.BagContents) do
        if not BuffCheck3:ConsumeListButtonExists(consume) then
            
            f = BuffCheck3:CreateConsumeListButton(consume)
            -- add to appropriate list
            local isadded = BuffCheck3:HasValue(BuffCheck3_SavedConsumes, consume)
            if isadded then
                table.insert(BuffCheck3.AddedButtons, f)
            else
                table.insert(BuffCheck3.AvailableButtons, f)
            end
        end
    end
    -- show all the buttons
    BuffCheck3:ShowConsumeButtons()
end

function BuffCheck3:ShowConsumeButtons()
    local fheight = 24
    local prev = getglobal("BuffCheck3ConsumeList")
    for i, f in ipairs(BuffCheck3.AvailableButtons) do
        f:ClearAllPoints()
        if i == 1 then
            f:SetPoint("TOPLEFT", prev, 15, -fheight*2)
        else
            f:SetPoint("TOPLEFT", prev, 0, -fheight)
        end
        f:SetScript("OnClick", BuffCheck3_MoveToAdded)
        prev = f
    end
    
    prev = getglobal("BuffCheck3ConsumeList")
    for i, f in ipairs(BuffCheck3.AddedButtons) do
        f:ClearAllPoints()
        if i == 1 then
            f:SetPoint("TOP", prev, 106, -fheight*2)
        else
            f:SetPoint("TOPLEFT", prev, 0, -fheight)
        end
        f:SetScript("OnClick", BuffCheck3_MoveToAvailable)
        prev = f
    end

    local numAvail = table.getn(BuffCheck3.AvailableButtons)
    local numAdded = table.getn(BuffCheck3.AddedButtons)
    -- update height
    if numAvail > numAdded then
        BuffCheck3ConsumeList:SetHeight(60 + numAvail*fheight)
    else
        BuffCheck3ConsumeList:SetHeight(60 + numAdded*fheight)
    end

    -- if either lists are empty add a msg
    if numAvail == 0 then
        BuffCheck3:ShowNoAvailableMsg(true)
    else
        BuffCheck3:ShowNoAvailableMsg(false)
    end
    if numAdded == 0 then
        BuffCheck3:ShowNoAddedMsg(true)
    else
        BuffCheck3:ShowNoAddedMsg(false)
    end
end

function BuffCheck3:ShowNoAvailableMsg(shouldshow)
    if shouldshow then
        getglobal("BuffCheck3ConsumeListNoAvailableText"):Show()
    else
        getglobal("BuffCheck3ConsumeListNoAvailableText"):Hide()
    end
end

function BuffCheck3:ShowNoAddedMsg(shouldshow)
    if shouldshow then
        getglobal("BuffCheck3ConsumeListNoAddedText"):Show()
    else
        getglobal("BuffCheck3ConsumeListNoAddedText"):Hide()
    end
end

-- debug only
function BuffCheck3:PrintAllConsumes()
    BuffCheck3:tprint(BuffCheck3.BagContents)
end

--=================================================================
-- Command Functions

-- toggles visibility
function BuffCheck3:ShowFrame(shouldshow)
    BuffCheck3_Config["showing"] = shouldshow
    if not shouldshow then
        -- Hide first so Show is the default
        BuffCheck3Frame:Hide()
        if shouldprint ~= false then
            BuffCheck3:SendMessage("Interface hidden")
        end
    else
        BuffCheck3Frame:Show()
        if shouldprint ~= false then
            BuffCheck3:SendMessage("Interface showing")
        end
    end
end

-- toggles lock
function BuffCheck3:LockFrame(shouldlock, shouldprint)
    BuffCheck3_Config["locked"] = shouldlock
    if shouldlock then
        BuffCheck3Frame:SetBackdrop(BuffCheck3.LockedBackdrop)
        BuffCheck3Frame:EnableMouse(false)
        if shouldprint ~= false then
            BuffCheck3:SendMessage("Interface locked")
        end
    else
        -- default
        BuffCheck3Frame:SetBackdrop(BuffCheck3.UnlockedBackdrop)
        BuffCheck3Frame:EnableMouse(true)
        if shouldprint ~= false then
            BuffCheck3:SendMessage("Interface unlocked")
        end
    end
end

-- toggles horizontal/vertical
function BuffCheck3:VerticalFrame(vertical)
    BuffCheck3_Config["vertical"] = vertical
    -- rest is handled by UpdateFrame
end

function BuffCheck3:ResizeFrame(size)
    if size == nil then
        -- set defaults
        size = 100
        BuffCheck3_Config["scale"] = 100
    end
    local shouldResetPos = false
    if BuffCheck3_Config["scale"] ~= size then
        BuffCheck3_Config["scale"] = size
        shouldResetPos = true
    end
    BuffCheck3Frame:SetScale(BuffCheck3_Config["scale"] / 100)
    BuffCheck3WeaponFrame:SetScale(BuffCheck3_Config["scale"] / 100)
    if shouldResetPos then
        BuffCheck3Frame:ClearAllPoints()
        BuffCheck3Frame:SetPoint("CENTER", "UIParent") -- inelegant solution, but w/e
        BuffCheck3:LockFrame(false, false)
    end
end

function BuffCheck3:PrintMissing()
    for _, consume in pairs(BuffCheck3_SavedConsumes) do
        if BuffCheck3.BagContents[consume] == nil or BuffCheck3.BagContents[consume] == 0 then
            BuffCheck3:SendMessage("missing " .. consume)
        end
    end
end

--=================================================================
-- Main Addon Functions

-- will auto show/hide the BuffCheck3Frame based on group type
function BuffCheck3:CheckGroupUpdate()
    -- NOTE: BuffCheck3_Config["showing"] must be false to auto show/hide
    if not BuffCheck3Frame:IsShown() and UnitInRaid("player") and BuffCheck3_Config["showing"] == false then
        BuffCheck3Frame:Show()
    end
    if BuffCheck3Frame:IsShown() and not UnitInRaid("player") and BuffCheck3_Config["showing"] == false then
        BuffCheck3Frame:Hide()
    end
end

-- return link, quality, texture if in BuffCheck3_Config
function BuffCheck3:FindTextureInfo(consume)
    if BuffCheck3_Textures[consume] then
        return BuffCheck3_Textures[consume].link, BuffCheck3_Textures[consume].quality, BuffCheck3_Textures[consume].texture
    end
    return nil, nil, nil
end

function BuffCheck3:UpdateBagContents()
    -- NOTE: found that using itemlinks as keys in a table is very inconsistent for lookups
    -- using the raw item name instead
    BuffCheck3.BagContents = {}
    for i = 0, 4 do
        for j = 1, GetContainerNumSlots(i) do
            local texture, count, _, _, _, _, link = GetContainerItemInfo(i, j)

            if link then
                local name, _, quality = GetItemInfo(link)
                local _, _, _, _, _, itemType = GetItemInfo(link)
                local buffname = GetItemSpell(link)

                if name and buffname and (itemType == "Consumable" or itemType == "Quest" or string.match(name, "Sharpening") or string.match(name, "Weightstone") or string.match(name, "Aquadynamic")) then
                    -- add to BagContents
                    if BuffCheck3.BagContents[name] then
                        BuffCheck3.BagContents[name] = BuffCheck3.BagContents[name] + count
                    else
                        BuffCheck3.BagContents[name] = count
                    end

                    -- if consume's texture not in Config then add it
                    if texture and not BuffCheck3_Textures[name] then
                        BuffCheck3_Textures[name] = {link = link, texture = texture, quality = quality};
                        BuffCheck3:SendMessage("Saved info for " .. tostring(link))
                    end
                end
            end
        end
    end
    -- add 0 count for any other consume that exists
    for _, consume in pairs(BuffCheck3_SavedConsumes) do
        if not BuffCheck3.BagContents[consume] and BuffCheck3_Textures[consume] then
            BuffCheck3.BagContents[consume] = 0
        end
    end
    for _, f in pairs(BuffCheck3.AllConsumeButtons) do
        if not BuffCheck3.BagContents[f.consume] and BuffCheck3_Textures[consume] then
            BuffCheck3.BagContents[consume] = 0
        end
    end
end

--=================================================================
-- IsBuffPresent Functions

function BuffCheck3:IsFoodBuffPresent()
    for x = 1, 32 do
        local name, _, _, _, _, expires = UnitBuff("player", x)
        if BuffCheck3:HasValue(BuffCheck3.FoodBuffList, name) then
            return true, expires - GetTime()
        end
    end
    return false, 0
end

function BuffCheck3:IsWeaponBuff(consume)
    local buffname, spellid = GetItemSpell(consume)
    if buffname == nil then
        if consume == "mainhand" or consume == "offhand" then
            return true
        end
    end
    local words = {}
    for word in buffname:gmatch("%w+") do table.insert(words, word) end
    return words[1] == "Sharpen" or words[1] == "Enhance" or words[1] == "Deadly" or words[1] == "Crippling" 
            or words[1] == "Mind-numbing" or words[1] == "Wound" or words[1] == "Instant" or words[1] == "Shiny" 
            or words[1] == "Aquadynamic" or words[1] == "Nightcrawlers" or words[1] == "Flesh"
end

function BuffCheck3:IsWeaponBuffName(buffname)
    local words = {}
    for word in buffname:gmatch("%w+") do table.insert(words, word) end
    return words[1] == "Sharpen" or words[1] == "Enhance" or words[1] == "Deadly" or words[1] == "Crippling" 
            or words[1] == "Mind-numbing" or words[1] == "Wound" or words[1] == "Instant" or words[1] == "Shiny" 
            or words[1] == "Aquadynamic" or words[1] == "Nightcrawlers" or words[1] == "Flesh"
end

function BuffCheck3:IsWeaponBuffsPresent()
    local hasMainHandEnchant, _, _, _, hasOffHandEnchant = GetWeaponEnchantInfo()
    local mainHandLink = GetInventoryItemLink("player", GetInventorySlotInfo("MainHandSlot"))
    local offHandLink = GetInventoryItemLink("player", GetInventorySlotInfo("SecondaryHandSlot"))
    local faction = UnitFactionGroup("player")
    local class = UnitClass("player")
    if (faction == "Horde" and class ~= "Warrior" and class ~= "Rogue") or faction == "Alliance" then
        if BuffCheck3:ItemIsEnchantable(mainHandLink) and not hasMainHandEnchant then
            return false
        end
    end
    if BuffCheck3:ItemIsEnchantable(offHandLink) and not hasOffHandEnchant then
        return false
    end
    -- mainhand and offhand are enchanted in regards to faction and class
    return true
end

function BuffCheck3:IsBuffPresent(consume)
    local buffname, spellid = GetItemSpell(consume)

    -- occasionally happens with weird consumes
    if buffname == nil then
        return nil, nil, nil
    end
    
    -- checking food buffs
    if buffname == "Food" then
        return BuffCheck3:IsFoodBuffPresent()
    end

    -- checking weapon buff
    if BuffCheck3:IsWeaponBuffName(buffname) then
        return BuffCheck3:IsWeaponBuffsPresent()
    end

    -- checking consume buff
    for x = 1, 32 do
        local name, _, _, _, _, expires = UnitBuff("player", x)
        if name == buffname then
            return true, expires - GetTime()
        end
    end
    return false, 0
end

function BuffCheck3:ItemIsEnchantable(itemlink)
    if itemlink == nil then return false end
    local _, _, _, _, _, _, sType = GetItemInfo(itemlink)
    if sType == nil then return false end
    local c = string.sub(sType, 0, 1)
    return c == "O" or c == "D" or c == "T" or c == "F"
end

--=================================================================
-- Expiration Functions

function BuffCheck3:CheckExpirationTimes()
    for _, f in pairs(BuffCheck3.ActiveConsumes) do
        if not BuffCheck3:IsWeaponBuff(f.consume) then -- weapon buff IsBuffPresent doesnt return time
            local _, exp1 = BuffCheck3:IsBuffPresent(f.consume)
            BuffCheck3:SetDuration(f, exp1)
            if exp1 and exp1 < 120 then -- 2 mins
                UIFrameFlash(f, 0.5, 0.5, -1)
            elseif UIFrameIsFlashing(f) then
                UIFrameFlashStop(f)
            end
        end
    end
    -- weapon enchants are special
    -- mh could be enchanted while offhand is not, so need to manually check here
    local _, mainHandExpiration, _, _, _, offHandExpiration = GetWeaponEnchantInfo()
    if mainHandExpiration then
        mainHandExpiration = mainHandExpiration / 1000
    end

    -- check for sheild
    if not BuffCheck3:ItemIsEnchantable(GetInventoryItemLink("player", GetInventorySlotInfo("SecondaryHandSlot"))) then
        offHandExpiration = nil
    end
    if offHandExpiration then
        offHandExpiration = offHandExpiration / 1000
    end
    BuffCheck3:CheckWepExpiration(mainHandExpiration, offHandExpiration)
end

function BuffCheck3:CheckWepExpiration(exp1, exp2)
    -- update duration text
    if exp1 and exp2 then  -- both active, set to lowest timer
        if exp1 < exp2 then
            BuffCheck3:SetWepDuration(exp1)
        else
            BuffCheck3:SetWepDuration(exp2)
        end
    -- offhand is active but not mainhand
    elseif exp2 then
        BuffCheck3:SetWepDuration(exp2)
    -- either mainhand or neither is active - doesnt matter just set mainhand
    else
        BuffCheck3:SetWepDuration(exp1)
    end
    -- if 0 < exp1 or exp2 < 120 then flash all weapon buttons
    BuffCheck3:FlashWeaponBuffs((exp1 and exp1 < 120) or (exp2 and exp2 < 120))
end

function BuffCheck3:HasGivenExpirationWarning(consume)
    local _, expiration = BuffCheck3:IsBuffPresent(consume)
    if expiration then return expiration < 300 end

    -- weapon buff
    local _, mainHandExpiration, _, _, _, offHandExpiration = GetWeaponEnchantInfo()
    if mainHandExpiration then
        mainHandExpiration = mainHandExpiration / 1000
    end

    -- check for sheild
    if not BuffCheck3:ItemIsEnchantable(GetInventoryItemLink("player", GetInventorySlotInfo("SecondaryHandSlot"))) then
        offHandExpiration = nil
    end
    if offHandExpiration then
        offHandExpiration = offHandExpiration / 1000
    end

    return (mainHandExpiration and mainHandExpiration < 300) or (offHandExpiration and offHandExpiration < 300)
end

--=================================================================
-- Consume Frame Functions

-- updates the counts on the frame
function BuffCheck3:UpdateItemCounts()
    for _, f in pairs(BuffCheck3.AllConsumeButtons) do
        local fcount = getglobal(f:GetName().."Count")
        local count = BuffCheck3.BagContents[f.consume]
        if count == nil then
            -- should only be nil for items with bag count of 0
            count = 0
        end
        if count and fcount:GetText() ~= tostring(count) then
            fcount:SetText(count)
            if string.len(count) == 2 then
                fcount:ClearAllPoints()
                fcount:SetPoint("LEFT", f, "RIGHT", -16, -10)
            else
                fcount:ClearAllPoints()
                fcount:SetPoint("LEFT", f, "RIGHT", -10, -10)
            end
        end
    end
end

function BuffCheck3:ConsumeFrameButtonExists(consume)
    for _, f in pairs(BuffCheck3.AllConsumeButtons) do
        if f.consume == consume then
            return true
        end
    end
    return false
end

function BuffCheck3:CreateConsumeFrameButton(consume)
    local parent = getglobal("BuffCheck3Frame")
    local fname = "BuffCheck3FrameButton" .. table.getn(BuffCheck3.AllConsumeButtons)

    -- more info on the item
    local texture = GetItemIcon(consume)

    f = CreateFrame("Button", fname, parent, "BuffCheck3ButtonTemplate")
    f.consume = consume

    -- set icon
    local icon = getglobal(fname.."Icon")
    icon:SetTexture(texture)
    icon:SetVertexColor(1,1,1)

    --create cooldown frame
    local myCooldown = CreateFrame("Cooldown", f:GetName().."Cooldown", f, "CooldownFrameTemplate")
    myCooldown:SetAllPoints()

    f.cooldown = function(start, duration)
        myCooldown:SetCooldown(start, duration)
    end

    -- set the onclick attribute for SecureActionButton
    f:SetAttribute("item", consume)

    return f
end

-- manages the Active and Inactive List
function BuffCheck3:UpdateFrame()

    -- create a button for each consume if it doesnt already exist
    for _, consume in pairs(BuffCheck3_SavedConsumes) do
        if not BuffCheck3:ConsumeFrameButtonExists(consume) and BuffCheck3.BagContents[consume] then
            -- create the button and add it to the list
            table.insert(BuffCheck3.AllConsumeButtons,
                BuffCheck3:CreateConsumeFrameButton(consume))
        end
    end
    -- sort the buttons into Active and Inactive
    BuffCheck3:SortConsumeFrameButtons()
    -- add counts to the buttons
    BuffCheck3:UpdateItemCounts()

    BuffCheck3:ShowInactiveConsumes()
end

function BuffCheck3:SortConsumeFrameButtons()
    BuffCheck3.ActiveConsumes = {}
    BuffCheck3.InactiveConsumes = {}
    for _, f in pairs(BuffCheck3.AllConsumeButtons) do
        -- only add consumes that are in SavedConsumes
        if BuffCheck3:HasValue(BuffCheck3_SavedConsumes, f.consume) then
            local isactive = BuffCheck3:IsBuffPresent(f.consume)
            if isactive then
                table.insert(BuffCheck3.ActiveConsumes, f)
                if not BuffCheck3:IsWeaponBuff(f.consume) then
                    f.WasActive = true
                end
            else
                table.insert(BuffCheck3.InactiveConsumes, f)
            end
        end
    end
end

function BuffCheck3:HideConsumeFrameButton(consume)
    for _, f in pairs(BuffCheck3.AllConsumeButtons) do
        if f.consume == consume then
            f:Hide()
        end
    end
end

function BuffCheck3:HideActiveButtons()
    for _, f in pairs(BuffCheck3.ActiveConsumes) do
        if not BuffCheck3:HasGivenExpirationWarning(f.consume) then
            f:Hide()
        end
    end
end

function BuffCheck3:HideAllButtons()
    for _, f in pairs(BuffCheck3.AllConsumeButtons) do
        if f:IsShown() then
            f:Hide()
        end
    end
end

function BuffCheck3:ShowInactiveConsumes()
    local parent = getglobal("BuffCheck3Frame")
    local numInactive = table.getn(BuffCheck3.InactiveConsumes)
    local offset = 33

    for _, f in pairs(BuffCheck3.InactiveConsumes) do
        if UIFrameIsFlashing(f) then
            UIFrameFlashStop(f)
        end
    end

    if BuffCheck3_Config["vertical"] then
        BuffCheck3:HideActiveButtons()
        local i = 1
        for _, f in pairs(BuffCheck3.InactiveConsumes) do
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", parent, "TOPLEFT", 11, -11 - offset*(i-1))
            getglobal(f:GetName() .. "Duration"):SetText("")
            f:Show()
            i = i + 1
        end
        -- also show soon to expire active consumes
        for _, f in pairs(BuffCheck3.ActiveConsumes) do
            if BuffCheck3:HasGivenExpirationWarning(f.consume) then
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", parent, "TOPLEFT", 11, -11 - offset*(i-1))
                f:Show()
                numInactive = numInactive + 1
                i = i + 1
            end
        end
       -- update dimensions
       BuffCheck3Frame:SetWidth(52)
       BuffCheck3Frame:SetHeight(52 + offset*(numInactive -1))
    else
        -- horizontal
        BuffCheck3:HideActiveButtons()
        local i = 1
        for _, f in pairs(BuffCheck3.InactiveConsumes) do
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", parent, "TOPLEFT", 11 + offset*(i-1), -11)
            getglobal(f:GetName() .. "Duration"):SetText("")
            f:Show()
            i = i + 1
        end
        -- also show soon to expire active consumes
        for _, f in pairs(BuffCheck3.ActiveConsumes) do
            if BuffCheck3:HasGivenExpirationWarning(f.consume) then
                f:ClearAllPoints()
                f:SetPoint("TOPLEFT", parent, "TOPLEFT", 11 + offset*(i-1), -11)
                f:Show()
                numInactive = numInactive + 1
                i = i + 1
            end
        end
        -- update dimensions
        BuffCheck3Frame:SetWidth(52 + offset*(numInactive -1))
        BuffCheck3Frame:SetHeight(52)
    end

    -- if none active
    if BuffCheck3.AllActive and numInactive > 0 then
        BuffCheck3Frame:Show()
        BuffCheck3.AllActive = false
    end
    if numInactive == 0 then
        BuffCheck3:HideAllButtons()
        -- only want to hide temporarily so not using BuffCheck3:ShowFrame(false)
        BuffCheck3Frame:Hide()
        BuffCheck3.AllActive = true
    end
end

function BuffCheck3:SetDuration(f, exp1)
    BuffCheck3:FormatDuration(f, exp1)
end

function BuffCheck3:SetWepDuration(exp1)
    for _, f in pairs(BuffCheck3.ActiveConsumes) do
        if BuffCheck3:IsWeaponBuff(f.consume) then
            BuffCheck3:FormatDuration(f, exp1)
        end
    end
    for _, f in pairs(BuffCheck3.InactiveConsumes) do
        if BuffCheck3:IsWeaponBuff(f.consume) then
            BuffCheck3:FormatDuration(f, exp1)
        end
    end
end

function BuffCheck3:FlashWeaponBuffs(flash)
    for _, f in pairs(BuffCheck3.ActiveConsumes) do
        if BuffCheck3:IsWeaponBuff(f.consume) then
            if flash then
                if not UIFrameIsFlashing(f) then
                    UIFrameFlash(f, 0.5, 0.5, -1)
                end
            else
                if UIFrameIsFlashing(f) then
                    UIFrameFlashStop(f)
                end
            end
        end
    end
    for _, f in pairs(BuffCheck3.InactiveConsumes) do
        if BuffCheck3:IsWeaponBuff(f.consume) then
            if flash then
                if not UIFrameIsFlashing(f) then
                    UIFrameFlash(f, 0.5, 0.5, -1)
                end
            else
                if UIFrameIsFlashing(f) then
                    UIFrameFlashStop(f)
                end
            end
        end
    end
end

function BuffCheck3:FormatDuration(f, exp1)
    local fdur = getglobal(f:GetName() .. "Duration")
    if exp1 == nil then
        exp1 = 0
    end
    exp1 = floor(exp1)
    if exp1 < 10 then
        fdur:ClearAllPoints()
        fdur:SetPoint("LEFT", f, "RIGHT", -20, 2)
    else
        fdur:ClearAllPoints()
        fdur:SetPoint("LEFT", f, "RIGHT", -25, 2)
    end
    if exp1 > 60 then
        -- round to min
        exp1 = floor(exp1 / 60 + 0.5)
        exp1 = tostring(exp1) .. "m"
    end
    if exp1 == 0 then
        fdur:SetText("")
    else
        fdur:SetText(exp1)
    end
end

--=================================================================
-- Tooltip Stuff

function BuffCheck3:ShowConsumeListTooltip(consume, name)
    local _, link = GetItemInfo(consume)
    GameTooltip:SetOwner(getglobal(name), "ANCHOR_BOTTOMRIGHT")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
end

function BuffCheck3:ShowConsumeFrameTooltip(consume, name)
    local _, link = GetItemInfo(consume)
    GameTooltip:SetOwner(getglobal(name), "ANCHOR_BOTTOMRIGHT")
    GameTooltip:SetHyperlink(link)
    GameTooltip:Show()
end

function BuffCheck3:ShowWeaponTooltip(fname)
    local id = string.sub(fname, -1)
    if id == "1" then
        GameTooltip:SetOwner(getglobal("BuffCheck3WeaponButton"..id), "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetInventoryItem("player", GetInventorySlotInfo("MainHandSlot"))
        GameTooltip:Show()
    elseif id == "2" then
        GameTooltip:SetOwner(getglobal("BuffCheck3WeaponButton"..id), "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetInventoryItem("player", GetInventorySlotInfo("SecondaryHandSlot"))
        GameTooltip:Show()
    end
end

--=================================================================
-- WeaponButton Stuff

function BuffCheck3:ShowWeaponButtons(f)
    BuffCheck3WeaponFrame:ClearAllPoints()
    BuffCheck3WeaponFrame:SetPoint("TOPLEFT", f, "TOPLEFT", -33, -33)

    -- mainhand
    local mainHandTexture = GetInventoryItemTexture("player", GetInventorySlotInfo("MainHandSlot"))
    if mainHandTexture then
        BuffCheck3WeaponButton1Icon:SetTexture(mainHandTexture)
        BuffCheck3WeaponButton1:Show()
        
        -- set the onclick attribute for SecureActionButton
        local link = GetInventoryItemLink("player", GetInventorySlotInfo("MainHandSlot"))
        BuffCheck3WeaponButton1:SetAttribute("item", BuffCheck3:LinkToName(link))
    else
        BuffCheck3WeaponButton1:Hide()
    end

    -- offhand
    local offHandTexture = GetInventoryItemTexture("player", GetInventorySlotInfo("SecondaryHandSlot"))
    if offHandTexture then
        BuffCheck3WeaponButton2Icon:SetTexture(offHandTexture)
        BuffCheck3WeaponButton2:Show()
        
        -- set the onclick attribute for SecureActionButton
        local link = GetInventoryItemLink("player", GetInventorySlotInfo("SecondaryHandSlot"))
        BuffCheck3WeaponButton2:SetAttribute("item", BuffCheck3:LinkToName(link))
    else
        BuffCheck3WeaponButton2:Hide()
    end

    BuffCheck3WeaponFrame:Show()
end

--=================================================================
-- Helper Functions

function BuffCheck3:SendMessage(msg)
    local msg = string.format(BuffCheck3_PrintFormat, msg)
    DEFAULT_CHAT_FRAME:AddMessage(string.format(BuffCheck3_PrintFormat, "BuffCheck3: ") .. msg)
end

-- used for debug
function BuffCheck3:LinkToName(consume)
    -- matches text inside square brackets ex: [...] -> ...
    return string.match(consume, "%[(.+)%]")
end

function BuffCheck3:LinkToID(link)
    return string.match(link, ":(%d+)")
end

function BuffCheck3:HasValue(tab, val)
    for _, value in pairs(tab) do
        if value == val then
            return true
        end
    end
    return false
end

function BuffCheck3:GetIndexInTable(tab, val)
    for i, value in ipairs(tab) do
        if value == val then
            return i
        end
    end
    return -1
end

-- debug only
function BuffCheck3:tprint(tbl, indent)
    if not indent then indent = 0 end
    for k, v in pairs(tbl) do
        local formatting = string.rep("  ", indent) .. k .. ": "
        if type(v) == "table" then
            DEFAULT_CHAT_FRAME:AddMessage(formatting)
            BuffCheck3:tprint(v, indent+1)
        elseif type(v) == 'boolean' then
            DEFAULT_CHAT_FRAME:AddMessage(formatting .. tostring(v))
        else
            DEFAULT_CHAT_FRAME:AddMessage(formatting .. v)
        end
    end
end

tprint = function(tbl, indent)
    if not indent then indent = 0 end
    for k, v in pairs(tbl) do
        local formatting = string.rep("  ", indent) .. k .. ": "
        if type(v) == "table" then
            DEFAULT_CHAT_FRAME:AddMessage(formatting)
            tprint(v, indent+1)
        elseif type(v) == 'boolean' then
            DEFAULT_CHAT_FRAME:AddMessage(formatting .. tostring(v))
        else
            DEFAULT_CHAT_FRAME:AddMessage(formatting .. v)
        end
    end
end

function BuffCheck3:Test()
    for _, f in pairs(BuffCheck3.InactiveConsumes) do
        f.cooldown(GetTime(), 10)
    end
end
