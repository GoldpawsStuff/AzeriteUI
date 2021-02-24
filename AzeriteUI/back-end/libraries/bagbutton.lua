local LibBagButton = Wheel:Set("LibBagButton", 28)
if (not LibBagButton) then	
	return
end

local LibEvent = Wheel("LibEvent")
assert(LibEvent, "LibBagButton requires LibEvent to be loaded.")

local LibMessage = Wheel("LibMessage")
assert(LibMessage, "LibBagButton requires LibMessage to be loaded.")

local LibClientBuild = Wheel("LibClientBuild")
assert(LibClientBuild, "LibBagButton requires LibClientBuild to be loaded.")

local LibFrame = Wheel("LibFrame")
assert(LibFrame, "LibBagButton requires LibFrame to be loaded.")

local LibTooltipScanner = Wheel("LibTooltipScanner")
assert(LibTooltipScanner, "LibBagButton requires LibTooltipScanner to be loaded.")

local LibTooltip = Wheel("LibTooltip")
assert(LibTooltip, "LibBagButton requires LibTooltip to be loaded.")

LibEvent:Embed(LibBagButton)
LibMessage:Embed(LibBagButton)
LibFrame:Embed(LibBagButton)
LibTooltip:Embed(LibBagButton)

-- Lua API
local _G = _G
local assert = assert
local debugstack = debugstack
local error = error
local pairs = pairs
local select = select
local setmetatable = setmetatable
local string_format = string.format
local string_join = string.join
local string_match = string.match
local table_insert = table.insert
local table_sort = table.sort
local tonumber = tonumber
local type = type
local unpack = unpack

-- WoW API
local GetBagName = GetBagName
local GetContainerItemLink = GetContainerItemLink
local GetContainerNumFreeSlots = GetContainerNumFreeSlots
local GetContainerNumSlots = GetContainerNumSlots
local GetCVarBool = GetCVarBool
local GetItemInfo = GetItemInfo
local GetItemInfoInstant = GetItemInfoInstant
local InRepairMode = InRepairMode
local IsLoggedIn = IsLoggedIn
local IsModifiedClick = IsModifiedClick
local ResetCursor = ResetCursor
local ShowContainerSellCursor = ShowContainerSellCursor
local ShowInspectCursor = ShowInspectCursor
local SpellIsTargeting = SpellIsTargeting

-- Constants
local IsClassic = LibClientBuild:IsClassic()
local IsRetail = LibClientBuild:IsRetail()

-- Library registries
LibBagButton.embeds = LibBagButton.embeds or {}
LibBagButton.buttons = LibBagButton.buttons or {} -- cache of buttons spawned
LibBagButton.buttons.Bag = LibBagButton.buttons.Bag or {}
LibBagButton.buttons.BagSlot = LibBagButton.buttons.BagSlot or {}
LibBagButton.buttons.Bank = LibBagButton.buttons.Bank or {}
LibBagButton.buttons.BankSlot = LibBagButton.buttons.BankSlot or {}
LibBagButton.buttons.ReagentBank = LibBagButton.buttons.ReagentBank or {}
LibBagButton.buttonParents = LibBagButton.buttonParents or {} -- cache of hidden button parents spawned
LibBagButton.buttonSlots = LibBagButton.buttonSlots or {} -- cache of actual usable button objects
LibBagButton.containers = LibBagButton.containers or {} -- cache of virtual containers spawned
LibBagButton.contents = LibBagButton.contents or {} -- cache of actual bank and bag contents
LibBagButton.queuedContainerIDs = LibBagButton.queuedContainerIDs or {} -- Queue system for uncached items 
LibBagButton.queuedItemIDs = LibBagButton.queuedItemIDs or {} -- Queue system for uncached items 
LibBagButton.blizzardMethods = LibBagButton.blizzardMethods or {}

-- Speed
local Buttons = LibBagButton.buttons
local ButtonParents = LibBagButton.buttonParents
local ButtonSlots = LibBagButton.buttonSlots
local Containers = LibBagButton.containers
local Contents = LibBagButton.contents
local QueuedContainerIDs = LibBagButton.queuedContainerIDs
local QueuedItemIDs = LibBagButton.queuedItemIDs
local BlizzardMethods = LibBagButton.blizzardMethods

-- Button Creation Templates
-----------------------------------------------------------------
-- Sourced from FrameXML/BankFrame.lua
-- Bag containing the 7 (or 6 in classic) bank bag buttons. 
local BANK_SLOT_CONTAINER = -4

-- This one does not exist. We made it up.
local BAG_SLOT_CONTAINER = -100

-- Frame type of slot buttons.
local BUTTON_TYPE = (IsClassic) and "Button" or "ItemButton" 

-- Frame template of itembuttons in each bagType.
-- This table will have both the bagTypes and all bagIDs as keys, 
-- making it a good tool to compare slot button compatibility on bagID changes.
local ButtonTemplates = {
	Bag = "ContainerFrameItemButtonTemplate", -- bag itembutton
	Bank = "BankItemButtonGenericTemplate", -- bank itembutton
	ReagentBank = "BankItemButtonGenericTemplate", -- reagent bank itembutton
	KeyRing = "ContainerFrameItemButtonTemplate", -- keyring itembutton
	BagSlot = "BagSlotButtonTemplate", -- equippable bag container slot
	BankSlot = "BankItemButtonBagTemplate" -- equippable bank container slot
}

-- Localized names for the bags. 
-- Note that some names can be generated on-the-fly, 
-- so we're intentionally avoiding to list a few here.
local BagNames = { [BACKPACK_CONTAINER] = BACKPACK_TOOLTIP, [BANK_CONTAINER] = BANK }

