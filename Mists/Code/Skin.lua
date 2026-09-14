--[[----------------------------------------------------------------------------
	Parrot 3 - fork of Parrot 2 by Neb (https://github.com/nebularg/Parrot2),
	itself based on the original Parrot by ckknight.
	Licensed under the GNU Lesser General Public License v2.1 - see LICENSE.txt.

	NEW in the Parrot 3 fork on 2026-09-10:
	  A cosmetic skin for the AceGUI-3.0 widgets used by the options window.
	  It only restyles frames/textures/fonts - the config itself is still built
	  and driven by AceConfigDialog, so every feature (the "+" side tabs, the
	  dynamic option lists, live preview, ...) keeps working exactly as before.
	  Nothing here touches saved variables or Parrot's own modules.
------------------------------------------------------------------------------]]
local _, ns = ...
local Parrot = ns.addon
if not Parrot then return end

local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
if not AceGUI then return end

----------------------------------------------------------------------
-- Palette & fonts
----------------------------------------------------------------------
local ACCENT      = { 0.30, 0.78, 0.55 }   -- #4DC78D  parrot green
local C = {
	accent      = ACCENT,
	accentFade  = { ACCENT[1], ACCENT[2], ACCENT[3], 0.16 },
	window      = { 0.067, 0.070, 0.078, 0.97 },
	rail        = { 0.090, 0.094, 0.104, 1 },
	panel       = { 0.118, 0.122, 0.134, 1 },
	panelHi     = { 0.165, 0.170, 0.185, 1 },
	input       = { 0.055, 0.058, 0.065, 1 },
	button      = { 0.150, 0.155, 0.170, 1 },
	buttonHi    = { 0.205, 0.210, 0.230, 1 },
	border      = { 0, 0, 0, 0.90 },
	borderSoft  = { 1, 1, 1, 0.055 },
	text        = { 0.88, 0.89, 0.91 },
	textDim     = { 0.52, 0.53, 0.57 },
}
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function mkfont(name, size, flags, col)
	local f = CreateFont("Parrot3Font_" .. name)
	f:SetFont(STANDARD_TEXT_FONT, size, flags or "")
	f:SetTextColor(unpack(col or C.text))
	f:SetShadowColor(0, 0, 0, 0.9)
	f:SetShadowOffset(1, -1)
	return f
end
local F = {
	title  = mkfont("Title", 15, "", C.accent),
	normal = mkfont("Normal", 12),
	small  = mkfont("Small", 11, "", C.textDim),
	header = mkfont("Header", 11, "OUTLINE", C.accent),
	label  = mkfont("Label", 11, "", C.accent),   -- control labels, was gold
}

local function greenLabel(fs)
	if fs and fs.SetFontObject then
		fs:SetFontObject(F.label)
		fs:SetTextColor(unpack(C.accent))
	end
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function stripTextures(frame, keep)
	if not frame then return end
	if frame.SetBackdrop then pcall(frame.SetBackdrop, frame, nil) end
	for _, r in next, { frame:GetRegions() } do
		if r ~= keep and r.GetObjectType and r:GetObjectType() == "Texture" then
			r:SetTexture(nil)
			if r.SetAtlas then r:SetAtlas(nil) end
			r:SetAlpha(0)
		end
	end
end

-- Flat fill + hairline 1px border, drawn with plain textures (works on every client).
local function flat(frame, col, borderCol)
	if not frame or frame.__pskin then return frame and frame.__pskin end
	col = col or C.panel
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(frame)
	bg:SetColorTexture(col[1], col[2], col[3], col[4] or 1)

	local bc = borderCol or C.border
	local edges = {}
	local defs = {
		{ "TOPLEFT", "TOPRIGHT", 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 1 },
		{ "TOPLEFT", "BOTTOMLEFT", 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 0 },
	}
	for _, d in next, defs do
		local t = frame:CreateTexture(nil, "BORDER")
		t:SetColorTexture(bc[1], bc[2], bc[3], bc[4] or 1)
		t:SetPoint(d[1]); t:SetPoint(d[2])
		if d[3] == 1 then t:SetHeight(1) else t:SetWidth(1) end
		edges[#edges + 1] = t
	end
	frame.__pskin = { bg = bg, edges = edges }
	return frame.__pskin
end

local function setFill(frame, col)
	if frame and frame.__pskin then
		frame.__pskin.bg:SetColorTexture(col[1], col[2], col[3], col[4] or 1)
	end
end

local function fontify(fs, font)
	if fs and fs.SetFontObject then fs:SetFontObject(font or F.normal) end
end

-- Kill a template button's art, give it a flat look with an accent hover.
local function skinButton(b, small)
	if not b or b.__pskin then return end
	stripTextures(b)
	for _, key in next, { "Left", "Middle", "Right", "TopLeft", "TopRight",
		"BottomLeft", "BottomRight", "TopMiddle", "BottomMiddle", "MiddleLeft",
		"MiddleRight", "MiddleMiddle" } do
		local t = b[key]
		if t and t.SetAlpha then t:SetAlpha(0) end
	end
	if b.SetNormalTexture then pcall(b.SetNormalTexture, b, nil) end
	if b.SetPushedTexture then pcall(b.SetPushedTexture, b, nil) end
	if b.SetDisabledTexture then pcall(b.SetDisabledTexture, b, nil) end
	if b.SetHighlightTexture then pcall(b.SetHighlightTexture, b, nil) end
	flat(b, C.button)
	local fs = b.GetFontString and b:GetFontString()
	fontify(fs, small and F.small or F.normal)
	if fs then fs:SetTextColor(unpack(C.text)) end
	b:HookScript("OnEnter", function(s) setFill(s, C.buttonHi); if s:GetFontString() then s:GetFontString():SetTextColor(unpack(C.accent)) end end)
	b:HookScript("OnLeave", function(s) setFill(s, C.button); if s:GetFontString() then s:GetFontString():SetTextColor(unpack(C.text)) end end)
end

-- Slim, dark scrollbar (UIPanelScrollBarTemplate or a bare Slider).
local function skinScrollBar(bar)
	if not bar or bar.__pskin then return end
	local name = bar.GetName and bar:GetName()
	if name then
		for _, sfx in next, { "ScrollUpButton", "ScrollDownButton" } do
			local btn = _G[name .. sfx]
			if btn then
				btn:SetAlpha(0); btn:EnableMouse(false)
				btn:SetSize(1, 1)
			end
		end
	end
	if bar.ScrollUpButton then bar.ScrollUpButton:SetAlpha(0); bar.ScrollUpButton:SetSize(1, 1) end
	if bar.ScrollDownButton then bar.ScrollDownButton:SetAlpha(0); bar.ScrollDownButton:SetSize(1, 1) end
	stripTextures(bar)
	bar:SetWidth(6)
	local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
	if thumb then
		thumb:SetTexture(WHITE)
		thumb:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.55)
		thumb:SetAlpha(1)
		thumb:SetSize(6, 40)
	end
	local track = bar:CreateTexture(nil, "BACKGROUND")
	track:SetColorTexture(1, 1, 1, 0.04)
	track:SetPoint("TOPLEFT"); track:SetPoint("BOTTOMRIGHT")
	bar.__pskin = { track = track }
end

----------------------------------------------------------------------
-- Per-widget skinners
----------------------------------------------------------------------
local S = {}

S.Frame = function(w)
	local f = w.frame
	stripTextures(f)                 -- removes the 32px dialog border + header art
	flat(f, C.window, { 0, 0, 0, 1 })
	-- accent hairline across the very top
	local accentBar = f:CreateTexture(nil, "ARTWORK")
	accentBar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
	accentBar:SetHeight(2)
	accentBar:SetPoint("TOPLEFT", 1, -1)
	accentBar:SetPoint("TOPRIGHT", -1, -1)

	if w.titlebg then w.titlebg:SetTexture(nil); w.titlebg:SetAlpha(0) end
	if w.titletext then
		fontify(w.titletext, F.title)
		w.titletext:SetTextColor(unpack(C.accent))
		w.titletext:ClearAllPoints()
		w.titletext:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -12)
	end
	if w.statustext then w.statustext:SetText(""); w.statustext:Hide() end

	-- close button (skin) + status strip (remove it entirely)
	for _, kid in next, { f:GetChildren() } do
		if kid ~= w.content then
			local txt = kid.GetText and kid:GetText()
			if txt and txt == _G.CLOSE then
				skinButton(kid)
			elseif kid.SetBackdrop then          -- the empty status bar
				pcall(kid.SetBackdrop, kid, nil)
				stripTextures(kid)
				kid:EnableMouse(false)
				kid:SetHeight(0.001)
				kid:SetAlpha(0)
			end
		end
	end
