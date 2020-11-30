local LibClientBuild = Wheel("LibClientBuild")
assert(LibClientBuild, "UnitHealth requires LibClientBuild to be loaded.")

local LibPlayerData = Wheel("LibPlayerData")
assert(LibPlayerData, "UnitHealth requires LibPlayerData to be loaded.")

-- Lua API
local _G = _G
local math_floor = math.floor
local math_modf = math.modf
local pairs = pairs
local string_find = string.find
local string_format = string.format
local tonumber = tonumber
local tostring = tostring
local unpack = unpack

-- WoW API
local IsInGroup = IsInGroup
local IsInInstance = IsInInstance
local UnitCanAttack = UnitCanAttack
local UnitClass = UnitClass
local UnitDetailedThreatSituation = UnitDetailedThreatSituation
local UnitGUID = UnitGUID
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsFriend = UnitIsFriend
local UnitIsPlayer = UnitIsPlayer
local UnitIsUnit = UnitIsUnit
local UnitIsTapDenied = UnitIsTapDenied 
local UnitPlayerControlled = UnitPlayerControlled
local UnitReaction = UnitReaction
local UnitThreatSituation = UnitThreatSituation

-- WoW Strings
local S_AFK = AFK
local S_DEAD = DEAD
local S_PLAYER_OFFLINE = PLAYER_OFFLINE

-- Constants for client version
local IsClassic = LibClientBuild:IsClassic()
local IsRetail = LibClientBuild:IsRetail()

-- Constants
local _,CLASS = UnitClass("player")
local minAbsorbDisplaySize = .1
local maxAbsorbDisplaySize = .6

-- Setup the classic heal predict environment
local HealComm, HealComm_OVERTIME_HEALS
if (IsClassic) then
	-- Add in support for LibHealComm-4.0
--	HealComm = LibStub("LibHealComm-4.0")
--	HealComm_OVERTIME_HEALS = bit.bor(HealComm.HOT_HEALS, HealComm.CHANNEL_HEALS)

	
end

-- Utility Functions
---------------------------------------------------------------------	
-- Calculate a RGB gradient from a minimum of 2 sets of RGB values
local colorsAndPercent = function(currentValue, maxValue, ...)
	if (currentValue <= 0 or maxValue == 0) then
		return nil, ...
	elseif (currentValue >= maxValue) then
		return nil, select(-3, ...)
	end
	local num = select("#", ...) / 3
	local segment, relperc = math_modf((currentValue / maxValue) * (num - 1))
	return relperc, select((segment * 3) + 1, ...)
end

-- RGB color gradient calculation from a minimum of 2 sets of RGB values
-- local r, g, b = gradient(currentValue, maxValue, r1, g1, b1, r2, g2, b2[, r3, g3, b3, ...])
local gradient = function(currentValue, maxValue, ...)
	local relperc, r1, g1, b1, r2, g2, b2 = colorsAndPercent(currentValue, maxValue, ...)
	if (relperc) then
		return r1 + (r2 - r1) * relperc, g1 + (g2 - g1) * relperc, b1 + (b2 - b1) * relperc
	else
		return r1, g1, b1
	end
end

-- Number abbreviations
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

