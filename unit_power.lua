-- Lua API
local _G = _G
local math_floor = math.floor
local pairs = pairs
local string_format = string.format
local tonumber = tonumber
local tostring = tostring
local unpack = unpack

-- WoW API
local UnitCanAttack = UnitCanAttack
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsTapDenied = UnitIsTapDenied 
local UnitPlayerControlled = UnitPlayerControlled
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType

-- Sourced from BlizzardInterfaceResources/Resources/EnumerationTables.lua
local ALTERNATE_POWER_INDEX = Enum and Enum.PowerType.Alternate or ALTERNATE_POWER_INDEX or 10

-- Number abbreviations
---------------------------------------------------------------------	
local large = function(value)
	if (value >= 1e8) then 		return string_format("%.0fm", value/1e6) 	-- 100m, 1000m, 2300m, etc
	elseif (value >= 1e6) then 	return string_format("%.1fm", value/1e6) 	-- 1.0m - 99.9m 
	elseif (value >= 1e5) then 	return string_format("%.0fk", value/1e3) 	-- 100k - 999k
	elseif (value >= 1e3) then 	return string_format("%.1fk", value/1e3) 	-- 1.0k - 99.9k
	elseif (value > 0) then 	return value 								-- 1 - 999
	else 						return ""
	end 
end 

local short = function(value)
	value = tonumber(value)
	if (not value) then return "" end
	if (value >= 1e9) then
		return ("%.1fb"):format(value / 1e9):gsub("%.?0+([kmb])$", "%1")
	elseif value >= 1e6 then
		return ("%.1fm"):format(value / 1e6):gsub("%.?0+([kmb])$", "%1")
	elseif value >= 1e3 or value <= -1e3 then
		return ("%.1fk"):format(value / 1e3):gsub("%.?0+([kmb])$", "%1")
	else
		return tostring(math_floor(value))
	end	
end

-- zhCN exceptions
local gameLocale = GetLocale()
if (gameLocale == "zhCN") then 
	large = function(value)
		if (value >= 1e8) then 		return string_format("%.1f亿", value/1e8)
		elseif (value >= 1e4) then 	return string_format("%.1f万", value/1e4)
		elseif (value > 0) then 	return value
		else 						return ""
		end 
	end
end 

local gameLocale = GetLocale()
if (gameLocale == "zhCN") then 
	short = function(value)
		value = tonumber(value)
		if (not value) then return "" end
		if (value >= 1e8) then
			return ("%.1f亿"):format(value / 1e8):gsub("%.?0+([km])$", "%1")
		elseif value >= 1e4 or value <= -1e3 then
			return ("%.1f万"):format(value / 1e4):gsub("%.?0+([km])$", "%1")
		else
			return tostring(math_floor(value))
		end 
	end
end 

local UpdateValue = function(element, unit, min, max, powerType, powerID, disconnected, dead, tapped)
	if element.OverrideValue then
		return element:OverrideValue(unit, min, max, powerType, powerID, disconnected, dead, tapped)
	end
	local value = element.Value or element:IsObjectType("FontString") and element 
	if value then
		if (min == 0 or max == 0) then
			value:SetText("")
		else
			if value.showDeficit then
				if value.showPercent then
					if value.showMaximum then
						value:SetFormattedText("%s / %s - %.0f%%", short(max - min), short(max), math_floor(min/max * 100))
					else
						value:SetFormattedText("%s / %.0f%%", short(max - min), math_floor(min/max * 100))
					end
				else
					if value.showMaximum then
						value:SetFormattedText("%s / %s", short(max - min), short(max))
					else
						value:SetFormattedText("%s", short(max - min))
					end
				end
			else
				if value.showPercent then
					if value.showMaximum then
						value:SetFormattedText("%s / %s - %.0f%%", short(min), short(max), math_floor(min/max * 100))
					else
						value:SetFormattedText("%s / %.0f%%", short(min), math_floor(min/max * 100))
					end
				else
					if value.showMaximum then
						value:SetFormattedText("%s / %s", short(min), short(max))
					else
						value:SetFormattedText("%s", short(min))
					end
				end
			end
		end
	end
	local valuePercent = element.ValuePercent
	if (valuePercent) then 
		if (min and max) and (max > 0) then
			if (valuePercent.Override) then 
				valuePercent:Override(unit, min, max)
			else
				if (disconnected or dead) then 
					valuePercent:SetText("")
				else 
					valuePercent:SetFormattedText("%.0f", min/max*100 - (min/max*100)%1)
				end 
				if (valuePercent.PostUpdate) then 
					valuePercent:PostUpdate(unit, min, max)
				end 
			end 
		else
			valuePercent:SetText("")
		end 
	end

end 