end

S.TreeGroup = function(w)
	stripTextures(w.treeframe)
	flat(w.treeframe, C.rail, C.borderSoft)
	stripTextures(w.border)
	flat(w.border, C.window, C.border)
	if w.scrollbar then skinScrollBar(w.scrollbar) end
	if w.dragger then stripTextures(w.dragger) end

	-- wrap CreateButton so every tree row gets the flat treatment
	local orig = w.CreateButton
	if orig then
		w.CreateButton = function(self)
			local b = orig(self)
			if b and not b.__pskin then
				b.__pskin = true
				stripTextures(b, b.text)

				local hover = b:CreateTexture(nil, "BACKGROUND")
				hover:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.12)
				hover:SetPoint("TOPLEFT", 1, 0); hover:SetPoint("BOTTOMRIGHT", -1, 0)
				hover:Hide()

				local fill = b:CreateTexture(nil, "BACKGROUND")
				fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.16)
				fill:SetPoint("TOPLEFT", 1, 0); fill:SetPoint("BOTTOMRIGHT", -1, 0)
				fill:Hide()

				local bar = b:CreateTexture(nil, "ARTWORK")
				bar:SetColorTexture(unpack(C.accent))
				bar:SetPoint("TOPLEFT"); bar:SetPoint("BOTTOMLEFT")
				bar:SetWidth(2)
				bar:Hide()

				b.__psel = function()
					local on = b.selected
					fill:SetShown(on); bar:SetShown(on)
					if b.text then b.text:SetTextColor(unpack(on and C.accent or C.text)) end
				end
				b:HookScript("OnEnter", function() hover:Show() end)
				b:HookScript("OnLeave", function() hover:Hide() end)
				hooksecurefunc(b, "LockHighlight", function() b.selected = true; b.__psel() end)
				hooksecurefunc(b, "UnlockHighlight", function() b.selected = false; b.__psel() end)
				if b.text then b.text:SetTextColor(unpack(C.text)) end

				-- custom minimalist expand toggle: an accent "+" that loses its
				-- vertical stroke when the node is open (becomes "-")
				local tg = b.toggle
				if tg and not tg.__pskin then
					tg.__pskin = true
					local hbar = tg:CreateTexture(nil, "OVERLAY")
					hbar:SetColorTexture(unpack(C.accent))
					hbar:SetSize(7, 2)
					hbar:SetPoint("CENTER")
					local vbar = tg:CreateTexture(nil, "OVERLAY")
					vbar:SetColorTexture(unpack(C.accent))
					vbar:SetSize(2, 7)
					vbar:SetPoint("CENTER")
					tg.__pv = vbar
					local function repaint(self, tex)
						if tex ~= nil and tex ~= "" then
							local nt = self.GetNormalTexture and self:GetNormalTexture()
							if nt then nt:SetAlpha(0) end
							local pt = self.GetPushedTexture and self:GetPushedTexture()
							if pt then pt:SetAlpha(0) end
							-- 130838 = PlusButton-UP (collapsed)
							self.__pv:SetShown(tex == 130838)
						end
					end
					hooksecurefunc(tg, "SetNormalTexture", repaint)
				end
			end
			return b
		end
	end

	-- AceGUI anchors the row text 2px above centre; pull it back to the middle
	-- of the highlight after every tree refresh.
	local origRefresh = w.RefreshTree
	if origRefresh then
		w.RefreshTree = function(self, ...)
			local r = origRefresh(self, ...)
			for _, b in next, (self.buttons or {}) do
				if b.text then
					local _, _, _, x = b.text:GetPoint(1)
					b.text:ClearAllPoints()
					b.text:SetPoint("LEFT", b, "LEFT", x or 8, 0)
					b.text:SetPoint("RIGHT", b, "RIGHT", -4, 0)
					b.text:SetJustifyV("MIDDLE")
				end
			end
			return r
		end
	end