local UpdateValues = function(health, unit, min, max, minPerc, maxPerc)
	local healthValue = health.Value
	if (healthValue) then 
		if (healthValue.Override) then 
			healthValue:Override(unit, min, max)
		else
			if (health.disconnected) then 
				healthValue:SetText(S_PLAYER_OFFLINE)
			elseif (health.dead) then 
				healthValue:SetText(S_DEAD)
			else 
				if (min == 0 or max == 0) and (not healthValue.showAtZero) then
					healthValue:SetText("")
				else
					if (healthValue.useSmartValue) then 
						if (min == max) then
							healthValue:SetFormattedText("%s", large(min))
						else
							healthValue:SetFormattedText("%.0f%%", min/max*100 - (min/max*100)%1)
						end
					else
						if (healthValue.showMaxValue) then
							healthValue:SetFormattedText("%s / %s", large(min), large(max))
						else
							healthValue:SetFormattedText("%s", large(min))
						end
					end
				end
			end
			if (healthValue.PostUpdate) then 
				healthValue:PostUpdate(unit, min, max)
			end 
		end 
	end
	local healthPercent = health.ValuePercent
	if (healthPercent) then 
		local min, max = minPerc or min, maxPerc or max
		if (min and max) and (max > 0) then
			if (healthPercent.Override) then 
				healthPercent:Override(unit, min, max)
			else
				if (health.disconnected or health.dead) then 
					healthPercent:SetText("")
				else 
					healthPercent:SetFormattedText("%.0f", min/max*100 - (min/max*100)%1)
				end 
				if (healthPercent.PostUpdate) then 
					healthPercent:PostUpdate(unit, min, max)
				end 
			end 
		else
			healthPercent:SetText("")
		end 
	end
	local absorbValue = health.ValueAbsorb
	if (absorbValue) then 
		local curAbsorb = health.curAbsorb
		if (curAbsorb) and (curAbsorb > 0) then 
			if (absorbValue.Override) then 
				absorbValue:Override(unit, curAbsorb)
			else
				if (health.disconnected or health.dead) then 
					absorbValue:SetText("")
				else 
					absorbValue:SetFormattedText("%s", short(curAbsorb))
				end 
				if (absorbValue.PostUpdate) then 
					absorbValue:PostUpdate(unit, curAbsorb)
				end 
			end 
		else 
			absorbValue:SetText("")
		end 
	end
end 

local UpdateColors = function(health, unit, min, max)
	if health.OverrideColor then
		return health:OverrideColor(unit, min, max)
	end

	local self = health._owner
	local color, r, g, b
	if (health.colorPlayer and UnitIsUnit(unit, "player")) then 
		color = self.colors.class[CLASS]
	elseif (health.colorTapped and health.tapped) then
		color = self.colors.tapped
	elseif (health.colorDisconnected and health.disconnected) then
		color = self.colors.disconnected
	elseif (health.colorDead and health.dead) then
		color = self.colors.dead
	elseif (health.colorCivilian and UnitIsPlayer(unit) and UnitIsFriend("player", unit)) then 
		color = self.colors.reaction.civilian
	elseif (health.colorClass and UnitIsPlayer(unit)) then
		local _, class = UnitClass(unit)
		color = class and self.colors.class[class]
	elseif (health.colorPetAsPlayer and UnitIsUnit(unit, "pet")) then 
		local _, class = UnitClass("player")
		color = class and self.colors.class[class]
	else
		if (health.colorThreat) then
			-- BUG: Non-existent '*target' or '*pet' units cause UnitThreatSituation() errors (thank you oUF!)
			local threat
			if (IsRetail) then
				if ((not health.hideThreatSolo) or (IsInGroup() or IsInInstance())) then
					local feedbackUnit = health.threatFeedbackUnit
					if (not UnitIsFriend("player", unit)) and (feedbackUnit and (feedbackUnit ~= unit) and UnitExists(feedbackUnit)) then
						threat = UnitThreatSituation(feedbackUnit, unit)
					else
						threat = UnitThreatSituation(unit)
					end
				end
			end
			if (threat) and (self.colors.threat[threat]) then 
				color = self.colors.threat[threat]
			end
		end
		if (not color) then
			if (health.colorReaction and UnitReaction(unit, "player")) then
				color = self.colors.reaction[UnitReaction(unit, "player")]
			elseif (health.colorHealth) then 
				color = self.colors.health
			end
		end
	end

	if (color) then 
		if (health.colorSmooth) then 
			r, g, b = gradient(min, max, 1,0,0, color[1], color[2], color[3], color[1], color[2], color[3])
		else 
			r, g, b = color[1], color[2], color[3]
		end 
		health:SetStatusBarColor(r, g, b)
		health.Preview:SetStatusBarColor(r, g, b)

		-- Dynamically tint the absorb bar towards the health color
		local absorb = health.Absorb
		if (absorb and health.colorAbsorb) then
			local aR = r + (1 - r)*4/5 -- 1/2
			local aG = g + (1 - g)*3/4 -- 1/3
			local aB = b + (1 - b)*4/5 -- 1/2
			absorb:SetStatusBarColor(aR, aG, aB)
		end
	end 
	
	if (health.PostUpdateColor) then 
		health:PostUpdateColor(unit, min, max, r, g, b)
	end 
