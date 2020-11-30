local ADDON, Private = ...
local Core = Wheel("LibModule"):GetModule(ADDON)
if (not Core) then 
	return 
end

local Module = Core:NewModule("BlizzardTooltips", "LibEvent", "LibDB", "LibFrame", "LibTooltip", "LibTooltipScanner", "LibPlayerData", "LibClientBuild")

-- Lua API
local _G = _G
local math_floor = math.floor
local math_max = math.max
local math_mod = math.fmod
local string_find = string.find
local string_format = string.format
local string_split = string.split
local table_concat = table.concat
local table_wipe = table.wipe
local tonumber = tonumber
local type = type
local unpack = unpack

-- WoW API
local GetItemInfo = GetItemInfo
local GetMouseFocus = GetMouseFocus
local GetQuestGreenRange = GetQuestGreenRange
local GetScalingQuestGreenRange = GetScalingQuestGreenRange
local UnitCanAttack = UnitCanAttack
local UnitClass = UnitClass
local UnitEffectiveLevel = UnitEffectiveLevel
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsPlayer = UnitIsPlayer
local UnitIsTapDenied = UnitIsTapDenied
local UnitIsUnit = UnitIsUnit
local UnitLevel = UnitLevel
local UnitPlayerControlled = UnitPlayerControlled
local UnitQuestTrivialLevelRange = UnitQuestTrivialLevelRange or GetQuestGreenRange
local UnitQuestTrivialLevelRangeScaling = UnitQuestTrivialLevelRangeScaling or GetScalingQuestGreenRange
local UnitReaction = UnitReaction

-- Private API
local Colors = Private.Colors
local GetFont = Private.GetFont
local GetLayout = Private.GetLayout
local GetMedia = Private.GetMedia

-- Constants for client version
local IsClassic = Module:IsClassic()
local IsRetail = Module:IsRetail()

-- Blizzard textures we use 
local BLANK = "|T"..GetMedia("blank")..":14:14:-2:1|t" -- 1:1
local BOSS_TEXTURE = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:14:14:-2:1|t" -- 1:1
local FFA_TEXTURE = "|TInterface\\TargetingFrame\\UI-PVP-FFA:14:10:-2:1:64:64:6:34:0:40|t" -- 4:3
local FACTION_ALLIANCE_TEXTURE = "|TInterface\\TargetingFrame\\UI-PVP-Alliance:14:10:-2:1:64:64:6:34:0:40|t" -- 4:3
local FACTION_NEUTRAL_TEXTURE = "|TInterface\\TargetingFrame\\UI-PVP-Neutral:14:10:-2:1:64:64:6:34:0:40|t" -- 4:3
local FACTION_HORDE_TEXTURE = "|TInterface\\TargetingFrame\\UI-PVP-Horde:14:14:-4:0:64:64:0:40:0:40|t" -- 1:1

-- Method template
local meta = getmetatable(CreateFrame("GameTooltip", nil, WorldFrame, "GameTooltipTemplate")).__index

-- Lockdowns
local LOCKDOWNS = {}

-- Flag set to true if any other known
-- addon with vendor sell prices is enabled.
local DISABLE_VENDOR_PRICES = IsRetail -- disable for retail for now
if (not DISABLE_VENDOR_PRICES) then
	DISABLE_VENDOR_PRICES = (function(...)
		for i = 1,select("#", ...) do
			if Module:IsAddOnEnabled((select(i, ...))) then 
				return true
			end
		end
	end)("Auctionator") -- "TradeSkillMaster"
end

-- Make the money display pretty
local formatMoney = function(money)
	local gold = math_floor(money / (100 * 100))
	local silver = math_floor((money - (gold * 100 * 100)) / 100)
	local copper = math_mod(money, 100)
	
	local goldIcon = string_format([[|T%s:16:16:-2:0:64:64:%d:%d:%d:%d|t]], GetMedia("coins"), 0,32,0,32)
	local silverIcon = string_format([[|T%s:16:16:-2:0:64:64:%d:%d:%d:%d|t]], GetMedia("coins"), 32,64,0,32)
	local copperIcon = string_format([[|T%s:16:16:-2:0:64:64:%d:%d:%d:%d|t]], GetMedia("coins"), 0,32,32,64)

	local moneyString
	if (gold > 0) then 
		moneyString = string_format("%d%s", gold, goldIcon)
	end
	if (silver > 0) then 
		moneyString = (moneyString and moneyString.." " or "") .. string_format("%d%s", silver, silverIcon)
	end
	if (copper > 0) then 
		moneyString = (moneyString and moneyString.." " or "") .. string_format("%d%s", copper, copperIcon)
	end 

	return moneyString