end

S.TabGroup = function(w)
	if w.border then stripTextures(w.border); flat(w.border, C.window, C.border) end
	if w.titletext then fontify(w.titletext, F.header) end

	local function paint(self)
		for _, tab in next, (self.tabs or {}) do
			if tab.__pUnder then tab.__pUnder:SetShown(tab.selected and true or false) end
			if tab.Text then tab.Text:SetTextColor(unpack(tab.selected and C.accent or C.textDim)) end
		end
	end

	local origCreate = w.CreateTab
	if origCreate then
		w.CreateTab = function(self, id)
			local tab = origCreate(self, id)
			if tab and not tab.__pskin then
				tab.__pskin = true
				for _, k in next, { "Left", "Middle", "Right", "LeftDisabled",
					"MiddleDisabled", "RightDisabled", "LeftHighlight",
					"MiddleHighlight", "RightHighlight" } do
					if tab[k] then tab[k]:SetAlpha(0) end
				end
				local under = tab:CreateTexture(nil, "OVERLAY")
				under:SetColorTexture(unpack(C.accent))
				under:SetHeight(2)
				under:SetPoint("BOTTOMLEFT", 6, 2)
				under:SetPoint("BOTTOMRIGHT", -6, 2)
				under:Hide()
				tab.__pUnder = under
				fontify(tab.Text, F.small)
			end
			return tab
		end
	end

	for _, m in next, { "SelectTab", "BuildTabs", "SetTabs" } do
		local orig = w[m]
		if orig then
			w[m] = function(self, ...)
				local a, b2, c2 = orig(self, ...)
				paint(self)
				return a, b2, c2
			end
		end
	end