end

local UpdateOrientations = function(health)
	local orientation = health:GetOrientation() or "RIGHT"
	local orientationFlippedH = health:IsFlippedHorizontally()
	local orientationFlippedV = health:IsFlippedVertically()

	local mirrorOrientation =  orientation == "LEFT" and "RIGHT" 
	or orientation == "RIGHT" and "LEFT" 
	or orientation == "UP" and "DOWN"
	or orientation == "DOWN" and "UP"

	local mirrorFlippedH = (mirrorOrientation == "RIGHT") and true or false
	local mirrorFlippedV = (mirrorOrientation == "DOWN") and true or false

	local preview = health.Preview
	preview:SetOrientation(orientation) 
	preview:SetFlippedHorizontally(orientationFlippedH)
	preview:SetFlippedVertically(orientationFlippedV)

	local absorb = health.Absorb
	if (absorb) then
		absorb:SetOrientation(mirrorOrientation) 
		absorb:SetFlippedHorizontally(mirrorFlippedH)
		absorb:SetFlippedVertically(mirrorFlippedV)
	end
end 

local UpdateSizes = function(health)
	local width, height = health:GetSize()
	width = math_floor(width + .5)
	height = math_floor(height + .5)
	health.Preview:SetSize(width, height)
	if (health.Absorb) then 
		health.Absorb:SetSize(width, height)
	end
	if (health.Predict) then
		health.Predict:SetSize(width, height)
	end
end

local UpdateStatusBarTextures = function(health)
	local texture = health:GetStatusBarTexture():GetTexture()
	health.Preview:SetStatusBarTexture(texture)
	if (health.Absorb) then
		health.Absorb:SetStatusBarTexture(texture)
	end
	if (health.Predict) then
		health.Predict:SetTexture(texture)
	end
end

local UpdateTexCoords = function(health)
	local left, right, top, bottom = health:GetTexCoord()
	health.Preview:SetTexCoord(left, right, top, bottom)
	if (health.Absorb) then
		health.Absorb:SetTexCoord(left, right, top, bottom)
	end
	if (health.Predict) then
		-- Forcing an update to adjust the prediction texture.
		-- This might be at a tiny, tiny performance cost, 
		-- but this whole function is only ever called when 
		-- the Health bar's texcoords are manually changed. 
		if (UnitExists(health.unit)) then
			health:ForceUpdate()
		end
	end
end