-- Simple lookup table to get bagType from a provided bagID.
local BagTypesFromID = { 
	[BACKPACK_CONTAINER] = "Bag", 
	[BANK_CONTAINER] = "Bank", 
	[BAG_SLOT_CONTAINER] = "BagSlot", 
	[BANK_SLOT_CONTAINER] = "BankSlot" 
}

-- Setup all bag tables.
local bagIDs = { BACKPACK_CONTAINER } -- indexed 
local isBagID = { [BACKPACK_CONTAINER] = true } -- hashed
for id = BACKPACK_CONTAINER + 1, NUM_BAG_SLOTS do
	isBagID[id] = true
	bagIDs[#bagIDs + 1] = id
	ButtonTemplates[id] = ButtonTemplates.Bag
	BagTypesFromID[id] = "Bag"
end
ButtonTemplates[BACKPACK_CONTAINER] = ButtonTemplates.Bag

-- Setup all bank tables.
local bankIDs = { BANK_CONTAINER } -- indexed 
local isBankID = { [BANK_CONTAINER] = true } -- hashed
for id = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do
	isBankID[id] = true
	bankIDs[#bankIDs + 1] = id
	ButtonTemplates[id] = ButtonTemplates.Bank
	BagTypesFromID[id] = "Bank"
end
ButtonTemplates[BANK_CONTAINER] = ButtonTemplates.Bank

-- This only exists in classic, 
-- but we leave the empty tables for a simpler API.
local isKeyRingID = {} -- hashed
if (IsClassic) then
	isBagID[KEYRING_CONTAINER] = true
	isKeyRingID[KEYRING_CONTAINER] = true
	bagIDs[#bagIDs + 1] = KEYRING_CONTAINER
	ButtonTemplates[KEYRING_CONTAINER] = ButtonTemplates.KeyRing
	BagNames[KEYRING_CONTAINER] = KEYRING
	BagTypesFromID[KEYRING_CONTAINER] = "KeyRing"
end

-- This only exists in retail, 
-- but we leave the empty tables for a simpler API.
local isReagentBankID = {} -- hashed
if (IsRetail) then
	isBankID[REAGENTBANK_CONTAINER] = true
	isReagentBankID[REAGENTBANK_CONTAINER] = true
	bankIDs[#bankIDs + 1] = REAGENTBANK_CONTAINER
	ButtonTemplates[REAGENTBANK_CONTAINER] = ButtonTemplates.ReagentBank
	BagNames[REAGENTBANK_CONTAINER] = REAGENT_BANK
	BagTypesFromID[REAGENTBANK_CONTAINER] = "ReagentBank"
end

-- Half-truths. We need numbers to index both. 
ButtonTemplates[BAG_SLOT_CONTAINER] = ButtonTemplates.BagSlot
ButtonTemplates[BANK_SLOT_CONTAINER] = ButtonTemplates.BankSlot

-- Utility Functions
-----------------------------------------------------------------
-- Syntax check 
local check = function(value, num, ...)
	assert(type(num) == "number", ("Bad argument #%.0f to '%s': %s expected, got %s"):format(2, "Check", "number", type(num)))
	for i = 1,select("#", ...) do
		if type(value) == select(i, ...) then 
			return 
		end
	end
	local types = string_join(", ", ...)
	local name = string_match(debugstack(2, 2, 0), ": in function [`<](.-)['>]")
	error(string_format("Bad argument #%.0f to '%s': %s expected, got %s", num, name, types, type(value)), 3)
end

local sortAscending = function(a,b)
	return a < b
end

local sortDescending = function(a,b)
	return a > b
end


-- Button Templates
-- These do not have to be connected to any container object,
-- and thus do not rely on bag/bank opening events to be shown.
-- You can use them to track quest items, food, whatever.
-----------------------------------------------------------------
local Button = LibBagButton:CreateFrame(BUTTON_TYPE)
local Button_MT = { __index = Button }

local Methods = getmetatable(Button).__index
local CreateFontString = Methods.CreateFontString
local CreateTexture = Methods.CreateTexture
local IsEventRegistered = Methods.IsEventRegistered
local SetSize = Methods.SetSize
local SetWidth = Methods.SetWidth
local SetHeight = Methods.SetHeight
local SetPoint = Methods.SetPoint
local SetAllPoints = Methods.SetAllPoints
local ClearAllPoints = Methods.ClearAllPoints

Button.SetSize = function(self, ...)
	SetSize(self, ...)
	ButtonSlots[self]:SetSize(...)
end

Button.SetWidth = function(self, ...)
	SetWidth(self, ...)
	ButtonSlots[self]:SetWidth(...)
end

Button.SetHeight = function(self, ...)
	SetHeight(self, ...)
	ButtonSlots[self]:SetHeight(...)
end

-- Set the bagID of the button.
-- Only accept changes within the same bagType range,
-- silentyly fail if a template change is attempted.
-- Reason we can't change templates is because of the
-- Blizzard OnClick functionality needed for interaction,
-- which can't be modified, added or changed after creation.
Button.SetBagID = function(self, bagID)
	-- If we requested a new bagID, see if the old and new share button templates,
	-- as this will tell us whether or not the bagIDs are interchangeable.
	if (ButtonTemplates[self.bagType] == ButtonTemplates[bagID]) then
		ButtonParents[self]:SetID(bagID)
		self.bagID = bagID
		self:Update()
	end
end

-- Change the slotID of a button.
-- We can in theory set this to non-existing IDs, but don't.
Button.SetSlotID = function(self, slotID)
	ButtonSlots[self]:SetID(slotID)
	self.slotID = slotID
	self:Update()
end

-- Change the bagID and slotID at once.
-- Only accept changes within the same bagType range,
-- silentyly fail if a template change is attempted.
-- Reason we can't change templates is because of the
-- Blizzard OnClick functionality needed for interaction,
-- which can't be modified, added or changed after creation.
Button.SetBagAndSlotID = function(self, bagID, slotID)
	-- If we requested a new bagID, see if the old and new share button templates,
	-- as this will tell us whether or not the bagIDs are interchangeable.
	if (ButtonTemplates[self.bagType] == ButtonTemplates[bagID]) then
		ButtonParents[self]:SetID(bagID)
		ButtonSlots[self]:SetID(slotID)
		self.bagID = bagID
		self.slotID = slotID
		self:Update()
	end
end

Button.GetBagID = function(self)
	return self.bagID
end

Button.GetSlotID = function(self)
	return self.slotID
end

Button.GetBagAndSlotID = function(self)
	return self.bagID, self.slotID
end

-- Updates the icon of a slot button.
Button.UpdateIcon = function(self)
	self.Icon:SetTexture(self.itemIcon)
end

-- Updates the stack/charge count of a slot button.
Button.UpdateCount = function(self)
end

-- Updates the rarity colorign of a slot button.
Button.UpdateRarity = function(self)
end

-- Updates the quest icons of a slot button.
Button.UpdateQuest = function(self)
end

-- All the following are applied to all button types, 
-- and thus should need to do relevant checks themselves.
-----------------------------------------------------------------

-- Updates all the sub-elements of a slot button at once.
Button.Update = function(self)
	-- Update flags and information
	local clear
	if (self.bagID) and (self.slotID) then
		local Item = LibBagButton:GetBlizzardContainerSlotCache(self.bagID, self.slotID)
		if (Item) then
			self.itemID = Item.itemID
			self.itemString = Item.itemString
			self.itemName = Item.itemName
			self.itemLink = Item.itemLink
			self.itemRarity = Item.itemRarity
			self.itemLevel = Item.itemLevel
			self.itemMinLevel = Item.itemMinLevel
			self.itemType = Item.itemType
			self.itemSubType = Item.itemSubType
			self.itemStackCount = Item.itemStackCount
			self.itemEquipLoc = Item.itemEquipLoc
			self.itemEquipLocLabel = Item.itemEquipLocLabel
			self.itemIcon = Item.itemIcon
			self.itemSellPrice = Item.itemSellPrice
			self.itemClassID = Item.itemClassID
			self.itemSubClassID = Item.itemSubClassID
			self.bindType = Item.bindType
			self.expacID = Item.expacID
			self.itemSetID = Item.itemSetID
			self.isCraftingReagent = Item.isCraftingReagent
			self.isUsable = Item.isUsable
			self.isQuestItem = Item.isQuestItem
			self.isQuestActive = Item.isQuestActive
			self.isUsableQuestItem = Item.isUsableQuestItem
			self.questID = Item.questID
		else
			clear = true
		end
	else
		clear = true
	end
	if (clear) then
		self.itemID = nil
		self.itemString = nil
		self.itemName = nil
		self.itemLink = nil
		self.itemRarity = nil
		self.itemLevel = nil
		self.itemMinLevel = nil
		self.itemType = nil
		self.itemSubType = nil
		self.itemStackCount = nil
		self.itemEquipLoc = nil
		self.itemEquipLocLabel = nil
		self.itemIcon = ""
		self.itemSellPrice = nil
		self.itemClassID = nil
		self.itemSubClassID = nil
		self.bindType = nil
		self.expacID = nil
		self.itemSetID = nil
		self.isCraftingReagent = nil
		self.isUsable = nil
		self.isQuestItem = nil
		self.isQuestActive = nil
		self.isUsableQuestItem = nil
		self.questID = nil
	end

	-- Update layers
	self:UpdateIcon()
	self:UpdateCount()
	self:UpdateRarity()
	self:UpdateQuest()

	-- Run user post updates
	if (self._owner) and (self._owner.PostCreateItemButton) then
		self._owner:PostUpdateItemButton(self)
	end
end

-- Basically a tooltip function that needs regular updates.
Button.OnUpdate = function(self)
	-- Avoid nil bugs. 
	if (not self.bagID) or (not self.bagID) then
		return
	end

	-- Is it a classic keyring? Add code. 

	-- retrieve item info from tooltip backend
	local showSell
	local tooltip = self:GetTooltip() 
	local Item = LibBagButton:GetBlizzardContainerSlotCache(self.bagID, self.slotID)
	
	-- calculate tooltip anchors
	tooltip:SetSmartItemAnchor(self, tooltip.tooltipAnchorX or 4, tooltip.tooltipAnchorY or 0) 

	local 	hasCooldown, 
			repairCost, 
			speciesID, 
			level, 
			breedQuality, 
			maxHealth, 
			power, 
			speed, 
			name = tooltip:SetBagItem(self.bagID, self.slotID)


	-- check for modified clicks, show compare tips if need be.
	if (IsModifiedClick("COMPAREITEMS")) or (GetCVarBool("alwaysCompareItems")) then
		-- Show compare item. 
	end

	if (InRepairMode()) and ((repairCost) and (repairCost > 0)) then
		-- REPAIR_COST = "Repair Cost:"
		-- show tooltip

	elseif (MerchantFrame:IsShown()) and (MerchantFrame.selectedTab == 1) then
		showSell = 1
	end

	if ( not SpellIsTargeting() ) then
		if (IsModifiedClick("DRESSUP")) and ((Item) or (self.hasItem)) then
			ShowInspectCursor()

		elseif (showSell) then
			ShowContainerSellCursor(self.bagID, self.slotID)

		elseif (self.readable) then
			ShowInspectCursor()

		else
			ResetCursor()
		end
	end

end

Button.OnEnter = function(self)
	self:OnUpdate()
end

Button.OnLeave = function(self)
	self:OnUpdate()

	local tooltip = self:GetTooltip()
	if (tooltip:IsShown()) then
		tooltip:Hide()
	end

	if (not SpellIsTargeting()) then
		ResetCursor()		
	end
end

Button.OnHide = function(self)
	self.isShown = nil
end

Button.OnShow = function(self)
	self.isShown = true
	self:Update()
end

Button.OnEvent = function(self)
	if (not self.isShown) then
		return
	end
end

Button.GetTooltip = function(self)
	return LibBagButton:GetBagButtonTooltip()
end

-- Container Template
-- This is NOT the equivalent of the blizzard bags or containers,
-- as our containers are not restricted to nor mirror specific bagIDs.
-- Our containers do however respond to regular game events
-- for showing/hiding/toggling the bags and bank.
-----------------------------------------------------------------
local Container = LibBagButton:CreateFrame("Frame")
local Container_MT = { __index = Container }

Container.SetFilter = function(self, filterMethod)
end

Container.SetSorting = function(self, sortMethod)
end

Container.SpawnItemButton = function(self, bagType)
	if (not self.buttons) then
		self.buttons = {}
	end
	if (not self.buttons[bagType]) then
		self.buttons[bagType] = {}
	end

	local button = LibBagButton:SpawnItemButton(bagType)
	button:SetParent(self)
	button._owner = self

	if (self.PostCreateItemButton) then
		self:PostCreateItemButton(button)
	end

	-- Insert the virtual button slot object into the correct cache.
	table_insert(self.buttons[bagType], button) 

	return button
end

Container.GetTooltip = function(self)
	return LibBagButton:GetBagButtonTooltip()
end

Container.OnEvent = function(self, event, ...)
end

-- Library API
-- *The 'self' is the library here.
-----------------------------------------------------------------
LibBagButton.GetBagButtonTooltip = function(self)
	return LibBagButton:GetTooltip("GP_BagButtonTooltip") or LibBagButton:CreateTooltip("GP_BagButtonTooltip")
end

--[[-- 
	local numberOfFreeSlots, bagType = GetContainerNumFreeSlots(bagID)
	bagType = 2^(bitfield-1) 
	(https://wow.gamepedia.com/ItemFamily)

		bit category
		-------------------------------------
		 4 	Leatherworking Supplies
		 5 	Inscription Supplies
		 6 	Herbs
		 7 	Enchanting Supplies
		 8 	Engineering Supplies
		10 	Gems
		11 	Mining Supplies
		12 	Soulbound Equipment
		16 	Fishing Supplies
		17 	Cooking Supplies
		20 	Toys
		21 	Archaeology
		22 	Alchemy
		23 	Blacksmithing
		24 	First Aid
		25 	Jewelcrafting
		26 	Skinning
		27 	Tailoring 
--]]--

-- Retrieve the existing or create a blank cache for this blizzard container.
LibBagButton.GetBlizzardContainerCache = function(self, bagID)
	if (not Contents[bagID]) then
		Contents[bagID] = {}
	end
	return Contents[bagID]
end

-- Retrieve the existing or create a blank cache for this blizzard slot.
LibBagButton.GetBlizzardContainerSlotCache = function(self, bagID, slotID)
	if (not Contents[bagID]) then
		Contents[bagID] = {}
	end
	if (not Contents[bagID][slotID]) then
		Contents[bagID][slotID] = {}
	end
	return Contents[bagID][slotID]
end

-- Clear the contents of a cached blizzard container slot if it exists.
LibBagButton.ClearBlizzardContainerSlot = function(self, bagID, slotID)
	if (Contents[bagID]) then
		if (Contents[bagID][slotID]) then
			for i in pairs(Contents[bagID][slotID]) do
				Contents[bagID][slotID][i] = nil
			end
		end
	end
end

-- Parse and cache a specific slot in a blizzard container. 
LibBagButton.ParseBlizzardContainerSlot = function(self, bagID, slotID)
	local _
	local itemID, itemName, itemIcon, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount
	local itemEquipLoc, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID, isCraftingReagent
	local isQuestItem, questID, isActive

	-- Check if the Blizzard slot has an item in it
	local itemLink = GetContainerItemLink(bagID, slotID)
	if (itemLink) then

		-- Check if we have cached the item previously,
		-- or create an empty cache table if none exist.
		local Item = self:GetBlizzardContainerSlotCache(bagID, slotID)

		-- Compare the cache's itemlink to the blizzard itemlink, 
		-- and update or retrieve the contents to our cache if need be.
		if (Item.itemLink ~= itemLink) then

			-- No quest item info in classic
			if (not IsClassic) then
				isQuestItem, questID, isActive = GetContainerItemQuestInfo(bagID, slotID)
			end

			itemName, _, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemIcon, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID, isCraftingReagent = GetItemInfo(itemLink)
			
			-- Get some basic info if the item hasn't been cached up yet
			if (not itemName) then
				if (not QueuedContainerIDs[bagID]) then
					QueuedContainerIDs[bagID] = {}
				end
				if (not QueuedContainerIDs[bagID][slotID]) then
					QueuedContainerIDs[bagID][slotID] = itemID
				end
				self:RegisterEvent("GET_ITEM_INFO_RECEIVED", "OnEvent")
	
				-- Use the client-only API for faster lookups here
				itemID, itemType, itemSubType, itemEquipLoc, itemIcon, itemClassID, itemSubClassID = GetItemInfoInstant(itemLink)
			end

			Item.itemID = itemID or tonumber(string_match(itemLink, "item:(%d+)"))
			Item.itemString = string_match(itemLink, "item[%-?%d:]+")
			Item.itemName = itemName
			Item.itemLink = itemLink
			Item.itemRarity = itemRarity
			Item.itemLevel = itemLevel
			Item.itemMinLevel = itemMinLevel
			Item.itemType = itemType
			Item.itemSubType = itemSubType
			Item.itemStackCount = itemStackCount
			Item.itemEquipLoc = itemEquipLoc
			Item.itemEquipLocLabel = (itemEquipLoc and (itemEquipLoc ~= "")) and _G[itemEquipLoc] or nil
			Item.itemIcon = itemIcon
			Item.itemSellPrice = itemSellPrice
			Item.itemClassID = itemClassID
			Item.itemSubClassID = itemSubClassID
			Item.bindType = bindType
			Item.expacID = expacID
			Item.itemSetID = itemSetID
			Item.isCraftingReagent = isCraftingReagent
			Item.isUsable = IsUsableItem(Item.itemID)
			Item.isQuestItem = isQuestItem or (itemClassID == LE_ITEM_CLASS_QUESTITEM)
			Item.isQuestActive = isQuestItem and isActive
			Item.isUsableQuestItem = Item.isQuestItem and Item.isUsable
			Item.questID = isQuestItem and questID
		end

	else
		-- The blizzard slot has no item, so we clear our cache if it exists.
		self:ClearBlizzardContainerSlot(bagID, slotID)
	end
end

-- Parse and cache all the slots of a blizzard container, and the container itself. 
LibBagButton.ParseSingleBlizzardContainer = function(self, bagID)

	local numberOfSlots = GetContainerNumSlots(bagID) or 0 -- returns 0 before the BAG_UPDATE for the bagID has fired.
	local numberOfFreeSlots, bagType = GetContainerNumFreeSlots(bagID) or -1

	if (numberOfSlots > 0) then
		local cache = self:GetBlizzardContainerCache(bagID)
		cache.bagType = bagType or 0 -- any other value than 0 means profession bag.
		cache.freeSlots = numberOfFreeSlots 
		cache.totalSlots = numberOfSlots
		cache.name = BagNames[bagID] or GetBagName(bagID)

		for slotID = 1,numberOfSlots do
			self:ParseBlizzardContainerSlot(bagID, slotID)
		end
	end
end

-- Parse and cache specific multiple blizzard containers. 
LibBagButton.ParseMultipleBlizzardContainers = function(self, ...)
	local bagID
	local numContainers = select("#", ...)
	if (numContainers) and (numContainers > 0) then
		for i = 1,numContainers do
			bagID = select(i, ...)
			self:ParseSingleBlizzardContainer(bagID)
		end
	end
end

-- Shows your containers containing bag buttons.
-- Suppresses the blizzard method if 'true' is returned.
LibBagButton.ShowBags = function(self)
	local hasBags
	for container, bagType in pairs(Containers) do
		if (bagType == "Bag") then
			container:Show()
			hasBags = true
		end
	end
	-- A return value other than false
	-- suppresses the blizzard methods.
	return hasBags
end

-- Hides your containers containing bag buttons.
LibBagButton.HideBags = function(self)
	local hasBags
	for container, bagType in pairs(Containers) do
		if (bagType == "Bag") then
			container:Hide()
			hasBags = true
		end
	end
	-- A return value other than false
	-- suppresses the blizzard methods.
	return hasBags
end

-- Toggles your bag frames.
-- Suppresses the blizzard method if 'true' is returned.
LibBagButton.ToggleBags = function(self)
	-- Check if we have bag containers, and if any are shown
	local hasBags, shouldHide
	for container, bagType in pairs(Containers) do
		if (bagType == "Bag") then
			-- We have bag containers.
			hasBags = true 
			if (container:IsShown()) then 
				-- they are visible, so this is a hide operation.
				shouldHide = true 
				-- If both flags are true, 
				-- no further iteration is needed.
				if (hasBags) then
					break
				end
			end
		end
	end
	-- If bags were found, we need a 2nd pass to toggle visibility.
	if (hasBags) then
		local changesMade
		for container, bagType in pairs(Containers) do
			if (bagType == "Bag") then
				if (container:IsShown()) then
					if (shouldHide) then
						changesMade = true
					end
				else
					if (not shouldHide) then
						changesMade = true
					end
				end
				container:SetShown((not shouldHide))
			end
		end
		-- Alert the environment.
		if (changesMade) then
			if (shouldHide) then
				self:SendMessage("GP_BAGS_HIDDEN")
			else
				self:SendMessage("GP_BAGS_SHOWN")
			end
		end
	end
	-- A return value other than false
	-- suppresses the blizzard methods.
	return hasBags
end

-- Displays your bank frames.
-- Will use stored information when available, 
-- making it possible to track bank contents when not at the bank.
-- TODO: Add API to assign a cache at container creation!
LibBagButton.ShowBank = function(self)
end

-- Hides bank frames.
LibBagButton.HideBank = function(self)
end

-- Toggles your bank frames.
LibBagButton.ToggleBank = function(self)
end

-- Global function names, 
-- and our library equivalents.
-- Note: We should check for library version if we change this!
local methodByGlobal = {
	["ToggleAllBags"] = "ToggleBags",
	["ToggleBackpack"] = "ToggleBags",
	["ToggleBag"] = "ToggleBags",
	["OpenAllBags"] = "ShowBags",
	["OpenBackpack"] = "ShowBags",
	["OpenBag"] = "ShowBags",
	["CloseAllBags"] = "HideBags" -- only replace the full hide function, not singular bags.
}

-- Method to hook the blizzard bag toggling functions.
LibBagButton.HookBlizzardBagFunctions = function(self)
	-- Replace the global funcs, or update the replacements 
	-- if this was a library upgrade. 
	-- Note: We should check for library version if we change this!
	for globalName,method in pairs(methodByGlobal) do
		local globalFunc = _G[globalName]
		if (globalFunc) then

			-- Only store the global once, to avoid overwritring precious hooks.
			BlizzardMethods[globalName] = BlizzardMethods[globalName] or globalFunc

			-- Upvalue method names and replace the global function.
			local globalName, method = globalName, method
			local func = function(...)
				if (not LibBagButton[method](LibBagButton)) then
					BlizzardMethods[globalName](...)
				end
			end
			_G[globalName] = func
		end
	end
end

-- Method to restore blizzard bag toggling functions.
LibBagButton.UnhookBlizzardBagFunctions = function(self)
	for globalName,func in pairs(BlizzardMethods) do
		_G[globalName] = func
	end
end

LibBagButton.OnEvent = function(self, event, ...)
	-- Todo:
	-- item locks changed: ITEM_LOCK_CHANGED: bagID, slotID
	-- number of available slots? BAG_SLOT_FLAGS_UPDATED: bagID
	-- number of available slots? BANK_BAG_SLOT_FLAGS_UPDATED: bagID
	-- cooldowns changed: BAG_UPDATE_COOLDOWN
	-- new item highlight: BAG_NEW_ITEMS_UPDATED
	-- item upgrade icons: (event == "UNIT_INVENTORY_CHANGED") or (event == "PLAYER_SPECIALIZATION_CHANGED")
	-- quest icons: (event == "QUEST_ACCEPTED") or (event == "UNIT_QUEST_LOG_CHANGED" and (arg1 == "player"))

	if (event == "BANKFRAME_OPENED") then
		self.atBank = true
		self:ParseMultipleBlizzardContainers(unpack(bankIDs))
		self:ShowBank()
		self:ShowBags()
		self:SendMessage("GP_BANKFRAME_OPENED")

	elseif (event == "BANKFRAME_CLOSED") then
		self.atBank = nil
		self:HideBank()
		self:HideBags()
		self:SendMessage("GP_BANKFRAME_CLOSED")
		
	elseif (event == "BAG_OPEN") then
		local bagID = ...
		if (bagID) and (BagTypesFromID[bagID]) then
			self:ShowBags()
		end

	elseif (event == "BAG_CLOSED") then
		local bagID = ...
		if (bagID) and (BagTypesFromID[bagID]) then
			self:HideBags()
		end

	elseif (event == "BAG_UPDATE") then
		local bagID = ...

		-- This is where the actual magic happens. 
		self.parsingRequired = true
		self:ParseSingleBlizzardContainer(bagID)
		self:SendMessage("GP_BAG_UPDATE", bagID)

	elseif (event == "GET_ITEM_INFO_RECEIVED") then
		local updatedItemID, success = ...
		for bagID in pairs(QueuedContainerIDs) do
			for slotID, itemID in pairs(QueuedContainerIDs[bagID]) do
				if (itemID == updatedItemID) then

					-- Clear the entry to avoid parsing it again
					QueuedContainerIDs[bagID][slotID] = nil

					-- Full item info is availble
					if (success) then
						-- Parse this slot
						self:ParseBlizzardContainerSlot(bagID, slotID)
						self:SendMessage("GP_GET_ITEM_INFO_RECEIVED",  updatedItemID, success, bagID, slotID)
						self:SendMessage("GP_BAG_UPDATE", bagID, slotID)

					-- Item does not exist, clear it
					elseif (success == nil) then
						-- Clear this slot
						self.parsingRequired = true
						self:ClearBlizzardContainerSlot(bagID, slotID)
						self:SendMessage("GP_GET_ITEM_INFO_RECEIVED",  updatedItemID, success, bagID, slotID)
						self:SendMessage("GP_BAG_UPDATE", bagID, slotID)
					end

				end
			end
		end
		-- Check if anything is still queued
		for bagID in pairs(QueuedContainerIDs) do
			for slotID, itemID in pairs(QueuedContainerIDs[bagID]) do
				-- If anything is found, just return
				return 
			end
		end
		-- Kill off the event if no more itemslots are queued
		self:UnregisterEvent("GET_ITEM_INFO_RECEIVED", "OnEvent")
		-- Fire a custom event to indicate the queue has been parsed
		-- and all delayed item information has been received.
		self:SendMessage("GP_BAGS_READY")

	elseif (event == "PLAYER_ENTERING_WORLD") then

		-- Only ever want this once after library enabling.
		self:UnregisterEvent("PLAYER_ENTERING_WORLD", "OnEvent")

		-- Now we can start tracking stuff
		self:RegisterEvent("BANKFRAME_OPENED", "OnEvent")
		self:RegisterEvent("BANKFRAME_CLOSED", "OnEvent")

		-- Even though technically all data is available at this point,
		-- information like the size of each container isn't available
		-- until those containers get their BAG_UPDATE event.
		-- This is most likely due to the UI resetting its
		-- internal cache sometimes between these events.
		self:RegisterEvent("BAG_UPDATE", "OnEvent")

		-- Do an initial parsing of the bags.
		-- The results might be lacking because of the above.
		self:ParseMultipleBlizzardContainers(unpack(bagIDs))

		-- Fire off some semi-fake events.
		-- The idea is to have the front-end only rely on custom messages, 
		-- so we need these here instead of the Blizzard events.
		for _,bagID in ipairs(bagIDs) do
			self:SendMessage("GP_BAG_UPDATE", bagID)
		end

		local stillWaiting
		if (QueuedContainerIDs) then
			-- Check if anything is still queued
			for bagID in pairs(QueuedContainerIDs) do
				for slotID, itemID in pairs(QueuedContainerIDs[bagID]) do
					-- If anything is found, break here
					stillWaiting = true 
				end
			end
		end
		if (not stillWaiting) then
			-- Fire a custom event to indicate the queue has been parsed
			-- and all delayed item information has been received.
			self:SendMessage("GP_BAGS_READY")
		end

	end
end

LibBagButton.Start = function(self)

	-- Hook the blizzard bag toggling.
	-- It is preferable to get this done as early as possible.
	self:HookBlizzardBagFunctions()

	-- Always kill off all events here.
	self:UnregisterAllEvents()

	-- Could be a library upgrade, or forced restart.
	if (IsLoggedIn()) then
		-- If we restarted the engine after login, 
		-- we need to manually trigger this event as though
		-- it was the initial login, to enable event tracking.
		self:OnEvent("PLAYER_ENTERING_WORLD", true)
	else
		-- Delay all event parsing until we enter the world.
		self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEvent")
	end

	local tooltip = self:GetBagButtonTooltip()
	tooltip:SetCValue("backdrop", {
		bgFile = [[Interface\Tooltips\UI-Tooltip-Background]],
		edgeFile = [[Interface\Tooltips\UI-Tooltip-Border]], 
		edgeSize = 16,
		insets = {
			left = 3.5,
			right = 3.5,
			top = 3.5,
			bottom = 3.5
		}
	})
	tooltip:SetCValue("backdropColor", { 0, 0, 0, .95 })
	tooltip:SetCValue("backdropBorderColor", { .25, .25, .25, 1 })
	tooltip:SetCValue("backdropOffsets", { 10, 10, 10, 10 })

end

-- Library Public API
-- *The 'self' is the module embedding it here.
-----------------------------------------------------------------
LibBagButton.SpawnItemContainer = function(self, ...)
	local bagType = ...

	check(bagType, 1, "string")

	if (bagType ~= "Bag") and (bagType ~= "Bank") then
		return error(string_format("No bagType named '%d' exists!", bagType))
	end

	local frame = setmetatable(self:CreateFrame("Frame", nil, "UICenter"), Container_MT)
	frame:SetFrameStrata("HIGH")
	frame:EnableMouse(true)
	frame:Hide()

	Containers[frame] = bagType

	return frame
end

local hidden = CreateFrame("Frame")
hidden:Hide()

-- @input bagType <integer,string> bagID or bagType
-- @return <frame> the button
LibBagButton.SpawnItemButton = function(self, ...)
	local bagType, bagID, slotID

	local numArgs = select("#", ...)
	if (numArgs == 1) then
		bagType = ...
		check(bagType, 1, "string")

	elseif (numArgs == 2) then
		bagID, slotID = ...
		check(bagID, 1, "number")
		check(slotID, 2, "number")
		bagType = BagTypesFromID[bagID]

		-- An illegal bagType has been requested.
		if (not bagType) then
			return error(string_format("No bagType for the bagID '%d' exists!", bagID))
		end
	end

	-- An unknown bagType was requested.
	if (not Buttons[bagType]) then
		return error(string_format("No bagType named '%d' exists!", bagID))
	end

	local button -- virtual button object returned to the user.
	local parent -- hidden button slot parent for bag items, basically a fake bag container.
	local slot -- slot object that contains the "actual" button with functional blizz scripts and methods.

	-- Our virtual object. We don't want the front-end to directly
	-- interact with any of the actual objects created below.
	--button = setmetatable(self:CreateFrame(BUTTON_TYPE), Button_MT)
	button = setmetatable(self:CreateFrame("Frame"), Button_MT)
	button:EnableMouse(false)
	button.bagType = bagType
	button.bagID = bagID
	button.slotID = slotID

	-- This is basically a bag for all intents and purposes, 
	-- except that it totally isn't that at all. 
	-- We just need a parent for the slot with and ID for the template to work.
	parent = button:CreateFrame("Frame")
	--parent:SetAllPoints()
	parent:EnableMouse(false)
	parent:SetID(bagID or 100)

	-- Need to clear away blizzard layers from this one, 
	-- as they interfere with anything we do.
	slot = parent:CreateFrame(BUTTON_TYPE, nil, ButtonTemplates[bagType])
	slot:SetAllPoints(button) -- bypass the parent/fakebag object
	slot:SetPoint("CENTER", button, "CENTER", 0, 0)
	slot:EnableMouse(true)

	-- BlizzKill
	slot.UpdateTooltip = nil
	slot:DisableDrawLayer("BACKDROP")
	slot:DisableDrawLayer("BORDER")
	slot:DisableDrawLayer("ARTWORK")
	slot:DisableDrawLayer("OVERLAY")
	slot:GetNormalTexture():SetParent(hidden)
	slot:GetPushedTexture():SetParent(hidden)
	slot:GetHighlightTexture():SetParent(hidden)

	slot:SetID(slotID or 0)
	slot:Show() -- do this before we add the scripthandlers below!

	-- Set Scripts
	-- Let these be proxies
	slot:SetScript("OnEnter", function(slot) button:OnEnter() end)
	slot:SetScript("OnLeave", function(slot) button:OnLeave() end)
	slot:SetScript("OnHide", function(slot) button:OnHide() end)
	slot:SetScript("OnShow", function(slot) button:OnShow() end)
	slot:SetScript("OnEvent", function(slot) button:OnEvent() end)

	-- Cache up our elements 
	ButtonParents[button] = parent
	ButtonSlots[button] = slot

	-- Insert the virtual button slot object into the correct cache.
	table_insert(Buttons[bagType], button) 

	-- Create button layers.
	local icon = button:CreateTexture()
	icon:SetDrawLayer("BACKGROUND", 0)
	icon:SetAllPoints()
	icon:SetTexCoord(5/64, 59/64, 5/64, 59/64)
	button.Icon = icon

	--[[-- 

		frame
			backdrop
			icon

		cooldownframe
			cooldown

		borderframe
			border
			stack

		overlayframe
			itemlevel
			questtexture

	--]]--

	-- Return the button slot object to the user
	return button
end

-- Returns the free,total space in a specific container.
-- *Will return 0,0 if no information is yet available.
LibBagButton.GetFreeBagSpaceInBag = function(self, bagID)
	local cache = Contents[bagID]
	if (not cache) then
		return 0,0
	end
	return cache.freeSlots or 0, cache.totalSlots or 0
end

-- Returns the free bag space.
-- @input <number> query a certain bagType only. 
-- @return <number,number> currentFree, totalFree 
LibBagButton.GetFreeBagSpace = function(self, bagType)
	local freeSlots, totalSlots = 0, 0
	if (not bagType) then 
		bagType = 0 -- 0 means regular non-profession containers
	end
	if (not LibBagButton.freeSlots) then
		LibBagButton.freeSlots = {}
	end
	if (not LibBagButton.totalSlots) then
		LibBagButton.totalSlots = {}
	end
	if (LibBagButton.parsingRequired) or (not LibBagButton.freeSlots[bagType]) or (not LibBagButton.totalSlots[bagType]) then
		for i,bagID in pairs(bagIDs) do
			if (BagTypesFromID[bagID] == "Bag") then
				local cache = Contents[bagID]
				if (cache) and (cache.bagType == bagType) then 
					totalSlots = totalSlots + cache.totalSlots
					freeSlots = freeSlots + cache.freeSlots
				end
			end
			LibBagButton.freeSlots[bagType] = freeSlots
			LibBagButton.totalSlots[bagType] = totalSlots
		end
		LibBagButton.parsingRequired = nil
	end
	return LibBagButton.freeSlots[bagType] or 0, LibBagButton.totalSlots[bagType] or 0	
end

-- Returns the free bank space.
-- *Will returned a cached value if not currently at the bank,
-- @input <number> query a certain bagType only. 
-- @return <number,number> currentFree, totalFree 
LibBagButton.GetFreeBankSpace = function(self, bagType)
	local freeSlots, totalSlots = 0, 0
	if (not bagType) then 
		bagType = 0 -- 0 means regular non-profession containers
	end
	if (not LibBagButton.freeBankSlots) then
		LibBagButton.freeBankSlots = {}
	end
	if (not LibBagButton.totalBankSlots) then
		LibBagButton.totalBankSlots = {}
	end
	if (LibBagButton:IsAtBank()) then
		for i,bagID in pairs(bankIDs) do
			if (BagTypesFromID[bagID] == "Bank") then
				local cache = Contents[bagID]
				if (cache) and (cache.bagType == bagType) then 
					totalSlots = totalSlots + cache.totalSlots
					freeSlots = freeSlots + cache.freeSlots
				end
			end
		end
		LibBagButton.freeBankSlots[bagType] = freeSlots
		LibBagButton.totalBankSlots[bagType] = totalSlots
	end
	return LibBagButton.freeBankSlots[bagType] or 0, LibBagButton.totalBankSlots[bagType] or 0
end

LibBagButton.GetIteratorForBagIDs = function(self)
	local new = {}
	for i,bagID in pairs(bagIDs) do
		if (BagTypesFromID[bagID] == "Bag") then
			new[#new + 1] = bagID
		end
	end
	table_sort(new, sortAscending)
	return ipairs(new)
end

LibBagButton.GetIteratorForBagIDsReversed = function(self)
	local new = {}
	for i,bagID in pairs(bagIDs) do
		if (BagTypesFromID[bagID] == "Bag") then
			new[#new + 1] = bagID
		end
	end
	table_sort(new, sortDescending)
	return ipairs(new)
end

LibBagButton.GetIteratorForBankIDs = function(self)
	local new = {}
	for i,bagID in pairs(bankIDs) do
		if (BagTypesFromID[bagID] == "Bank") then
			new[#new + 1] = bagID
		end
	end
	return ipairs(new)
end

LibBagButton.GetIteratorForReagentBankIDs = function(self)
	local new = {}
	return ipairs(new)
end


-- Returns true if we're at the bank.
LibBagButton.IsAtBank = function(self)
	return LibBagButton.atBank
end

-- Module embedding
local embedMethods = {
	GetIteratorForBagIDs = true,
	GetIteratorForBagIDsReversed = true,
	GetIteratorForBankIDs = true,
	GetIteratorForReagentBankIDs = true,
	GetFreeBagSpace = true,
	GetFreeBagSpaceInBag = true, 
	GetFreeBankSpace = true,
	IsAtBank = true,
	SpawnItemContainer = true,
	SpawnItemButton = true
}

LibBagButton.Embed = function(self, target)
	for method in pairs(embedMethods) do
		target[method] = self[method]
	end
	self.embeds[target] = true
	return target
end

-- Upgrade existing embeds, if any
for target in pairs(LibBagButton.embeds) do
	LibBagButton:Embed(target)
end

-- Always needed, for library upgrades too!
LibBagButton:Start()