end

local function skinGroupBorder(w)
	if w.border then stripTextures(w.border); flat(w.border, C.panel, C.borderSoft) end
	if w.titletext then fontify(w.titletext, F.header); w.titletext:SetTextColor(unpack(C.accent)) end
end
S.InlineGroup = skinGroupBorder
S.DropdownGroup = skinGroupBorder

S.SimpleGroup = function(w)
	if w.scrollbar then skinScrollBar(w.scrollbar) end
end
S.ScrollFrame = function(w)
	if w.scrollbar then skinScrollBar(w.scrollbar) end
end

-- Custom checkbox: a flat square that fills with the accent when checked.
-- The Blizzard textures are hidden entirely.
local function hideNativeCheck(w)
	for _, t in next, { w.checkbg, w.check, w.highlight } do
		if t then t:SetTexture(nil); if t.SetAtlas then t:SetAtlas(nil) end; t:SetAlpha(0) end
	end
end

S.CheckBox = function(w)
	hideNativeCheck(w)
	if w.frame and not w.frame.__pcb then
		w.frame.__pcb = true
		local box = CreateFrame("Frame", nil, w.frame)
		box:SetSize(16, 16)
		box:SetPoint("LEFT", w.frame, "LEFT", 3, 0)
		flat(box, C.input, { 1, 1, 1, 0.20 })

		local fill = box:CreateTexture(nil, "ARTWORK")
		fill:SetColorTexture(unpack(C.accent))
		fill:SetPoint("TOPLEFT", 3, -3)
		fill:SetPoint("BOTTOMRIGHT", -3, 3)
		fill:Hide()

		local hi = box:CreateTexture(nil, "ARTWORK")
		hi:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.14)
		hi:SetAllPoints(box)
		hi:Hide()
		w.frame:HookScript("OnEnter", function() hi:Show() end)
		w.frame:HookScript("OnLeave", function() hi:Hide() end)

		w.__pfill, w.__pbox = fill, box
	end
	fontify(w.text, F.normal)

	local function sync(self)
		local fill = self.__pfill
		if not fill then return end
		if self.checked == true then
			fill:Show(); fill:SetAlpha(1)
		elseif self.checked == nil and self.tristate then
			fill:Show(); fill:SetAlpha(0.4)
		else
			fill:Hide()
		end
	end
	for _, m in next, { "SetValue", "SetTriState", "SetType" } do
		local orig = w[m]
		if orig then
			w[m] = function(self, ...)
				local r = orig(self, ...)
				hideNativeCheck(self)
				sync(self)
				return r
			end
		end
	end
	local origDis = w.SetDisabled
	if origDis then
		w.SetDisabled = function(self, disabled)
			origDis(self, disabled)
			if self.__pbox then self.__pbox:SetAlpha(disabled and 0.4 or 1) end
		end
	end