local UpdateColor = function(element, unit, min, max, powerType, powerID, disconnected, dead, tapped)
	if element.OverrideColor then
		return element:OverrideColor(unit, min, max, powerType, powerID, disconnected, dead, tapped)
	end
	local self = element._owner
	local r, g, b
	if disconnected then
		r, g, b = unpack(self.colors.disconnected)
	elseif dead then
		r, g, b = unpack(self.colors.dead)
	elseif tapped then
		r, g, b = unpack(self.colors.tapped)
	else
		r, g, b = unpack(powerType and self.colors.power[powerType] or self.colors.power.UNUSED)
	end
	element:SetStatusBarColor(r, g, b)
end 

local Update = function(self, event, unit)
	if (not unit) or (unit ~= self.unit) then 
		return 
	end 

	local element = self.Power
	local powerID, powerType

	if element.visibilityFilter then 
		if (not element:visibilityFilter(unit)) then 
			return element:Hide()
		end
	end

	if element.PreUpdate then
		element:PreUpdate(unit)
	end

	powerID, powerType = UnitPowerType(unit)

	-- Check if the element is exclusive to a certain power type
	if element.exclusiveResource then 

		-- If the new powertype isn't the one tracked, 
		-- we hide the element.
		if (powerType ~= element.exclusiveResource) then 
			element.powerType = powerType
			element:Clear()
			element:Hide()
			return 
		end 

	-- Check if the min should be hidden on a certain resource type
	elseif element.ignoredResource then 

		-- If the new powertype is the one ignored, 
		-- we hide the element.
		if (powerType == element.ignoredResource) then 
			element.powerType = powerType
			element:Clear()
			element:Hide()
			return
		end  
	end 

	if (element.powerType ~= powerType) then
		element:Clear()
		element.powerType = powerType
	end

	local disconnected = not UnitIsConnected(unit)
	local dead = UnitIsDeadOrGhost(unit)
	local min = (disconnected or dead) and 0 or UnitPower(unit, powerID)
	local max = (disconnected or dead) and 0 or UnitPowerMax(unit, powerID)
	local tapped = (not UnitPlayerControlled(unit)) and UnitIsTapDenied(unit) and UnitCanAttack("player", unit)

	if (element.hideWhenEmpty and (min == 0)) or (element.hideWhenDead and dead) then 
		element:Clear()
		element:Hide()
		return
	end 

	element:SetMinMaxValues(0, max)
	element:SetValue(min, (event == "Forced"))
	element:UpdateColor(unit, min, max, powerType, powerID, disconnected, dead, tapped)
	element:UpdateValue(unit, min, max, powerType, powerID, disconnected, dead, tapped)
	
	if (not element:IsShown()) then 
		element:Show()
	end
	
	if element.PostUpdate then
		return element:PostUpdate(unit, min, max, powerType, powerID)
	end	
end 

local Proxy = function(self, ...)
	return (self.Power.Override or Update)(self, ...)
end 

local ForceUpdate = function(element)
	return Proxy(element._owner, "Forced", element._owner.unit)
end

local Enable = function(self)
	local element = self.Power
	if element then
		element._owner = self
		element.ForceUpdate = ForceUpdate

		local unit = self.unit
		if element.frequent and ((unit == "player") or (unit == "pet")) then 
			self:RegisterEvent("UNIT_POWER_FREQUENT", Proxy)
		else 
			self:RegisterEvent("UNIT_POWER_UPDATE", Proxy)
		end 

		self:RegisterEvent("UNIT_POWER_BAR_SHOW", Proxy)
		self:RegisterEvent("UNIT_POWER_BAR_HIDE", Proxy)
		self:RegisterEvent("UNIT_DISPLAYPOWER", Proxy)
		self:RegisterEvent("UNIT_CONNECTION", Proxy)
		self:RegisterEvent("UNIT_MAXPOWER", Proxy)
		self:RegisterEvent("UNIT_FACTION", Proxy)
		self:RegisterEvent("PLAYER_ALIVE", Proxy, true)

		element.UpdateColor = UpdateColor
		element.UpdateValue = UpdateValue

		return true
	end
end 

local Disable = function(self)
	local element = self.Power
	if element then
		element:Hide()

		self:UnregisterEvent("UNIT_POWER_FREQUENT", Proxy)
		self:UnregisterEvent("UNIT_POWER_UPDATE", Proxy)
		self:UnregisterEvent("UNIT_POWER_BAR_SHOW", Proxy)
		self:UnregisterEvent("UNIT_POWER_BAR_HIDE", Proxy)
		self:UnregisterEvent("UNIT_DISPLAYPOWER", Proxy)
		self:UnregisterEvent("UNIT_CONNECTION", Proxy)
		self:UnregisterEvent("UNIT_MAXPOWER", Proxy)
		self:UnregisterEvent("UNIT_FACTION", Proxy)

	end
end 

-- Register it with compatible libraries
for _,Lib in ipairs({ (Wheel("LibUnitFrame", true)), (Wheel("LibNamePlate", true)) }) do 
	Lib:RegisterElement("Power", Enable, Disable, Proxy, 18)
end 