end

local hooks = {}
local align
align = function(self)
	-- Check points to avoid indents
	local pointID = 1
	local point,anchor,rpoint,x,y = self:GetPoint(pointID)
	while (point) do
		if (point == "LEFT") and (rpoint == "LEFT") and (x < 9 or x > 11) then
			-- 10 is the tooltip default for only text,
			-- ~28 is the default when textures are visible
			self:SetPoint(point,anchor,rpoint,10,y)
		end
		pointID = pointID + 1
		point,anchor,rpoint,x,y = self:GetPoint(pointID)
	end
	-- Attempt to fix the fucked up width and alignment in 9.0.1.
	local tooltip = self:GetParent()
	local tooltipName = tooltip:GetName()
	local maxWidth = 0
	for i = tooltip:NumLines(), 1, -1 do
		local line = _G[tooltipName.."TextLeft"..i]
		if (line) then
			--line:SetIndentedWordWrap(false)
			--line:SetWordWrap(true)
			local msg = line:GetText()
			if (msg and msg ~= "") then
				local parentWidth = tooltip:GetWidth()
				local width = line:GetUnboundedStringWidth()
				if (width < 280) then
					maxWidth = math_max(width, maxWidth)
				end
			end
		end
	end
	-- Tooltips are something like 460px (relative to a 1920px width) wide by default in 9.0.2, 
	-- which is just waaaay too much. Tons of empty space to the right, and it makes no sense.
	-- We are limiting this.
	if (maxWidth > 280) then
		--tooltip:SetMinimumWidth(maxWidth + 20)
		tooltip:SetMinimumWidth(280)
		tooltip:SetWidth(420)
	else
		tooltip:SetMinimumWidth(0)
	end
	tooltip:Show()
end

-- Add or replace a line of text in the tooltip
local AddIndexedLine = function(tooltip, lineIndex, msg, r, g, b)
	r = r or Colors.offwhite[1]
	g = g or Colors.offwhite[2]
	b = b or Colors.offwhite[3]
	local line
	local numLines = tooltip:NumLines()
	if (lineIndex > numLines) then 
		meta.AddLine(tooltip, msg, r, g, b)
		line = _G[tooltip:GetName().."TextLeft"..(numLines + 1)]
	else
		line = _G[tooltip:GetName().."TextLeft"..lineIndex]
		line:SetText(msg)
		if (r and g and b) then 
			line:SetTextColor(r, g, b)
		end
	end
	align(line)
	return lineIndex + 1
end

-- Returns the correct difficulty color compared to the player.
-- Using this as a tooltip method to access our custom colors.
-- *Sourced from /back-end/tooltip.lua
local GetDifficultyColorByLevel
if (IsClassic) then
	GetDifficultyColorByLevel = function(level, isScaling)
		local colors = Colors.quest
		local levelDiff = level - UnitLevel("player")
		if (isScaling) then
			if (levelDiff > 5) then
				return colors.red[1], colors.red[2], colors.red[3], colors.red.colorCode
			elseif (levelDiff > 3) then
				return colors.orange[1], colors.orange[2], colors.orange[3], colors.orange.colorCode
			elseif (levelDiff >= 0) then
				return colors.yellow[1], colors.yellow[2], colors.yellow[3], colors.yellow.colorCode
			elseif (-levelDiff <= GetScalingQuestGreenRange()) then
				return colors.green[1], colors.green[2], colors.green[3], colors.green.colorCode
			else
				return colors.gray[1], colors.gray[2], colors.gray[3], colors.gray.colorCode
			end
		else
			if (levelDiff > 5) then
				return colors.red[1], colors.red[2], colors.red[3], colors.red.colorCode
			elseif (levelDiff > 3) then
				return colors.orange[1], colors.orange[2], colors.orange[3], colors.orange.colorCode
			elseif (levelDiff >= -2) then
				return colors.yellow[1], colors.yellow[2], colors.yellow[3], colors.yellow.colorCode
			elseif (-levelDiff <= GetQuestGreenRange()) then
				return colors.green[1], colors.green[2], colors.green[3], colors.green.colorCode
			else
				return colors.gray[1], colors.gray[2], colors.gray[3], colors.gray.colorCode
			end
		end
	end