end

-- box + hairline border drawn as parent-frame textures (stay behind the
-- dropdown's own child frames, so the value text/arrow keep showing)
-- box + hairline border as parent-frame textures. `top`/`bottom` are y-offsets
-- from the parent's top/bottom edges (top negative), so the box can clear a label.
local function boxTextures(parent, inset, top, bottom)
	local bar = parent:CreateTexture(nil, "BACKGROUND")
	bar:SetColorTexture(unpack(C.input))
	bar:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, top)
	bar:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, bottom)
	local defs = {
		{ "TOPLEFT", "TOPRIGHT", 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 1 },
		{ "TOPLEFT", "BOTTOMLEFT", 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 0 },
	}
	for _, d in next, defs do
		local e = parent:CreateTexture(nil, "BORDER")
		e:SetColorTexture(1, 1, 1, 0.12)
		e:SetPoint(d[1], bar, d[1]); e:SetPoint(d[2], bar, d[2])
		if d[3] == 1 then e:SetHeight(1) else e:SetWidth(1) end
	end
	return bar
end

-- a small accent chevron drawn from two rotated bars
local function chevron(parent)
	local function stroke(rot, dx)
		local t = parent:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(unpack(C.accent))
		t:SetSize(7, 2)
		t:SetPoint("CENTER", parent, "CENTER", dx, 1)
		t:SetRotation(rot)
		return t
	end
	return stroke(-0.7854, -2.4), stroke(0.7854, 2.4)
end

S.Dropdown = function(w)
	local dd = w.dropdown
	if dd then
		local name = dd.GetName and dd:GetName()
		for _, sfx in next, { "Left", "Middle", "Right" } do
			local t = name and _G[name .. sfx]
			if t and t.SetAlpha then t:SetAlpha(0) end
		end
	end

	if w.frame and not w.frame.__pdd then
		w.frame.__pdd = true
		local function place(self)
			if not self.__pddbar then
				self.__pddbar = boxTextures(self.frame, 3, -1, 1)
			end
			local labelled = self.label and self.label:IsShown()
			self.__pddbar:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 3, labelled and -22 or -1)
			if self.text then
				self.text:ClearAllPoints()
				self.text:SetPoint("LEFT", self.__pddbar, "LEFT", 8, 0)
				self.text:SetPoint("RIGHT", self.__pddbar, "RIGHT", -20, 0)
				self.text:SetJustifyH("LEFT")
			end
			if self.button then
				self.button:ClearAllPoints()
				self.button:SetPoint("RIGHT", self.__pddbar, "RIGHT", -4, 0)
				self.button:SetSize(16, 16)
			end
		end
		local origLabel = w.SetLabel
		if origLabel then
			w.SetLabel = function(self, ...) local r = origLabel(self, ...) place(self) return r end
		end
		place(w)
	end

	-- custom chevron instead of the gold arrow
	if w.button and not w.button.__pchev then
		w.button.__pchev = true
		for _, r in next, { w.button:GetRegions() } do
			if r.GetObjectType and r:GetObjectType() == "Texture" then r:SetAlpha(0) end
		end
		for _, m in next, { "SetNormalTexture", "SetPushedTexture", "SetDisabledTexture", "SetHighlightTexture" } do
			if w.button[m] then pcall(w.button[m], w.button, nil) end
		end
		local a, b = chevron(w.button)
		w.__chevA, w.__chevB = a, b
		w.button:HookScript("OnEnter", function() if not w.__ddDisabled then a:SetColorTexture(1, 1, 1, 0.9); b:SetColorTexture(1, 1, 1, 0.9) end end)
		w.button:HookScript("OnLeave", function() w.__paintChev() end)
	end

	w.__paintChev = function()
		local col = w.__ddDisabled and { 0.38, 0.38, 0.42 } or C.accent
		if w.__chevA then w.__chevA:SetColorTexture(unpack(col)) end
		if w.__chevB then w.__chevB:SetColorTexture(unpack(col)) end
	end
	local origDis = w.SetDisabled
	if origDis then
		w.SetDisabled = function(self, disabled)
			local r = origDis(self, disabled)
			self.__ddDisabled = disabled and true or false
			self.__paintChev()
			return r
		end
	end

	if w.text then fontify(w.text, F.normal); w.text:SetTextColor(unpack(C.text)) end
	greenLabel(w.label)