local Update = function(self, event, unit)
	if (not unit) or (unit ~= self.unit) then 
		return 
	end 

	-- Allow modules to run their pre-updates
	local health = self.Health
	if health.PreUpdate then
		health:PreUpdate(unit)
	end

	-- Different GUID means a different player or NPC,
	-- so we want updates to be instant, not smoothed. 
	local guid = UnitGUID(unit)
	local forced = guid ~= health.guid

	-- Store some basic values on the health element
	health.guid = guid
	health.disconnected = not UnitIsConnected(unit)
	health.dead = UnitIsDeadOrGhost(unit)
	health.tapped = (not UnitPlayerControlled(unit)) and UnitIsTapDenied(unit) and UnitCanAttack("player", unit)

	-- If the unit is dead or offline, we can skip a lot of stuff, 
	-- so we're making an exception for this early on. 
	if (health.disconnected or health.dead) then 
		-- Forcing all values to zero for dead or disconnected units. 
		-- Never thought it made sense to "know" the health of something dead, 
		-- since health is life, and you don't have it while dead. Doh. 
		health:SetMinMaxValues(0, 0, true)
		health:SetValue(0, true)
		health:UpdateValues(unit, 0, 0)

		-- Hide all extra elements, they have no meaning when dead or disconnected. 
		health.Preview:Hide()
		if (health.Predict) then
			health.Predict:Hide()
		end
		if (health.Absorb) then
			health.Absorb:Hide()
		end

		-- Allow modules to run their post-updates
		if (health.PostUpdate) then 
			health:PostUpdate(unit, 0, 0)
		end 
		return 
	end 

	-- Retrieve element pointers
	local absorb = health.Absorb 
	local predict = health.Predict 
	local preview = health.Preview

	-- Retrieve values for our bars
	local curHealth = UnitHealth(unit) or 0 -- The unit's current health
	local maxHealth = UnitHealthMax(unit) or 0 -- The unit's maximum health
	local perc = (maxHealth > 0) and curHealth/maxHealth*100

	local allAbsorbs = absorb and UnitGetTotalAbsorbs(unit) or 0 -- The total amount of damage the unit can absorb before losing health
	local allNegativeHeals = absorb and UnitGetTotalHealAbsorbs(unit) or 0 -- The total amount of healing the unit can absorb without gaining health
	local myIncomingHeal = predict and UnitGetIncomingHeals(unit, "player") or 0 -- Incoming heals to the unit cast by the player
	local allIncomingHeal = predict and UnitGetIncomingHeals(unit) or 0 -- Incoming heals to the unit from any source
	local otherIncomingHeal = 0

	-- Store this for the postupdates
	health.curAbsorb = allAbsorbs

	health:SetMinMaxValues(0, maxHealth, forced)
	health:SetValue(curHealth, forced)
	health:UpdateColors(unit, curHealth, maxHealth)

	-- Always force this to be instant regardless of bar settings. 
	preview:SetMinMaxValues(0, maxHealth, true)
	preview:SetValue(curHealth, true)

	local minPerc, maxPerc
	if (maxHealth == 100) then 
		minPerc = curHealth
		maxPerc = maxHealth
		curHealth = 0
		maxHealth = 0
	end

	health:UpdateValues(unit, curHealth, maxHealth, minPerc, maxPerc)

	if (absorb) then
		local maxAbsorb = health.maxAbsorb or maxAbsorbDisplaySize
		local hasOverAbsorb = (allAbsorbs > 0) and (curHealth + allIncomingHeal + allAbsorbs >= maxHealth)
		local absorbDisplay = (allAbsorbs > maxHealth*maxAbsorb) and maxHealth*maxAbsorb or allAbsorbs
		if (absorbDisplay < maxHealth * (health.absorbThreshold or .05)) then 
			absorbDisplay = 0
		end

		absorb:SetMinMaxValues(0, maxHealth) 
		absorb:SetValue(absorbDisplay, forced)
	end

	if (predict) then
		local showPrediction, change
		if ((allIncomingHeal > 0) or (allNegativeHeals > 0)) then 
			local startPoint = curHealth/maxHealth

			-- Dev switch to test absorbs with normal healing
			--allIncomingHeal, allNegativeHeals = allNegativeHeals, allIncomingHeal

			-- Hide predictions if the change is very small, or if the unit is at max health. 
			change = (allIncomingHeal - allNegativeHeals)/maxHealth
			if ((curHealth < maxHealth) and (change > (health.predictThreshold or .05))) then 
				local endPoint = startPoint + change

				-- Crop heal prediction overflows
				if (endPoint > 1) then 
					endPoint = 1
					change = endPoint - startPoint
				end

				-- Crop heal absorb overflows
				if (endPoint < 0) then 
					endPoint = 0
					change = -startPoint
				end

				-- This shouldn't happen, but let's do it anyway. 
				if (startPoint ~= endPoint) then 
					showPrediction = true
				end
			end 
		end

		if (showPrediction) then 
			local orientation = preview:GetOrientation()
			local min,max = preview:GetMinMaxValues()
			local value = preview:GetValue() / max
			local previewTexture = preview:GetStatusBarTexture()
			local previewWidth, previewHeight = preview:GetSize()
			local left, right, top, bottom = preview:GetTexCoord()
		
			if (orientation == "RIGHT") then 
				local texValue, texChange = value, change
		
				local rangeH, rangeV
				rangeH = right - left
				rangeV = bottom - top
				texChange = change*value
				texValue = left + value*rangeH
		
				if (change > 0) then 
					predict:ClearAllPoints()
					predict:SetPoint("BOTTOMLEFT", previewTexture, "BOTTOMRIGHT", 0, 0)
					predict:SetSize(change*previewWidth, previewHeight)
					predict:SetTexCoord(texValue, texValue + texChange, top, bottom)
					predict:SetVertexColor(0, .7, 0, .25)
					predict:Show()
				elseif (change < 0) then 
					predict:ClearAllPoints()
					predict:SetPoint("BOTTOMRIGHT", previewTexture, "BOTTOMRIGHT", 0, 0)
					predict:SetSize((-change)*previewWidth, previewHeight)
					predict:SetTexCoord(texValue + texChange, texValue, top, bottom)
					predict:SetVertexColor(.5, 0, 0, .75)
					predict:Show()
				else 
					predict:Hide()
				end 
		
			elseif (orientation == "LEFT") then 
				local texValue, texChange = value, change
				local rangeH, rangeV
				rangeH = right - left
				rangeV = bottom - top
				texChange = change*value
				texValue = left + value*rangeH
		
				if (change > 0) then 
					predict:ClearAllPoints()
					predict:SetPoint("BOTTOMRIGHT", previewTexture, "BOTTOMLEFT", 0, 0)
					predict:SetSize(change*previewWidth, previewHeight)
					predict:SetTexCoord(texValue + texChange, texValue, top, bottom)
					predict:SetVertexColor(0, .7, 0, .25)
					predict:Show()
				elseif (change < 0) then
					predict:ClearAllPoints()
					predict:SetPoint("BOTTOMLEFT", previewTexture, "BOTTOMLEFT", 0, 0)
					predict:SetSize((-change)*previewWidth, previewHeight)
					predict:SetTexCoord(texValue, texValue + texChange, top, bottom)
					predict:SetVertexColor(.5, 0, 0, .75)
					predict:Show()
				else 
					predict:Hide()
				end 
			end 

			if (not predict:IsShown()) then 
				predict:Show()
			end 
		else
			if (predict:IsShown()) then 
				predict:Hide()
			end 
		end
	end

	if (not health:IsShown()) then 
		health:Show()
	end

	if (not preview:IsShown()) then 
		preview:Show()
	end 

	if (absorb) and (not absorb:IsShown()) then 
		absorb:Show()
	end 

	if (health.PostUpdate) then
		return health:PostUpdate(unit, curHealth, maxHealth, minPerc, maxPerc)
	end	