elseif (IsRetail) then
	GetDifficultyColorByLevel = function(level, isScaling)
		local colors = Colors.quest
		if (isScaling) then
			local levelDiff = level - UnitEffectiveLevel("player")
			if (levelDiff > 5) then
				return colors.red[1], colors.red[2], colors.red[3], colors.red.colorCode
			elseif (levelDiff > 3) then
				return colors.orange[1], colors.orange[2], colors.orange[3], colors.orange.colorCode
			elseif (levelDiff >= 0) then
				return colors.yellow[1], colors.yellow[2], colors.yellow[3], colors.yellow.colorCode
			elseif (-levelDiff <= -UnitQuestTrivialLevelRangeScaling("player")) then
				return colors.green[1], colors.green[2], colors.green[3], colors.green.colorCode
			else
				return colors.gray[1], colors.gray[2], colors.gray[3], colors.gray.colorCode
			end
		else
			local levelDiff = level - UnitLevel("player")
			if (levelDiff > 5) then
				return colors.red[1], colors.red[2], colors.red[3], colors.red.colorCode
			elseif (levelDiff > 3) then
				return colors.orange[1], colors.orange[2], colors.orange[3], colors.orange.colorCode
			elseif (levelDiff >= -4) then
				return colors.yellow[1], colors.yellow[2], colors.yellow[3], colors.yellow.colorCode
			elseif (-levelDiff <= -UnitQuestTrivialLevelRange("player")) then
				return colors.green[1], colors.green[2], colors.green[3], colors.green.colorCode
			else
				return colors.gray[1], colors.gray[2], colors.gray[3], colors.gray.colorCode
			end
		end
	end
end

-- Update the color of the tooltip's current unit
-- Returns the r, g, b value
local GetUnitHealthColor = function(unit, data)
	local r, g, b
	if data then 
		if (data.isPet and data.petRarity) then 
			r, g, b = unpack(Colors.quality[data.petRarity - 1])
		else
			if ((not UnitPlayerControlled(unit)) and UnitIsTapDenied(unit) and UnitCanAttack("player", unit)) then
				r, g, b = unpack(Colors.tapped)
			elseif (not UnitIsConnected(unit)) then
				r, g, b = unpack(Colors.disconnected)
			elseif (UnitIsDeadOrGhost(unit)) then
				r, g, b = unpack(Colors.dead)
			elseif (UnitIsPlayer(unit)) then
				local _, class = UnitClass(unit)
				if class then 
					r, g, b = unpack(Colors.class[class])
				else 
					r, g, b = unpack(Colors.disconnected)
				end 
			elseif (UnitReaction(unit, "player")) then
				r, g, b = unpack(Colors.reaction[UnitReaction(unit, "player")])
			else
				r, g, b = 1, 1, 1
			end
		end 
	else 
		if ((not UnitPlayerControlled(unit)) and UnitIsTapDenied(unit) and UnitCanAttack("player", unit)) then
			r, g, b = unpack(Colors.tapped)
		elseif (not UnitIsConnected(unit)) then
			r, g, b = unpack(Colors.disconnected)
		elseif (UnitIsDeadOrGhost(unit)) then
			r, g, b = unpack(Colors.dead)
		elseif (UnitIsPlayer(unit)) then
			local _, class = UnitClass(unit)
			if class then 
				r, g, b = unpack(Colors.class[class])
			else 
				r, g, b = unpack(Colors.disconnected)
			end 
		elseif (UnitReaction(unit, "player")) then
			r, g, b = unpack(Colors.reaction[UnitReaction(unit, "player")])
		else
			r, g, b = 1, 1, 1
		end
	end 
	return r,g,b
end 

local GetTooltipUnit = function(tooltip)
	local _, unit = tooltip:GetUnit()
	if (not unit) and UnitExists("mouseover") then
		unit = "mouseover"
	end
	if (unit) and UnitIsUnit(unit, "mouseover") then
		unit = "mouseover"
	end
	return UnitExists(unit) and unit
end