end

S["Dropdown-Pullout"] = function(w)
	if w.frame then
		stripTextures(w.frame)
		flat(w.frame, C.panelHi, C.border)
	end
	if w.slider then skinScrollBar(w.slider) end
end

S.Slider = function(w)
	local sl = w.slider
	if sl then
		if sl.SetBackdrop then pcall(sl.SetBackdrop, sl, nil) end
		if not sl.__ptrack then
			sl.__ptrack = true
			local track = sl:CreateTexture(nil, "BACKGROUND")
			track:SetColorTexture(C.input[1], C.input[2], C.input[3], 1)
			track:SetPoint("LEFT", 1, 0)
			track:SetPoint("RIGHT", -1, 0)
			track:SetHeight(3)
		end
		sl:SetThumbTexture(WHITE)
		local thumb = sl:GetThumbTexture()
		if thumb then
			thumb:SetVertexColor(unpack(C.accent))
			thumb:SetSize(6, 12)
			thumb:SetAlpha(1)
		end
	end
	if w.editbox then
		if w.editbox.SetBackdrop then pcall(w.editbox.SetBackdrop, w.editbox, nil) end
		flat(w.editbox, C.input, C.borderSoft)
	end
	greenLabel(w.label)
	fontify(w.lowtext, F.small)
	fontify(w.hightext, F.small)
	-- put the min/max labels on the same line as the value box, clear of the track
	if w.lowtext and w.editbox then
		w.lowtext:ClearAllPoints()
		w.lowtext:SetPoint("RIGHT", w.editbox, "LEFT", -6, 0)
	end
	if w.hightext and w.editbox then
		w.hightext:ClearAllPoints()
		w.hightext:SetPoint("LEFT", w.editbox, "RIGHT", 6, 0)
	end
end

local IBORDER = { 1, 1, 1, 0.22 }   -- visible edge so a text field reads as a text field

S.EditBox = function(w)
	local eb = w.editbox
	local f  = w.frame
	if eb then
		local name = eb.GetName and eb:GetName()
		for _, sfx in next, { "Left", "Middle", "Right" } do
			local t = name and _G[name .. sfx]
			if t then t:SetAlpha(0) end
		end
		stripTextures(eb)
		if eb.SetTextInsets then eb:SetTextInsets(7, 7, 3, 3) end
		flat(eb, { 0.045, 0.048, 0.055, 1 }, IBORDER)

		-- small accent tab on the left edge = "this is an input"
		if not eb.__ptab then
			eb.__ptab = true
			local tab = eb:CreateTexture(nil, "ARTWORK")
			tab:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.55)
			tab:SetWidth(2)
			tab:SetPoint("TOPLEFT", 0, 0); tab:SetPoint("BOTTOMLEFT", 0, 0)
			eb.__ptab = tab
		end

		-- AceGUI keeps re-anchoring the editbox 6-7px in for the old border art;
		-- rewrite any inset TOPLEFT/BOTTOMLEFT back to flush.
		if f and not eb.__phook then
			eb.__phook = true
			hooksecurefunc(eb, "SetPoint", function(self, point, _, _, x, y)
				if self.__pfixing then return end
				if (point == "TOPLEFT" or point == "BOTTOMLEFT") and x and x ~= 0 then
					self.__pfixing = true
					self:SetPoint(point, f, point, 0, y or 0)
					self.__pfixing = false
				end
			end)
		end

		eb:HookScript("OnEditFocusGained", function(s)
			if s.__pskin then for _, e in next, s.__pskin.edges do e:SetColorTexture(unpack(C.accent)) end end
			if s.__ptab then s.__ptab:SetAlpha(1) end
		end)
		eb:HookScript("OnEditFocusLost", function(s)
			if s.__pskin then for _, e in next, s.__pskin.edges do e:SetColorTexture(unpack(IBORDER)) end end
			if s.__ptab then s.__ptab:SetAlpha(0.55) end
		end)
	end

	local function realign(self)
		local e = self.editbox
		if not (e and self.frame) then return end
		local labelled = self.label and self.label:GetText() and self.label:GetText() ~= ""
		e.__pfixing = true
		e:ClearAllPoints()
		e:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, labelled and -18 or 0)
		e:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
		e.__pfixing = false
	end
	for _, m in next, { "SetLabel", "SetText" } do
		local orig = w[m]
		if orig then w[m] = function(self, ...) local r = orig(self, ...) realign(self) return r end end
	end
	realign(w)
	if w.button then skinButton(w.button, true) end
	greenLabel(w.label)
