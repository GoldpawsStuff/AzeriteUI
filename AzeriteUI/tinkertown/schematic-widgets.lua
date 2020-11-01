--[[--

	The purpose of this file is to provide
	standarized forges for common widgets,
	like action- and aura buttons.

--]]--
local ADDON, Private = ...

-- Private API
local Colors = Private.Colors
local GetAuraFilter = Private.GetAuraFilter
local GetFont = Private.GetFont
local GetMedia = Private.GetMedia
local GetSchematic = Private.GetSchematic

-- Utility Functions
-----------------------------------------------------------
-- Button mouseover highlight update
-- Requires: Darken, Border, Glow
local PostUpdateMouseOver = function(self)
	if (self.isMouseOver) then 
		self.Darken:SetAlpha(0)
		self.Border:SetVertexColor(Colors.highlight[1], Colors.highlight[2], Colors.highlight[3], 1)
		self.Glow:Show()
	else 
		self.Darken:SetAlpha(.15)
		self.Border:SetVertexColor(Colors.ui[1], Colors.ui[2], Colors.ui[3], 1)
		self.Glow:Hide()
	end 
end 

-- Button stack/charge count font update
-- Requires: Count
-- Optional: Rank
local PostUpdateStackCount = function(self, count)
	count = tonumber(count) or 0
	local font = GetFont((count < 10) and 18 or 14, true) 
	if (self.Count:GetFontObject() ~= font) then 
		self.Count:SetFontObject(font)
	end
	-- TO BACK-END!
	-- Hide the rank text element if a count exists. 
	-- I don't think this'll ever happen (?), 
	-- but better safe than sorry. 
	if (self.Rank) then 
		self.Rank:SetShown((count == 0))
	end 
end

-- Legacy Schematics
-----------------------------------------------------------
-- Applied to aura buttons.
-- Keep these in a manner that works without knowing the size.
Private.RegisterSchematic("WidgetForge::AuraButton::Large", "Legacy", {
	{
		type = "ModifyWidgets",
		widgets = {
			{
				parent = nil, ownerKey = "Icon", objectType = "Texture",
				chain = {
					"SetPosition", { "CENTER", 0, 0 },
					"SetTexCoord", { 5/64, 59/64, 5/64, 59/64 },
					"SetSizeOffset", -10
				} 
			},
			{
				parent = nil, ownerKey = "Count", objectType = "FontString",
				chain = {
					"SetPosition", { "BOTTOMRIGHT", 2, -2 },
					"SetFontObject", Private.GetFont(14, true),
					"SetTextColor", { Colors.normal[1], Colors.normal[2], Colors.normal[3], .85 }
				}
			},
			{
				parent = nil, ownerKey = "Time", objectType = "FontString",
				chain = {
					"SetPosition", { "TOPLEFT", -2, 2 },
					"SetFontObject", Private.GetFont(14, true)
				}
			}
		}
	},
	{
		type = "CreateWidgets",
		widgets = {
			{
				parent = "self", ownerKey = "Border", objectType = "Frame", objectSubType = "Frame",
				chain = {
					"SetFrameLevelOffset", 2,
					"SetBackdrop", {{ edgeFile = Private.GetMedia("aura_border"), edgeSize = 16 }},
					"SetBackdropBorderColor", { Colors.ui[1] *.3, Colors.ui[2] *.3, Colors.ui[3] *.3, 1 },
					"ClearAllPoints", "SetPoint", { "TOPLEFT", -7, 7 }, "SetPoint", { "BOTTOMRIGHT", 7, -7 }
				}

			}
		}
	}
})

-- Applied to primary bar action buttons.
Private.RegisterSchematic("WidgetForge::ActionButton::Normal", "Legacy", {
})

-- Applied to pet-, stance- and additional bars action buttons.
Private.RegisterSchematic("WidgetForge::ActionButton::Small", "Legacy", {
})

-- Applied to huge floating buttons like zone abilities.
Private.RegisterSchematic("WidgetForge::ActionButton::Large", "Legacy", {
})