-- Bar post updates
-- Show health values for tooltip health bars, and hide others.
-- Will expand on this later to tailer all tooltips to our needs.  
local StatusBar_UpdateValue = function(bar, value, max)

	local isRealValue = (max ~= 100)
	if (value) then 
		if (isRealValue) then 
			if (value >= 1e8) then 			bar.value:SetFormattedText("%.0fm", value/1e6) 		-- 100m, 1000m, 2300m, etc
			elseif (value >= 1e6) then 		bar.value:SetFormattedText("%.1fm", value/1e6) 		-- 1.0m - 99.9m 
			elseif (value >= 1e5) then 		bar.value:SetFormattedText("%.0fk", value/1e3) 		-- 100k - 999k
			elseif (value >= 1e3) then 		bar.value:SetFormattedText("%.1fk", value/1e3) 		-- 1.0k - 99.9k
			elseif (value > 0) then 		bar.value:SetText(tostring(math_floor(value))) 		-- 1 - 999
			else 							bar.value:SetText(DEAD)
			end 
		else 
			if (value > 0) then 
				bar.value:SetFormattedText("%.0f%%", value)
			else 
				bar.value:SetText("")
			end
		end 
		if (not bar.value:IsShown()) then 
			bar.value:Show()
		end
	else 
		if (bar.value:IsShown()) then 
			bar.value:Hide()
			bar.value:SetText("")
		end
	end 
end 

-- zhCN exceptions
local gameLocale = GetLocale()
if (gameLocale == "zhCN") then 
	StatusBar_UpdateValue = function(bar, value, max)
		local isRealValue = (max ~= 100)
		if (value) then 
			if (isRealValue) then 
				if (value >= 1e8) then 			bar.value:SetFormattedText("%.1f亿", value/1e8)
				elseif (value >= 1e4) then 		bar.value:SetFormattedText("%.1f万", value/1e4)
				elseif (value > 0) then 		bar.value:SetText(tostring(math_floor(value)))
				else 							bar.value:SetText(DEAD)
				end 
			else 
				if (value > 0) then 
					bar.value:SetFormattedText("%.0f%%", value)
				else 
					bar.value:SetText("")
				end
			end 
			if (not bar.value:IsShown()) then 
				bar.value:Show()
			end
		else 
			if (bar.value:IsShown()) then 
				bar.value:Hide()
				bar.value:SetText("")
			end
		end 
	end
end

local StatusBar_OnValueChanged = function(statusbar)
	local value = statusbar:GetValue()
	local min, max = statusbar:GetMinMaxValues()
	
	-- Hide the bar if values are missing, or if max or min is 0. 
	if (not min) or (not max) or (not value) or (max == 0) or (value == min) then
		statusbar:Hide()
		return
	end
	
	-- Just in case somebody messed up, 
	-- we silently correct out of range values.
	if value > max then
		value = max
	elseif value < min then
		value = min
	end
	
	if statusbar.value then
		StatusBar_UpdateValue(statusbar, value, max)
	end

	-- Because blizzard shrink the textures instead of cropping them.
	statusbar:GetStatusBarTexture():SetTexCoord(0, (value-min)/(max-min), 0, 1)

	-- Add the green if no other color was detected. Like objects that aren't units, but still have health. 
	if (not statusbar.color) or (not statusbar:GetParent().unit) then
		statusbar.color = Colors.quest.green
	end

	-- The color needs to be updated, or it will pop back to green
	statusbar:SetStatusBarColor(unpack(statusbar.color))
end

local StatusBar_OnShow = function(statusbar)
	if (not statusbar._owner) or (not GetTooltipUnit(statusbar._owner)) then 
		statusbar:Hide()
		return
	end
	Module:SetBlizzardTooltipBackdropOffsets(statusbar._owner, 10, 10, 10, 18)
	StatusBar_OnValueChanged(statusbar)
end

-- Do a color and texture reset upon hiding, to make sure it looks right when next shown. 
local StatusBar_OnHide = function(statusbar)
	statusbar.color = Colors.quest.green
	statusbar:GetStatusBarTexture():SetTexCoord(0, 1, 0, 1)
	statusbar:SetStatusBarColor(unpack(statusbar.color))
	Module:SetBlizzardTooltipBackdropOffsets(statusbar._owner, 10, 10, 10, 12)
end