end

S.MultiLineEditBox = function(w)
	if w.scrollBG then
		stripTextures(w.scrollBG)
		flat(w.scrollBG, { 0.045, 0.048, 0.055, 1 }, IBORDER)
		if not w.scrollBG.__ptab then
			w.scrollBG.__ptab = true
			local tab = w.scrollBG:CreateTexture(nil, "ARTWORK")
			tab:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.55)
			tab:SetWidth(2)
			tab:SetPoint("TOPLEFT"); tab:SetPoint("BOTTOMLEFT")
		end
	end
	if w.button then skinButton(w.button, true) end
	if w.scrollBar then skinScrollBar(w.scrollBar) end
	greenLabel(w.label)
end

S.Button = function(w)
	skinButton(w.frame)
end

S.Heading = function(w)
	if w.left then w.left:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5); w.left:SetHeight(1) end
	if w.right then w.right:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5); w.right:SetHeight(1) end
	fontify(w.label, F.header)
	if w.label then w.label:SetTextColor(unpack(C.accent)) end
end

S.ColorPicker = function(w)
	fontify(w.text, F.normal)
	if w.colorSwatch and not w.colorSwatch.__pcp then
		w.colorSwatch.__pcp = true
		local b = CreateFrame("Frame", nil, w.frame)
		b:SetPoint("TOPLEFT", w.colorSwatch, "TOPLEFT", -1, 1)
		b:SetPoint("BOTTOMRIGHT", w.colorSwatch, "BOTTOMRIGHT", 1, -1)
		flat(b, { 0, 0, 0, 0 }, C.border)
	end
end

S.Keybinding = function(w)
	if w.button then skinButton(w.button, true) end
	if w.msgframe then stripTextures(w.msgframe); flat(w.msgframe, C.panelHi, C.accent) end
	greenLabel(w.label)
end

S.Label = function(w) fontify(w.label, F.normal) end
S.InteractiveLabel = function(w) fontify(w.label, F.normal) end
S.Icon = function(w) fontify(w.label, F.small) end

----------------------------------------------------------------------
-- Install: wrap every widget constructor in the registry
----------------------------------------------------------------------
-- Widgets whose `label` fontstring AceGUI paints gold and keeps re-painting
-- (SetDisabled/SetLabel). We force it to the accent green after every such call.
local GOLD_LABEL = {
	Slider = true, Dropdown = true, EditBox = true,
	MultiLineEditBox = true, Keybinding = true, Heading = true,
}

local function forceGreenLabel(widget)
	local fs = widget.label
	if not fs then return end
	greenLabel(fs)
	local function repaint(self, disabled)
		if not self.label then return end
		if disabled then
			self.label:SetTextColor(0.45, 0.45, 0.48)
		else
			self.label:SetTextColor(unpack(C.accent))
		end
	end
	for _, m in next, { "SetDisabled", "SetLabel", "SetText" } do
		local orig = widget[m]
		if orig then
			widget[m] = function(self, a, ...)
				local r = orig(self, a, ...)
				repaint(self, m == "SetDisabled" and a or self.disabled)
				return r
			end
		end
	end
end

local function wrap(wtype, ctor)
	local greenit = GOLD_LABEL[wtype]
	return function(...)
		local widget = ctor(...)
		if widget and not widget.__parrotSkinned then
			widget.__parrotSkinned = true
			local skinner = S[wtype]
			if skinner then pcall(skinner, widget) end
			if greenit then pcall(forceGreenLabel, widget) end
		end
		return widget
	end
end