-- Azerite Schematics
-----------------------------------------------------------
-- Applied to primary bar action buttons.
Private.RegisterSchematic("WidgetForge::ActionButton::Normal", "Azerite", {
	{
		-- Only set the parent in modifiable widgets if it is your intention to change it.
		-- Otherwise the code will assume the owner is the parent, and leave it as is,
		-- which is what we want in the majority of cases.
		type = "ModifyWidgets",
		widgets = {
			{
				-- Note that a missing ownerKey or parentKey
				-- will apply these changes to the original object instead.
				parent = nil, ownerKey = nil, 
				chain = {
					"SetSize", { 64, 64 }, 
					"SetHitBox", { -4, -4, -4, -4 }
				},
				values = {
					"colors", Colors,
					"maxDisplayCount", 99,
					"PostUpdateCount", PostUpdateStackCount,
					"PostUpdateCooldown", function(self, cooldownObject) 
						cooldownObject:SetSwipeColor(0, 0, 0, .75)
					end,
					"PostUpdateChargeCooldown", function(self, cooldownObject) 
						cooldownObject:SetSwipeColor(0, 0, 0, .5)
					end,
					"PostEnter", PostUpdateMouseOver,
					"PostLeave", PostUpdateMouseOver,
					"PostUpdate", PostUpdateMouseOver,

					-- Tone down and desaturate gamepad binds when not usable.
					"PostUpdateUsable", function(self, shouldDesaturate)
						if (shouldDesaturate) then
							for i = 1,4 do
								local slot = self["GamePadKeySlot"..i]
								slot:SetDesaturated(true)
								slot:SetVertexColor(.5,.5,.5)
							end
						else
							for i = 1,4 do
								local slot = self["GamePadKeySlot"..i]
								slot:SetDesaturated(false)
								slot:SetVertexColor(1,1,1)
							end
						end
					end,

					"OnKeyDown", function(self) end,
					"OnKeyUp", function(self) end,

					-- This will take presedence when true,
					-- causing any existing gamepad binds 
					-- to be shown instead of keyboard.
					--"prioritizeGamePadBinds", true, 

					-- This will make sure keyboard binds are shown
					-- even if a gamepad bind is before it in the list.
					--"prioritzeKeyboardBinds", true, 

					"GetBindingTextAbbreviated", function(self)
						local key = self:GetBindingText()
						if (key) then
							key = key:upper()

							local keyboard = self:GetBindingText("key")
							local gamepad = self:GetBindingText("pad")

							if (keyboard and gamepad) then
								if (self.prioritizeGamePadBinds) then
									key = gamepad
								elseif (self.prioritzeKeyboardBinds) then
									key = keyboard
								end
							end

							if (key:find("PAD"))  then

								local mods = 0
								local slot1, slot2, slot3, slot4

								-- Get the main button pressed, without modifiers
								local main = key:match("%-?([%a%d]-)$")
								if (main) then

									-- Figure out what modifiers are used
									local alt = key:find("ALT%-")
									local ctrl = key:find("CTRL%-")
									local shift = key:find("SHIFT%-")

									-- If modifiers are used, check if the pad has them assigned. 
									local padAlt, padCtrl, padShift
									if (alt or ctrl or shift) then
										if (alt) then
											padAlt = GetCVar("GamePadEmulateAlt")
											if (padAlt == "" or padAlt == "none") then
												padAlt = nil
											end 
											if (padAlt) then
												mods = mods + 1
											end
										end
										if (ctrl) then
											padCtrl = GetCVar("GamePadEmulateCtrl")
											if (padCtrl == "" or padCtrl == "none") then
												padCtrl = nil
											end 
											if (padCtrl) then
												mods = mods + 1
											end
										end
										if (shift) then
											padShift = GetCVar("GamePadEmulateShift")
											if (padShift == "" or padShift == "none") then
												padShift = nil
											end 
											if (padShift) then
												mods = mods + 1
											end
										end
									end

									local padButton
									if (key:find("PAD1")) then
										padButton = GetMedia("controller-xbox-a")
									elseif (key:find("PAD2")) then
										padButton = GetMedia("controller-xbox-b")
									elseif (key:find("PAD3")) then
										padButton = GetMedia("controller-xbox-x")
									elseif (key:find("PAD4")) then
										padButton = GetMedia("controller-xbox-y")
									end

									if (mods == 0) then
										slot2 = padButton
									elseif (mods == 1) then
										slot2 = padButton
									elseif (mods == 2) then
										slot2 = padButton
										--slot1 = mod2
										--slot3 = mod1
									elseif (mods == 3) then
										slot2 = padButton
										--slot1 = mod3
										--slot3 = mod1
										--slot4 = mod2
									end


									-- Apply the slot textures
									self.GamePadKeySlot1:SetTexture(slot1)

									self.GamePadKeySlot2:SetTexture(slot2)
									--self.GamePadKeySlot2:SetPoint("TOPLEFT", 0, 0)
									--self.GamePadKeySlot2:SetSize(24,24)
									self.GamePadKeySlot2:SetPoint("TOPLEFT", 0, -2)
									self.GamePadKeySlot2:SetSize(22,22)

									self.GamePadKeySlot3:SetTexture(slot3)
									self.GamePadKeySlot4:SetTexture(slot4)

									-- Return empty string to hide regular keybinds.
									return ""
								end
							end

							-- If no pad bind was used, clear out the textures
							self.GamePadKeySlot1:SetTexture("")
							self.GamePadKeySlot2:SetTexture("")
							self.GamePadKeySlot3:SetTexture("")
							self.GamePadKeySlot4:SetTexture("")

							-- Return standard abbreviations if no pad bind was used.
							return self:AbbreviateBindText(key)
						end
						return ""
					end
				}
			},
			{
				parent = nil, ownerKey = "Icon", objectType = "Texture",
				chain = {
					"SetSize", { 44, 44 },
					"SetPosition", { "CENTER", 0, 0 }, 
					"ClearTexture", 
					"SetMask", GetMedia("actionbutton-mask-circular")
				}
			},
			{
				-- If the owner does not have the ownerDependencyKey key, this item will be skipped.
				parent = nil, ownerKey = "Pushed", ownerDependencyKey = "SetPushedTexture", objectType = "Texture",
				chain = {
					"SetSize", { 44, 44 }, 
					"SetDrawLayer", { "ARTWORK", 1 },
					"SetPosition", { "CENTER", 0, 0 },
					"SetMask", GetMedia("actionbutton-mask-circular"),
					"SetColorTexture", { 1, 1, 1, .15 }
				}
			},
			{
				-- If the owner does not have the ownerDependencyKey key, this item will be skipped.
				parent = nil, ownerKey = nil, ownerDependencyKey = "SetPushedTexture",
				chain = {
					"SetPushedTextureKey", "Pushed",
					"SetPushedTextureBlendMode", "ADD",
					"SetPushedTextureDrawLayer", { "ARTWORK", 1 }
				}
			},
			{
				parent = nil, ownerKey = "Flash", objectType = "Texture",
				chain = {
					"SetSize", { 44, 44 },
					"SetPosition", { "CENTER", 0, 0 }, 
					"SetDrawLayer", { "ARTWORK", 2 },
					"SetTexture", [[Interface\ChatFrame\ChatFrameBackground]],
					"SetVertexColor", { 1, 0, 0, .25 },
					"SetMask", GetMedia("actionbutton-mask-circular")
				}
			},
			{
				parent = nil, ownerKey = "Cooldown", objectType = "Frame", objectSubType = "Cooldown",
				chain = {
					"SetSize", { 44, 44 },
					"SetPosition", { "CENTER", 0, 0 }, 
					"SetSwipeTexture", GetMedia("actionbutton-mask-circular"),
					"SetDrawSwipe", true,
					"SetBlingTexture", { GetMedia("blank"), 0, 0, 0 , 0 },
					"SetDrawBling", true
				}
			},
			{
				parent = nil, ownerKey = "ChargeCooldown", objectType = "Frame", objectSubType = "Cooldown",
				chain = {
					"SetSize", { 44, 44 },
					"SetPosition", { "CENTER", 0, 0 }, 
					"SetSwipeTexture", { GetMedia("actionbutton-mask-circular"), 0, 0, 0, .5 },
					"SetSwipeColor", { 0, 0, 0, .5 },
					"SetBlingTexture", { GetMedia("blank"), 0, 0, 0 , 0 },
					"SetDrawSwipe", true,
					"SetDrawBling", false
				}
			},
			{
				parent = nil, ownerKey = "CooldownCount", objectType = "FontString", 
				chain = {
					"SetPosition", { "CENTER", 1, 0 },
					"SetFontObject", GetFont(16, true),
					"SetJustifyH", "CENTER",
					"SetJustifyV", "MIDDLE",
					"SetShadowOffset", { 0, 0 },
					"SetShadowColor", { 0, 0, 0, 1 },
					"SetTextColor", { Colors.highlight[1], Colors.highlight[2], Colors.highlight[3], .85 }
				}
			},
			{
				parent = nil, ownerKey = "Count", objectType = "FontString", 
				chain = {
					"SetPosition", { "BOTTOMRIGHT", -3, 3 },
					"SetFontObject", GetFont(18, true),
					"SetJustifyH", "CENTER",
					"SetJustifyV", "BOTTOM",
					"SetShadowOffset", { 0, 0 },
					"SetShadowColor", { 0, 0, 0, 1 },
					"SetTextColor", { Colors.normal[1], Colors.normal[2], Colors.normal[3], .85 }
				}
			},
			(IsClassic) and {
				parent = nil, ownerKey = "Rank", objectType = "FontString", 
				chain = {
					"SetPosition", { "BOTTOMRIGHT", -3, 3 },
					"SetFontObject", GetFont(18, true),
					"SetJustifyH", "CENTER",
					"SetJustifyV", "BOTTOM",
					"SetShadowOffset", { 0, 0 },
					"SetShadowColor", { 0, 0, 0, 1 },
					"SetTextColor", { Colors.quest.gray[1], Colors.quest.gray[2], Colors.quest.gray[3] }
				}
			} or false,
			{
				parent = nil, ownerKey = "Keybind", objectType = "FontString", 
				chain = {
					"SetPosition", { "TOPLEFT", 5, -5 },
					"SetFontObject", GetFont(15, true),
					"SetJustifyH", "CENTER",
					"SetJustifyV", "BOTTOM",
					"SetShadowOffset", { 0, 0 },
					"SetShadowColor", { 0, 0, 0, 1 },
					"SetTextColor", { Colors.quest.gray[1], Colors.quest.gray[2], Colors.quest.gray[3], .75 }
				}
			},
			{
				parent = nil, ownerKey = "SpellHighlight", objectType = "Frame", 
				chain = {
					"SetPosition", { "CENTER", 0, 0 },
					"SetSize", { 64/(122/256), 64/(122/256) }
				}
			},
			{
				parent = nil, ownerKey = "SpellHighlight,Texture", objectType = "Texture", 
				chain = {
					"SetTexture", GetMedia("actionbutton-spellhighlight"),
					"SetVertexColor", { 255/255, 225/255, 125/255, .75 },
				}
			},
			{
				parent = nil, ownerKey = "SpellAutoCast", objectType = "Frame", 
				chain = {
					"SetPosition", { "CENTER", 0, 0 },
					"SetSize", { 50, 50 }
				}
			},
			{
				parent = nil, ownerKey = "SpellAutoCast,Ants", objectType = "Texture", 
				chain = {
					"SetTexture", GetMedia("actionbutton-ants-small-grid"),
					"SetVertexColor", { Colors.cast[1], Colors.cast[2], Colors.cast[3], 1 },
				}
			},
			{
				parent = nil, ownerKey = "SpellAutoCast,Ants,Anim", objectType = "Animation", 
				chain = {
					"SetSpeed", 1/15,
					"SetGrid", { 512, 512, 96, 96, 25 },
				}
			},

			{
				parent = nil, ownerKey = "SpellAutoCast,Glow", objectType = "Texture", 
				chain = {
					"SetTexture", GetMedia("actionbutton-ants-small-glow-grid"),
					"SetVertexColor", { Colors.cast[1], Colors.cast[2], Colors.cast[3], .25 },
				}
			},
			{
				parent = nil, ownerKey = "SpellAutoCast,Glow,Anim", objectType = "Animation", 
				chain = {
					"SetSpeed", 1/15,
					"SetGrid", { 512, 512, 96, 96, 25 },
				}
			},
	
		}
	},
	{
		type = "CreateWidgets",
		widgets = {
			{
				parent = "self", ownerKey = "Backdrop", objectType = "Texture",
				chain = {
					"SetSize", { 64/(122/256), 64/(122/256) },
					"SetPoint", { "CENTER", 0, 0 },
					"SetDrawLayer", { "BACKGROUND", 1 },
					"SetVertexColor", { 2/3, 2/3, 2/3, 1 },
					"SetTexture", GetMedia("actionbutton-backdrop")
				}
			},
			{
				-- If the owner does not have the ownerDependencyKey key, this item will be skipped.
				parent = "self", ownerKey = "Checked", ownerDependencyKey = "SetCheckedTexture", objectType = "Texture",
				chain = {
					"SetDrawLayer", { "ARTWORK", 2 },
					"SetSize", { 44, 44 },
					"SetPosition", { "CENTER", 0, 0 },
					"SetMask", GetMedia("actionbutton-mask-circular"),
					"SetColorTexture", { .9, .8, .1, .3 }
				}
			},
			{
				-- If the owner does not have the ownerDependencyKey key, this item will be skipped.
				ownerDependencyKey = "SetCheckedTexture",
				chain = {
					"SetCheckedTextureKey", "Checked",
					"SetCheckedTextureBlendMode", "ADD",
					"SetCheckedTextureDrawLayer", { "ARTWORK", 1 }
				},
			},
			{
				parent = "self", ownerKey = "Darken", objectType = "Texture",
				chain = {
					"SetDrawLayer", { "BACKGROUND", 3 },
					"SetSize", { 44, 44 },
					"SetAllPointsToParentKey", "Icon",
					"SetMask", GetMedia("actionbutton-mask-circular"),
					"SetTexture", [=[Interface\ChatFrame\ChatFrameBackground]=],
					"SetVertexColor", { 0, 0, 0, .15 }
				}
			},
			{
				parent = "self", ownerKey = "BorderFrame", objectType = "Frame", objectSubType = "Frame",
				chain = {
					"SetFrameLevelOffset", 5,
					"SetAllPointsToParent"
				}
			},
			{
				parent = "self,BorderFrame", ownerKey = "Border", objectType = "Texture",
				chain = {
					"SetPoint", { "CENTER", 0, 0 },
					"SetDrawLayer", { "BORDER", 1 },
					"SetSize", { 64/(122/256), 64/(122/256) },
					"SetTexture", GetMedia("actionbutton-border"),
					"SetVertexColor", { Colors.ui[1], Colors.ui[2], Colors.ui[3], 1 }
				}
			},
			{
				parent = "self,BorderFrame", ownerKey = "GamePadKeySlot1", objectType = "Texture",
				chain = {
					"SetPoint",  { "TOPLEFT", 5-18, -5 },
					"SetDrawLayer", { "BORDER", 2 },
					"SetSize", { 18, 18 },
				}
			},
			{
				parent = "self,BorderFrame", ownerKey = "GamePadKeySlot2", objectType = "Texture",
				chain = {
					"SetPoint",  { "TOPLEFT", 5, -5 },
					"SetDrawLayer", { "BORDER", 2 },
					"SetSize", { 18, 18 },
				}
			},
			{
				parent = "self,BorderFrame", ownerKey = "GamePadKeySlot3", objectType = "Texture",
				chain = {
					"SetPoint",  { "TOPLEFT", 5-18, -5-18 },
					"SetDrawLayer", { "BORDER", 2 },
					"SetSize", { 18, 18 },
				}
			},
			{
				parent = "self,BorderFrame", ownerKey = "GamePadKeySlot4", objectType = "Texture",
				chain = {
					"SetPoint",  { "TOPLEFT", 5, -5-18 },
					"SetDrawLayer", { "BORDER", 2 },
					"SetSize", { 18, 18 },
				}
			},
			{
				parent = "self,Overlay", ownerKey = "Glow", objectType = "Texture",
				chain = {
					"SetHidden",
					"SetDrawLayer", { "ARTWORK", 1 },
					"SetSize", { 44/(122/256),44/(122/256) },
					"SetPoint", { "CENTER", 0, 0 },
					"SetTexture", GetMedia("actionbutton-glow-white"),
					"SetVertexColor", { 1, 1, 1, .5 },
					"SetBlendMode", "ADD"
				}
			}

		}
	}
})