-- General scale and font object corrections on tooltip show. 
local OnTooltipShow = function(tooltip)
	if (tooltip:IsForbidden()) then 
		return
	end

	-- Set the tooltip to the same scale as our own. 
	local targetScale = Module:GetFrame("UICenter"):GetEffectiveScale()
	local tooltipParentScale = (tooltip:GetParent() or WorldFrame):GetEffectiveScale()
	tooltip:SetScale(targetScale/tooltipParentScale)

	-- Change the original font object and use inheritance, 
	-- as changing line by line produced weird alignments.
	local headerFontObject = GetFont(15,true)
	if (GameTooltipHeader:GetFontObject() ~= headerFontObject) then 
		GameTooltipHeader:SetFontObject(headerFontObject)
	end

	-- Some texts inherit from this, like the "!Quest Available" texts
	-- in the follower selection frame in Nazjatar. Outline doesn't work there!
	local lineFontObject = GetFont(13,true)
	if (GameTooltipText:GetFontObject() ~= lineFontObject) then 
		GameTooltipText:SetFontObject(lineFontObject)
	end

end

local OnTooltipHide = function(tooltip)
	tooltip.unit = nil
	tooltip.vendorSellLineID = nil
	LOCKDOWNS[tooltip] = nil
	if (tooltip:IsForbidden()) then 
		return
	end
end

local OnTooltipAddLine = function(tooltip, msg)
	if (tooltip:IsForbidden()) then 
		return
	end
	if not(LOCKDOWNS[tooltip]) then
		return OnTooltipShow(tooltip)
	end 
	for i = 2, tooltip:NumLines() do
		local line = _G[tooltip:GetName().."TextLeft"..i]
		if line then
			align(line)
			local text = line:GetText()
			-- We found the new line
			if (text == msg) then
				line:SetText("")
				return
			end 
		end
	end
end

local OnTooltipAddDoubleLine = function(tooltip, leftText, rightText)
	if (tooltip:IsForbidden()) then 
		return
	end
	if not(LOCKDOWNS[tooltip]) then
		return OnTooltipShow(tooltip)
	end 
	for i = 2, tooltip:NumLines() do
		local left = _G[tooltip:GetName().."TextLeft"..i]
		local right = _G[tooltip:GetName().."TextRight"..i]
		if (left) then
			local leftMsg = left:GetText()
			local rightMsg = right:GetText()
			if (leftMsg == leftText) or (rightMsg == rightText) then
				align(left)
				left:SetText("")
				right:SetText("")
				return
			end 
		end
	end
end

local OnTooltipSetItem = function(tooltip)
	if (tooltip:IsForbidden()) then 
		return
	end
	local frame = GetMouseFocus()
	if (frame and frame.GetName and not frame:IsForbidden()) then
		local name = frame:GetName()
		local _,link = tooltip:GetItem()

		local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
			itemEquipLoc, itemIcon, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID,
			isCraftingReagent

		-- Recolor items with our own item colors
		if (link) then
			itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
			itemEquipLoc, itemIcon, itemSellPrice, itemClassID, itemSubClassID, bindType, expacID, itemSetID,
			isCraftingReagent = GetItemInfo(link)
			if (itemName) and (itemRarity) then
				local line = _G[tooltip:GetName().."TextLeft1"]
				if (line) then
					local color = Colors.quality[itemRarity]
					line:SetTextColor(color[1], color[2], color[3])
				end
			end
		end

		if (DISABLE_VENDOR_PRICES) then 
			return 
		end
	
		if (not MerchantFrame:IsShown()) or (name and (string_find(name, "Character") or string_find(name, "TradeSkill"))) then
			local _,link = tooltip:GetItem()
			if (link) then
				if (itemSellPrice and (itemSellPrice > 0)) then
					LOCKDOWNS[tooltip] = nil

					local itemCount = frame.count and tonumber(frame.count) or (frame.Count and frame.Count.GetText) and tonumber(frame.Count:GetText())
					local label = string_format("%s:", SELL_PRICE)
					local price = formatMoney((itemCount or 1) * itemSellPrice)
					local color = Colors.offwhite

					if (tooltip.vendorSellLineID) then 
						_G[tooltip:GetName().."TextLeft"..tooltip.vendorSellLineID]:SetText("")
						_G[tooltip:GetName().."TextLeft"..(tooltip.vendorSellLineID+1)]:SetText("")
						_G[tooltip:GetName().."TextRight"..(tooltip.vendorSellLineID+1)]:SetText("")
					end

					tooltip.vendorSellLineID = tooltip:NumLines() + 1
					meta.AddLine(tooltip, BLANK)
					meta.AddDoubleLine(tooltip, label, price, color[1], color[2], color[3], color[1], color[2], color[3])

					-- Not doing this yet. But we will. Oh yes we will. 
					--LOCKDOWNS[tooltip] = true
				end
			end
		end
	end