end

local Proxy = function(self, ...)
	return (self.Health.Override or Update)(self, ...)
end 

local ForceUpdate = function(health)
	return Proxy(health._owner, "Forced", health._owner.unit)
end

local Enable = function(self)
	local unit = self.unit
	local health = self.Health

	if (health) then
		health._owner = self
		health.unit = unit
		health.guid = nil
		health.ForceUpdate = ForceUpdate
		health.UpdateColors = UpdateColors
		health.UpdateValues = UpdateValues
	
		-- Post updates to make sure the sub-elements follow the health
		health.PostUpdateSize = UpdateSizes
		health.PostUpdateWidth = UpdateSizes
		health.PostUpdateHeight = UpdateSizes
		health.PostUpdateOrientation = UpdateOrientations
		health.PostUpdateStatusBarTexture = UpdateStatusBarTextures
		health.PostUpdateTexCoord = UpdateTexCoords

		-- Health events
		if (health.frequent) and (not IsRetail) then
			self:RegisterEvent("UNIT_HEALTH_FREQUENT", Proxy)
		else
			self:RegisterEvent("UNIT_HEALTH", Proxy)
		end
		self:RegisterEvent("UNIT_MAXHEALTH", Proxy)

		-- Color events
		self:RegisterEvent("UNIT_CONNECTION", Proxy)
		self:RegisterEvent("UNIT_FACTION", Proxy) 

		-- Threat coloring events
		self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE", Proxy)
		self:RegisterEvent("UNIT_THREAT_LIST_UPDATE", Proxy)

		if (IsRetail) then

			-- Predict events
			self:RegisterEvent("UNIT_HEAL_PREDICTION", Proxy)

			-- Absorb events
			self:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED", Proxy)
			self:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", Proxy)
		end

		if (not health.Preview) then 
			local preview = health:CreateStatusBar()
			preview._owner = self
			preview:SetAllPoints(health)
			preview:SetFrameLevel(health:GetFrameLevel() - 1)
			preview:DisableSmoothing(true)
			preview:SetSparkTexture("")
			preview:SetAlpha(.5)
			health.Preview = preview
		end 

		if (IsRetail) then
			if (not health.Predict) then 
				local predict = health:CreateTexture()
				predict._owner = health
				predict:SetDrawLayer("ARTWORK", 0)
				health.Predict = predict
			end 
	
			if (not health.Absorb) then 
				local absorbAlpha = (string_find(unit, "raid") or string_find(unit, "party")) and .5 or ((unit == "player") or (unit == "target")) and .35 or .25
				local absorb = health:CreateStatusBar()
				absorb._owner = health
				absorb:SetAllPoints(health)
				absorb:SetFrameLevel(health:GetFrameLevel() + 3)
				absorb:SetSparkTexture(health:GetSparkTexture())
				absorb:SetStatusBarColor(1, 1, 1)
				absorb:SetAlpha(health.absorbOverrideAlpha or absorbAlpha)
				health.Absorb = absorb
			end 
		end

		health:PostUpdateSize()
		health:PostUpdateOrientation()
		health:PostUpdateStatusBarTexture()
		health:PostUpdateTexCoord()

		return true
	end