local reg = AceGUI.WidgetRegistry
if reg then
	for wtype, ctor in next, reg do
		if (S[wtype] or GOLD_LABEL[wtype]) and type(ctor) == "function" then
			reg[wtype] = wrap(wtype, ctor)
		end
	end
end

hooksecurefunc(AceGUI, "RegisterWidgetType", function(self, name, ctor)
	local r = self.WidgetRegistry
	if (S[name] or GOLD_LABEL[name]) and r and r[name] == ctor and type(ctor) == "function" then
		r[name] = wrap(name, ctor)
	end
end)

----------------------------------------------------------------------
-- Small UI toolkit shared with About.lua (Changelog / About popups)
----------------------------------------------------------------------
local UI = {}
Parrot.ui = UI
UI.C, UI.F, UI.WHITE = C, F, WHITE

function UI.Flat(frame, col, borderCol)
	frame.__pskin = nil
	return flat(frame, col, borderCol)
end

function UI.Panel(parent, col, borderCol)
	local f = CreateFrame("Frame", nil, parent)
	flat(f, col or C.panel, borderCol or C.borderSoft)
	return f
end

-- A window in the Parrot 3 style: accent top bar, title, close-x, ESC + drag.
function UI.Window(name, w, h, title)
	local f = CreateFrame("Frame", name, UIParent)
	f:SetSize(w, h)
	f:SetPoint("CENTER")
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()
	flat(f, C.window, { 0, 0, 0, 1 })
	if name then tinsert(_G.UISpecialFrames, name) end

	local bar = f:CreateTexture(nil, "ARTWORK")
	bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
	bar:SetHeight(2)
	bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("TOPRIGHT", -1, -1)

	local t = f:CreateFontString(nil, "OVERLAY")
	t:SetFontObject(F.title)
	t:SetPoint("TOPLEFT", 16, -13)
	t:SetText(title or "")
	f.title = t

	local x = CreateFrame("Button", nil, f)
	x:SetSize(22, 22)
	x:SetPoint("TOPRIGHT", -10, -9)
	local xt = x:CreateFontString(nil, "OVERLAY")
	xt:SetFontObject(F.title)
	xt:SetPoint("CENTER")
	xt:SetText("\195\151")   -- ×
	xt:SetTextColor(unpack(C.textDim))
	x:SetScript("OnEnter", function() xt:SetTextColor(unpack(C.accent)) end)
	x:SetScript("OnLeave", function() xt:SetTextColor(unpack(C.textDim)) end)
	x:SetScript("OnClick", function() f:Hide() end)

	local div = f:CreateTexture(nil, "ARTWORK")
	div:SetColorTexture(1, 1, 1, 0.07)
	div:SetHeight(1)
	div:SetPoint("TOPLEFT", 12, -38); div:SetPoint("TOPRIGHT", -12, -38)

	return f
end

-- Flat push-button in the Parrot 3 style.
function UI.Button(parent, text, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width or 90, 22)
	flat(b, C.button, C.borderSoft)
	local fs = b:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(F.normal)
	fs:SetPoint("CENTER")
	fs:SetText(text or "")
	b.text = fs
	b:SetScript("OnEnter", function(s) setFill(s, C.buttonHi); fs:SetTextColor(unpack(C.accent)) end)
	b:SetScript("OnLeave", function(s) setFill(s, C.button); fs:SetTextColor(unpack(C.text)) end)
	return b
end

-- Read-only, click-to-select field (for links).
function UI.LinkField(parent, value)
	local e = CreateFrame("EditBox", nil, parent)
	e:SetAutoFocus(false)
	e:SetFontObject(F.small)
	e:SetHeight(18)
	e:SetText(value or "")
	e:SetCursorPosition(0)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	e:SetScript("OnEnterPressed", e.ClearFocus)
	e:SetScript("OnEditFocusGained", function(s) s:HighlightText() end)
	e:SetScript("OnEditFocusLost", function(s) s:HighlightText(0, 0); s:SetCursorPosition(0) end)
	e:SetScript("OnKeyDown", function() end)
	flat(e, C.input, C.borderSoft)
	if e.SetTextInsets then e:SetTextInsets(6, 6, 2, 2) end
	return e
end

Parrot.skinAccent = C.accent