end

local OnTooltipSetUnit = function(tooltip)
	if (tooltip:IsForbidden()) then 
		return
	end

	local unit = GetTooltipUnit(tooltip)
	if (not unit) then
		tooltip:Hide()
		OnTooltipHide(tooltip)
		return
	end

	local data = Module:GetTooltipDataForUnit(unit)
	if (not data) then
		tooltip:Hide()
		OnTooltipHide(tooltip)
		return
	end

	LOCKDOWNS[tooltip] = nil
	
	tooltip.unit = unit

	-- Kill off texts
	local tooltipName = tooltip:GetName()
	local numLines = tooltip:NumLines()
	local lineIndex = 1
	for i = numLines,1,-1 do 
		local left = _G[tooltipName.."TextLeft"..i]
		local right = _G[tooltipName.."TextRight"..i]
		if (left) then
			align(left)
			left:SetText("")
		end
		if (right) then
			right:SetText("")
		end
	end

	-- Kill off textures
	local textureID = 1
	local texture = _G[tooltipName .. "Texture" .. textureID]
	while (texture) and (texture:IsShown()) do
		texture:SetTexture("")
		texture:Hide()
		textureID = textureID + 1
		texture = _G[tooltipName .. "Texture" .. textureID]
	end

	-- name 
	local displayName = data.name
	if (data.isPlayer) then 
		if (data.showPvPFactionWithName) then 
			if (data.isFFA) then
				displayName = FFA_TEXTURE .. " " .. displayName
			elseif (data.isPVP and data.englishFaction) then
				if (data.englishFaction == "Horde") then
					displayName = FACTION_HORDE_TEXTURE .. " " .. displayName
				elseif (data.englishFaction == "Alliance") then
					displayName = FACTION_ALLIANCE_TEXTURE .. " " .. displayName
				elseif (data.englishFaction == "Neutral") then
					-- They changed this to their new atlas garbage in Legion, 
					-- so for the sake of simplicty we'll just use the FFA PvP icon instead. Works.
					displayName = FFA_TEXTURE .. " " .. displayName
				end
			end
		end
		if (data.pvpRankName) then
			displayName = displayName .. Colors.quest.gray.colorCode.. " (" .. data.pvpRankName .. ")|r"
		end

	else 
		if (data.isBoss) then
			displayName = BOSS_TEXTURE .. " " .. displayName
		elseif (data.classification == "rare") or (data.classification == "rareelite") then
			displayName = displayName .. Colors.quality[3].colorCode .. " (" .. ITEM_QUALITY3_DESC .. ")|r"
		elseif (data.classification == "elite") then 
			displayName = displayName .. Colors.title.colorCode .. " (" .. ELITE .. ")|r"
		end
	end

	local levelText
	if (data.effectiveLevel and (data.effectiveLevel > 0)) then 
		local r, g, b, colorCode = GetDifficultyColorByLevel(data.effectiveLevel)
		levelText = colorCode .. data.effectiveLevel .. "|r"
	end 

	local r, g, b = GetUnitHealthColor(unit,data)
	if (levelText) then 
		lineIndex = AddIndexedLine(tooltip, lineIndex, levelText .. Colors.quest.gray.colorCode .. ": |r" .. displayName, r, g, b)
	else
		lineIndex = AddIndexedLine(tooltip, lineIndex, displayName, r, g, b)
	end 

	-- Players
	if (data.isPlayer) then 
		if (data.isDead) then 
			lineIndex = AddIndexedLine(tooltip, lineIndex, data.isGhost and DEAD or CORPSE, Colors.offwhite[1], Colors.offwhite[2], Colors.offwhite[3])
		else 
			if (data.guild) then 
				lineIndex = AddIndexedLine(tooltip, lineIndex, "<"..data.guild..">", Colors.title[1], Colors.title[2], Colors.title[3])
			end 

			local levelLine

			if (data.raceDisplayName) then 
				levelLine = (levelLine and levelLine.." " or "") .. data.raceDisplayName
			end 

			if (data.classDisplayName and data.class) then 
				levelLine = (levelLine and levelLine.." " or "") .. data.classDisplayName
			end 

			if (levelLine) then 
				lineIndex = AddIndexedLine(tooltip, lineIndex, levelLine, Colors.offwhite[1], Colors.offwhite[2], Colors.offwhite[3])
			end 

			-- player faction (Horde/Alliance/Neutral)
			if (data.localizedFaction) then 
				lineIndex = AddIndexedLine(tooltip, lineIndex, data.localizedFaction)
			end 
		end

	-- All other NPCs
	else 
		if (data.isDead) then 
			lineIndex = AddIndexedLine(tooltip, lineIndex, data.isGhost and DEAD or CORPSE, Colors.offwhite[1], Colors.offwhite[2], Colors.offwhite[3])
			if (data.isSkinnable) then 
				lineIndex = AddIndexedLine(tooltip, lineIndex, data.skinnableMsg, data.skinnableColor[1], data.skinnableColor[2], data.skinnableColor[3])
			end
		else 
			-- titles
			if (data.title) then 
				lineIndex = AddIndexedLine(tooltip, lineIndex, "<"..data.title..">", Colors.normal[1], Colors.normal[2], Colors.normal[3])
			end 

			if (data.city) then 
				lineIndex = AddIndexedLine(tooltip, lineIndex, data.city, Colors.title[1], Colors.title[2], Colors.title[3])
			end 

			-- Beast etc 
			if (data.creatureFamily) then 
				lineIndex = AddIndexedLine(tooltip, lineIndex, data.creatureFamily, Colors.offwhite[1], Colors.offwhite[2], Colors.offwhite[3])

			-- Humanoid, Crab, etc 
			elseif (data.creatureType) then 
				lineIndex = AddIndexedLine(tooltip, lineIndex, data.creatureType, Colors.offwhite[1], Colors.offwhite[2], Colors.offwhite[3])
			end 

			-- Player faction (Horde/Alliance/Neutral)
			if (data.localizedFaction) then 
				lineIndex = AddIndexedLine(tooltip, lineIndex, data.localizedFaction)
			end 

			-- Definitely important in classic!
			if (data.isCivilian) then 
				lineIndex = AddIndexedLine(tooltip, lineIndex, PVP_RANK_CIVILIAN, data.civilianColor[1], data.civilianColor[2], data.civilianColor[3])
			end
		end

		-- Add quest objectives
		if (data.objectives) then
			for objectiveID, objectiveData in ipairs(data.objectives) do
				lineIndex = AddIndexedLine(tooltip, lineIndex, BLANK) -- this ends up at the end(..?)
				lineIndex = AddIndexedLine(tooltip, lineIndex, objectiveData.questTitle, Colors.title[1], Colors.title[2], Colors.title[3])

				for objectiveID, questObjectiveData in ipairs(objectiveData.questObjectives) do
					local objectiveType = questObjectiveData.objectiveType
					if (objectiveType == "incomplete") then
						lineIndex = AddIndexedLine(tooltip, lineIndex, questObjectiveData.objectiveText, Colors.quest.gray[1], Colors.quest.gray[2], Colors.quest.gray[3])
					elseif (objectiveType == "complete") then
						lineIndex = AddIndexedLine(tooltip, lineIndex, questObjectiveData.objectiveText, Colors.offwhite[1], Colors.offwhite[2], Colors.offwhite[3])
					elseif (objectiveType == "failed") then
						lineIndex = AddIndexedLine(tooltip, lineIndex, questObjectiveData.objectiveText, Colors.quest.red[1], Colors.quest.red[2], Colors.quest.red[3])
					else
						-- Fallback for unknowns.
						lineIndex = AddIndexedLine(tooltip, lineIndex, questObjectiveData.objectiveText, Colors.offwhite[1], Colors.offwhite[2], Colors.offwhite[3])
					end
				end
			end
		end

	end 

	if (data.realm) then
		-- FRIENDS_LIST_REALM -- "Realm: "
		lineIndex = AddIndexedLine(tooltip, lineIndex, " ")
		lineIndex = AddIndexedLine(tooltip, lineIndex, FRIENDS_LIST_REALM..data.realm, Colors.quest.gray[1], Colors.quest.gray[2], Colors.quest.gray[3])
	end

	-- Only for dev purposes
	if (Questie) and (false) then
		-- Only do this if the Questie
		-- tooltip option is enabled.
		if (Questie.db.global.enableTooltips) then
			local guid = UnitGUID(unit)
			if (guid) then
				local type, zero, server_id, instance_id, zone_uid, npc_id, spawn_uid = string_split("-", guid or "")
				if (npc_id) then
					local QuestieTooltips = QuestieLoader:ImportModule("QuestieTooltips")
					local tooltipData = QuestieTooltips:GetTooltip("m_" .. npc_id)
					if (tooltipData) then
						lineIndex = AddIndexedLine(tooltip, lineIndex, BLANK)
						for _, v in pairs (tooltipData) do
							v = v:gsub("|","||")
							v = v:gsub("\n","||newline") -- not encountered this yet
							lineIndex = AddIndexedLine(tooltip, lineIndex, v)
						end
					end
				end
			end
		end
	end

	-- Bar should always be here, but who knows.
	local bar = _G[tooltipName.."StatusBar"]
	if (bar) then
		bar.color = { r, g, b }
		bar:ClearAllPoints()
		bar:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 9, -3)
		bar:SetPoint("TOPRIGHT", tooltip, "BOTTOMRIGHT", -9, -3)
		bar:SetStatusBarColor(r, g, b)
	end

	for i = 1,lineIndex do
		local line = _G[tooltipName.."TextLeft"..i]
		if (line) then
			align(line)
		end
	end

	-- We don't want additions.
	LOCKDOWNS[tooltip] = true

	-- Aligns the backdrop to the current number of active lines.
	tooltip:Show()
