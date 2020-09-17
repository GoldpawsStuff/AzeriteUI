local ADDON, Private = ...
local Core = Wheel("LibModule"):GetModule(ADDON)
if (not Core) then
	return 
end

local Module = Core:NewModule("ExplorerMode", "PLUGIN", "LibMessage", "LibEvent", "LibDB", "LibFader", "LibFrame")

-- Lua API
local _G = _G
local table_insert = table.insert
local unpack = unpack

-- Private API
local Colors = Private.Colors
local GetConfig = Private.GetConfig
local GetLayout = Private.GetLayout
local GetMedia = Private.GetMedia

Module.PostUpdatePlayerFading = function(self)
	local db = self.db
	if (db.enableExplorer) then 
		self:AttachModuleFrame("ActionBarMain")
		self:AttachModuleFrame("UnitFramePlayer")
		self:AttachModuleFrame("UnitFramePet")
		self:SendMessage("GP_EXPLORER_MODE_ENABLED")
	else 
		self:DetachModuleFrame("ActionBarMain")
		self:DetachModuleFrame("UnitFramePlayer")
		self:DetachModuleFrame("UnitFramePet")
		self:SendMessage("GP_EXPLORER_MODE_DISABLED")
	end 
end

Module.PostUpdateTrackerFading = function(self)
	local db = self.db
	if (db.enableTrackerFading) then 
		self:AttachModuleFrame("BlizzardObjectivesTracker")
		self:SendMessage("GP_TRACKER_EXPLORER_MODE_ENABLED")
	else 
		self:DetachModuleFrame("BlizzardObjectivesTracker")
		self:SendMessage("GP_TRACKER_EXPLORER_MODE_DISABLED")
	end 
end

Module.PostUpdateExplorerChat = function(self)
	local db = self.db
	if (db.enableExplorerChat) then
		self:SendMessage("GP_EXPLORER_CHAT_ENABLED")
	else
		self:SendMessage("GP_EXPLORER_CHAT_DISABLED")
	end
end

Module.AttachModuleFrame = function(self, moduleName)
	local module = Core:GetModule(moduleName, true)
	if module and not(module:IsIncompatible() or module:DependencyFailed()) then 
		if (module.GetExplorerModeFrameAnchors) then
			for _,frame in ipairs({ module:GetExplorerModeFrameAnchors() }) do
				self:RegisterObjectFade(frame)
			end
		else
			local frame = module:GetFrame()
			if frame then 
				self:RegisterObjectFade(frame)
			end
		end
	end 
end 

Module.DetachModuleFrame = function(self, moduleName)
	local module = Core:GetModule(moduleName, true)
	if module and not(module:IsIncompatible() or module:DependencyFailed()) then 
		if (module.GetExplorerModeFrameAnchors) then
			for _,frame in ipairs({ module:GetExplorerModeFrameAnchors() }) do
				self:UnregisterObjectFade(frame)
			end
		else
			local frame = module:GetFrame()
			if frame then 
				self:UnregisterObjectFade(frame)
			end
		end
	end
end

Module.OnInit = function(self)
	self:PurgeSavedSettingFromAllProfiles(self:GetName(), 
		"enableExplorerInstances",
		"enablePlayerFading",
		"enableTrackerFadingInstances",
		"useFadingInInstance", 
		"useFadingInvehicles"
	)
	self.db = GetConfig(self:GetName())

	local OptionsMenu = Core:GetModule("OptionsMenu", true)
	if (OptionsMenu) then
		local callbackFrame = OptionsMenu:CreateCallbackFrame(self)
		callbackFrame:AssignProxyMethods("PostUpdatePlayerFading", "PostUpdateTrackerFading", "PostUpdateExplorerChat")
		callbackFrame:AssignSettings(self.db)
		callbackFrame:AssignCallback([=[
			if (not name) then
				return 
			end 
			name = string.lower(name); 
			if (name == "change-enableexplorer") then 
				self:SetAttribute("enableExplorer", value); 
				self:CallMethod("PostUpdatePlayerFading"); 

			elseif (name == "change-enabletrackerfading") then 
				self:SetAttribute("enableTrackerFading", value); 
				self:CallMethod("PostUpdateTrackerFading"); 

			elseif (name == "change-enableexplorerchat") then
				self:SetAttribute("enableExplorerChat", value); 
				self:CallMethod("PostUpdateExplorerChat"); 
			end 
		]=])
	end
end 

Module.OnEnable = function(self)
	self:PostUpdatePlayerFading()
	self:PostUpdateTrackerFading()
	self:PostUpdateExplorerChat()
end