-- Applied to pet-, stance- and additional bars action buttons.
Private.RegisterSchematic("WidgetForge::ActionButton::Small", "Azerite", {
	{
		-- Only set the parent in modifiable widgets if it is your intention to change it.
		-- Otherwise the code will assume the owner is the parent, and leave it as is,
		-- which is what we want in the majority of cases.
		type = "ModifyWidgets",
		widgets = {
			{
				-- Note that a missing ownerKey or parentKey
				-- will apply these changes to the original object instead.
				parent = nil, ownerKey = nil, 
				chain = {
					"SetSize", { 48, 48 }, 
					"SetHitBox", { -4, -4, -4, -4 }
				},
				values = {
					"colors", Colors,
					"maxDisplayCount", 99,
					"PostUpdateCount", PostUpdateStackCount,
					"PostUpdateCooldown", function(self, cooldownObject) 
						cooldownObject:SetSwipeColor(0, 0, 0, .75)
					end,
					"PostUpdateChargeCooldown", function(self, cooldownObject) 
						cooldownObject:SetSwipeColor(0, 0, 0, .5)
					end,
					"PostEnter", PostUpdateMouseOver,
					"PostLeave", PostUpdateMouseOver,
					"PostUpdate", PostUpdateMouseOver
				}
			},
			{
				parent = nil, ownerKey = "Icon", objectType = "Texture",
				chain = {
					"SetSize", { 33, 33 },
					"SetPosition", { "CENTER", 0, 0 }, 
					"ClearTexture", 
					"SetMask", GetMedia("actionbutton-mask-circular")
				}
			},
			{
				-- If the owner does not have the ownerDependencyKey key, this item will be skipped.
				parent = nil, ownerKey = "Pushed", ownerDependencyKey = "SetPushedTexture", objectType = "Texture",
				chain = {
					"SetSize", { 33, 33 }, 
					"SetDrawLayer", { "ARTWORK", 1 },
					"SetPosition", { "CENTER", 0, 0 },
					"SetMask", GetMedia("actionbutton-mask-circular"),
					"SetColorTexture", { 1, 1, 1, .15 }
				}
			},
			{
				-- If the owner does not have the ownerDependencyKey key, this item will be skipped.
				parent = nil, ownerKey = nil, ownerDependencyKey = "SetPushedTexture",
				chain = {
					"SetPushedTextureKey", "Pushed",
					"SetPushedTextureMask", GetMedia("actionbutton-mask-circular"),
					"SetPushedTextureBlendMode", "ADD",
					"SetPushedTextureDrawLayer", { "ARTWORK", 1 }
				}
			},
			{
				parent = nil, ownerKey = "Flash", objectType = "Texture",
				chain = {
					"SetSize", { 33, 33 },
					"SetPosition", { "CENTER", 0, 0 }, 
					"SetDrawLayer", { "ARTWORK", 2 },
					"SetTexture", [=[Interface\ChatFrame\ChatFrameBackground]=],
					"SetVertexColor", { 1, 0, 0, .25 },
					"SetMask", GetMedia("actionbutton-mask-circular")
				}
			},
			{
				parent = nil, ownerKey = "Cooldown", objectType = "Frame", objectSubType = "Cooldown",
				chain = {
					"SetSize", { 33, 33 },
					"SetPosition", { "CENTER", 0, 0 }, 
					"SetSwipeTexture", GetMedia("actionbutton-mask-circular"),
					"SetDrawSwipe", true,
					"SetBlingTexture", { GetMedia("blank"), 0, 0, 0 , 0 },
					"SetDrawBling", true
				}
			},
			{
				parent = nil, ownerKey = "ChargeCooldown", objectType = "Frame", objectSubType = "Cooldown",
				chain = {
					"SetSize", { 33, 33 },
					"SetPosition", { "CENTER", 0, 0 }, 
					"SetSwipeTexture", { GetMedia("actionbutton-mask-circular"), 0, 0, 0, .5 },
					"SetSwipeColor", { 0, 0, 0, .5 },
					"SetBlingTexture", { GetMedia("blank"), 0, 0, 0 , 0 },
					"SetDrawSwipe", true,
					"SetDrawBling", false
				}
			},
			{
				parent = nil, ownerKey = "CooldownCount", objectType = "FontString", 
				chain = {
					"SetPosition", { "CENTER", 1, 0 },
					"SetFontObject", GetFont(16, true),
					"SetJustifyH", "CENTER",
					"SetJustifyV", "MIDDLE",
					"SetShadowOffset", { 0, 0 },
					"SetShadowColor", { 0, 0, 0, 1 },
					"SetTextColor", { Colors.highlight[1], Colors.highlight[2], Colors.highlight[3], .85 }
				}
			},
			{
				parent = nil, ownerKey = "Count", objectType = "FontString", 
				chain = {
					"SetPosition", { "BOTTOMRIGHT", -3, 3 },
					"SetFontObject", GetFont(11, true),
					"SetJustifyH", "CENTER",
					"SetJustifyV", "BOTTOM",
					"SetShadowOffset", { 0, 0 },
					"SetShadowColor", { 0, 0, 0, 1 },
					"SetTextColor", { Colors.normal[1], Colors.normal[2], Colors.normal[3], .85 }
				}
			},
			{
				parent = nil, ownerKey = "Keybind", objectType = "FontString", 
				chain = {
					"SetPosition", { "TOPLEFT", 5, -5 },
					"SetFontObject", GetFont(12, true),
					"SetJustifyH", "CENTER",
					"SetJustifyV", "BOTTOM",
					"SetShadowOffset", { 0, 0 },
					"SetShadowColor", { 0, 0, 0, 1 },
					"SetTextColor", { Colors.quest.gray[1], Colors.quest.gray[2], Colors.quest.gray[3], .75 }
				}
			},
			--[[
			{
				parent = nil, ownerKey = "SpellHighlight", objectType = "Frame", 
				chain = {
					"SetPosition", { "CENTER", 0, 0 },
					"SetSize", { 48/(122/256), 48/(122/256) }
				}
			},
			{
				parent = nil, ownerKey = "SpellHighlight,Texture", objectType = "Texture", 
				chain = {
					"SetTexture", GetMedia("actionbutton-spellhighlight"),
					"SetVertexColor", { 255/255, 225/255, 125/255, .75 },
				}
			},
			--]]--
			{
				parent = nil, ownerKey = "SpellAutoCast", objectType = "Frame", 
				chain = {
					"SetPosition", { "CENTER", 0, 0 },
					"SetSize", { 37.5, 37.5 }
				}
			},
			{
				parent = nil, ownerKey = "SpellAutoCast,Ants", objectType = "Texture", 
				chain = {
					"SetTexture", GetMedia("actionbutton-ants-small-grid"),
					"SetVertexColor", { Colors.cast[1], Colors.cast[2], Colors.cast[3], 1 },
				}
			},
			{
				parent = nil, ownerKey = "SpellAutoCast,Ants,Anim", objectType = "Animation", 
				chain = {
					"SetSpeed", 1/15,
					"SetGrid", { 512, 512, 96, 96, 25 },
				}
			},

			{
				parent = nil, ownerKey = "SpellAutoCast,Glow", objectType = "Texture", 
				chain = {
					"SetTexture", GetMedia("actionbutton-ants-small-glow-grid"),
					"SetVertexColor", { Colors.cast[1], Colors.cast[2], Colors.cast[3], .25 },
				}
			},
			{
				parent = nil, ownerKey = "SpellAutoCast,Glow,Anim", objectType = "Animation", 
				chain = {
					"SetSpeed", 1/15,
					"SetGrid", { 512, 512, 96, 96, 25 },
				}
			},

		}
	},
	{
		type = "CreateWidgets",
		widgets = {
			{
				parent = "self", ownerKey = "Backdrop", objectType = "Texture",
				chain = {
					"SetSize", { 48/(122/256), 48/(122/256) },
					"SetPoint", { "CENTER", 0, 0 },
					"SetDrawLayer", { "BACKGROUND", 1 },
					"SetVertexColor", { 2/3, 2/3, 2/3, 1 },
					"SetTexture", GetMedia("actionbutton-backdrop")
				}
			},
			{
				-- If the owner does not have the ownerDependencyKey key, this item will be skipped.
				parent = "self", ownerKey = "Checked", ownerDependencyKey = "SetCheckedTexture", objectType = "Texture",
				chain = {
					"SetDrawLayer", { "ARTWORK", 2 },
					"SetSize", { 33, 33 },
					"SetPosition", { "CENTER", 0, 0 },
					"SetMask", GetMedia("actionbutton-mask-circular"),
					"SetColorTexture", { .9, .8, .1, .3 }
				}
			},
			{
				-- If the owner does not have the ownerDependencyKey key, this item will be skipped.
				ownerDependencyKey = "SetCheckedTexture",
				chain = {
					"SetCheckedTextureKey", "Checked",
					"SetCheckedTextureMask", GetMedia("actionbutton-mask-circular"),
					"SetCheckedTextureBlendMode", "ADD",
					"SetCheckedTextureDrawLayer", { "ARTWORK", 1 }
				},
			},
			{
				parent = "self", ownerKey = "Darken", objectType = "Texture",
				chain = {
					"SetDrawLayer", { "BACKGROUND", 3 },
					"SetSize", { 33, 33 },
					"SetAllPointsToParentKey", "Icon",
					"SetMask", GetMedia("actionbutton-mask-circular"),
					"SetTexture", [=[Interface\ChatFrame\ChatFrameBackground]=],
					"SetVertexColor", { 0, 0, 0, .15 }
				}
			},
			{
				parent = "self", ownerKey = "BorderFrame", objectType = "Frame", objectSubType = "Frame",
				chain = {
					"SetFrameLevelOffset", 5,
					"SetAllPointsToParent"
				}
			},
			{
				-- Note that the "Border" object already exists, 
				-- so to avoid problems related to that, 
				-- we chose to simply rename our own custom element instead.
				parent = "self,BorderFrame", ownerKey = "ButtonBorder", objectType = "Texture",
				chain = {
					"SetPosition", { "CENTER", 0, 0 },
					"SetDrawLayer", { "BORDER", 1 },
					"SetSize", { 48/(122/256), 48/(122/256) },
					"SetTexture", GetMedia("actionbutton-border"),
					"SetVertexColor", { Colors.ui[1], Colors.ui[2], Colors.ui[3], 1 }
				}
			},
			{
				parent = "self,Overlay", ownerKey = "Glow", objectType = "Texture",
				chain = {
					"SetHidden",
					"SetDrawLayer", { "ARTWORK", 1 },
					"SetSize", { 33/(122/256), 33/(122/256) },
					"SetPoint", { "CENTER", 0, 0 },
					"SetTexture", GetMedia("actionbutton-glow-white"),
					"SetVertexColor", { 1, 1, 1, .5 },
					"SetBlendMode", "ADD"
				}
			}					
		}
	}
})