end

Module.OnInit = function(self)
	self.layout = GetLayout(self:GetName())
	if (not self.layout) then
		return self:SetUserDisabled(true)
	end
end 

Module.OnEnable = function(self)
	for tooltip in self:GetAllBlizzardTooltips() do 
		self:KillBlizzardBorderedFrameTextures(tooltip)
		self:KillBlizzardTooltipBackdrop(tooltip)
		self:SetBlizzardTooltipBackdrop(tooltip, self.layout.TooltipBackdrop)
		self:SetBlizzardTooltipBackdropColor(tooltip, unpack(self.layout.TooltipBackdropColor))
		self:SetBlizzardTooltipBackdropBorderColor(tooltip, unpack(self.layout.TooltipBackdropBorderColor))
		self:SetBlizzardTooltipBackdropOffsets(tooltip, 10, 10, 10, 12)

		if (tooltip.SetText) then 
			hooksecurefunc(tooltip, "SetText", OnTooltipAddLine)
		end

		if (tooltip.AddLine) then 
			hooksecurefunc(tooltip, "AddLine", OnTooltipAddLine)
		end 

		if (tooltip.AddDoubleLine) then 
			hooksecurefunc(tooltip, "AddDoubleLine", OnTooltipAddDoubleLine)
		end 

		if (tooltip:HasScript("OnTooltipSetUnit")) then 
			tooltip:HookScript("OnTooltipSetUnit", OnTooltipSetUnit)
		end

		if (tooltip:HasScript("OnTooltipSetItem")) then 
			tooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
		end

		if (tooltip:HasScript("OnHide")) then 
			tooltip:HookScript("OnHide", OnTooltipHide)
		end
		
		if (tooltip:HasScript("OnShow")) then 
			tooltip:HookScript("OnShow", OnTooltipShow)
		end

		local bar = _G[tooltip:GetName().."StatusBar"]
		if (bar) then 
			bar:ClearAllPoints()
			bar:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 3, -1)
			bar:SetPoint("TOPRIGHT", tooltip, "BOTTOMRIGHT", -3, -1)
			bar:SetHeight(3)
			bar._owner = tooltip

			bar.value = bar:CreateFontString()
			bar.value:SetDrawLayer("OVERLAY")
			bar.value:SetFontObject(Game13Font_o1)
			bar.value:SetPoint("CENTER", 0, 0)
			bar.value:SetTextColor(235/255, 235/255, 235/255, .75)

			bar:HookScript("OnShow", StatusBar_OnShow)
			bar:HookScript("OnHide", StatusBar_OnHide)
			bar:HookScript("OnValueChanged", StatusBar_OnValueChanged)
		end 
	end 
end 