end

local Disable = function(self)
	local health = self.Health
	if (health) then 
		self:UnregisterEvent("UNIT_HEALTH_FREQUENT", Proxy)
		self:UnregisterEvent("UNIT_HEALTH", Proxy)
		self:UnregisterEvent("UNIT_MAXHEALTH", Proxy)
		self:UnregisterEvent("UNIT_CONNECTION", Proxy)
		self:UnregisterEvent("UNIT_FACTION", Proxy) 
		self:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE", Proxy)
		self:UnregisterEvent("UNIT_THREAT_LIST_UPDATE", Proxy)

		if (IsRetail) then
			self:UnregisterEvent("UNIT_HEAL_PREDICTION", Proxy)
			self:UnregisterEvent("UNIT_ABSORB_AMOUNT_CHANGED", Proxy)
			self:UnregisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", Proxy)
		end

		health:Hide()
		health.guid = nil

		-- Hide the sub elements
		if (health.Absorb) then 
			health.Absorb:Hide()
		end
		if (health.Predict) then 
			health.Predict:Hide()
		end
		if (health.Preview) then 
			health.Preview:Hide()
		end

		-- Clear out the texts
		if (health.Value) then 
			health.Value:SetText("")
		end
		if (health.ValuePercent) then 
			health.ValuePercent:SetText("")
		end
		if (health.ValueAbsorb) then 
			health.ValueAbsorb:SetText("")
		end
	end
end

-- Register it with compatible libraries
for _,Lib in ipairs({ (Wheel("LibUnitFrame", true)), (Wheel("LibNamePlate", true)) }) do 
	Lib:RegisterElement("Health", Enable, Disable, Proxy, 61)
end 
