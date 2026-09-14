--[[----------------------------------------------------------------------------
	Parrot 3 - fork of Parrot 2 by Neb (https://github.com/nebularg/Parrot2),
	itself based on the original Parrot by ckknight.
	Licensed under the GNU Lesser General Public License v2.1 - see LICENSE.txt.

	NEW in the Parrot 3 fork on 2026-09-10:
	  The "Changelog" and "About" buttons at the bottom-left of the options
	  window, and the two custom popups they open. Pure UI, no saved variables.
------------------------------------------------------------------------------]]
local _, ns = ...
local Parrot = ns.addon
if not Parrot then return end

local L = LibStub("AceLocale-3.0"):GetLocale("Parrot")
local UI = Parrot.ui
if not UI then return end
local C, F = UI.C, UI.F

----------------------------------------------------------------------
-- Content
----------------------------------------------------------------------
local VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Parrot3", "Version"))
	or (GetAddOnMetadata and GetAddOnMetadata("Parrot3", "Version")) or "v3.0.0"

local G = "|cff4dc78d"   -- accent green
local X = "|r"
local D = "|cff808080"   -- dim

local CHANGELOG = [[
]] .. G .. [[v3.0.0  (2026-09-10)]] .. X .. [[

The first Parrot 3 release. Parrot 3 is a maintained fork of Parrot 2 by Neb,
itself based on the original Parrot by ckknight. Fork maintainer: NeRgY.
Licensed under the GNU LGPL v2.1, the same as upstream.

]] .. G .. [[1. One addon, four game versions]] .. X .. [[

Parrot 2 shipped as two disconnected builds. Parrot 3 merges them into one
addon with a dedicated TOC and a fully separate code tree per version:
  - Mainline  - Retail 12.1.0 / 12.1.5   (Interface 120100, 120105)
  - Vanilla   - Classic Era 1.15.9       (11509)
  - TBC       - TBC Classic 2.5.6        (20506)
  - Mists     - MoP Classic 5.5.4        (50504)
Libs, Locales and locales.xml are shared. All internal names stay "Parrot",
so your ParrotDB settings and profiles carry over unchanged. Mists also takes
the Retail trigger system (spec-based default triggers, focus unit, spell
overlay) with a C_Spell fallback for MoP's older spell API.
Removed the leftover Classic/ and Retail/ source folders.

]] .. G .. [[2. Licensing]] .. X .. [[

LICENSE.txt (LGPL v2.1) and X-License kept. Credits kept: ckknight, profalbert,
nebularg; Author / X-Fork-Maintainer set to NeRgY. Upstream Curse / WoWI IDs
removed. Every changed file carries an LGPL v2.1 change notice.

]] .. G .. [[3. Bug fixes and optimisations]] .. X .. [[

- Retail: screen flash restored - the flash frame lost its BackdropTemplate in
  Neb's retail build, which errored on 9.0+. Backdrop alpha 255 -> 1 everywhere.
- Item name / icon fall back to the link text when the client hasn't cached the
  item yet (Loot, Cooldowns, Point gains) instead of erroring or showing blank.
- Combat-log handler: reject untracked events and irrelevant units before the
  flag math, and only build the info table once a check passes.
- TriggerCombatEvent: the 5 runtime guards debug() + return instead of error(),
  so a bad call can't break event dispatch.
- Display_Update only allocates the overlap list for overlapping styles.
- Parrot:MigrateDB() - a versioned top-level database migration scaffold.
- Parrot:Print() defined (AceConsole isn't embedded; Triggers.lua called it).

]] .. G .. [[4. Client abstraction + error isolation]] .. X .. [[

- Parrot.API (Code/API.lua, one per client) - modules call Parrot.API.* for
  spell / item lookups instead of C_Spell / GetSpellInfo directly, so all the
  client differences live in one file. Also folds in the retail deprecation
  guards (IsUsableSpell, GetItemIcon, GetComboPoints) and the old MoP shim.
- Parrot:SafeCall wraps the module lifecycle loops in pcall - one broken
  module can no longer break profile switching or the config window.
  /parrot errors shows what was caught.

]] .. G .. [[5. Embedded libraries]] .. X .. [[

- Ace3 refreshed to current upstream (AceGUI r41, AceConfigDialog r93, AceDB
  r35, ...). Fixes the "bad argument #5 to SetText" error on the Anniversary
  clients.
- LibDBIcon-1.0 r56 added for the minimap button.

]] .. G .. [[6. AddOn-list metadata]] .. X .. [[

All four TOCs: IconTexture, Group, localised Category, and AddonCompartmentFunc
(retail minimap addon menu - left-click config, right-click toggle).

]] .. G .. [[7. Minimap button]] .. X .. [[

Parrot 2 registered a LibDataBroker launcher but bundled nothing to show it.
Added LibDBIcon-1.0. Left-click config, right-click toggle. Show / hide under
Settings -> Minimap icon.

]] .. G .. [[8. Slash sub-commands]] .. X .. [[

/parrot or /parrot config - options.   /parrot test - sample messages.
/parrot toggle - enable / disable.

]] .. G .. [[9. Settings tab and interface language]] .. X .. [[

New Settings group (after General). The minimap toggle moved here. New Language
selector - Automatic (client language) by default, or any of the 11 shipped
languages; changing it prompts for a reload. PreLocale.lua / PostLocale.lua set
GAME_LOCALE around locales.xml so AceLocale loads the chosen language.

]] .. G .. [[10. Modern options skin]] .. X .. [[

A cosmetic skin for the AceGUI widgets - AceConfigDialog still builds and drives
everything, so the "+" side tabs, dynamic option lists and live preview all keep
working. Flat dark surfaces, a parrot-green accent, hairline borders, custom
fonts, slim scrollbars. Custom filled checkboxes, a custom "+"/"-" expand
toggle, a custom dropdown chevron (grey when disabled), an accent underline on
the active tab, an accent bar on the selected side-tab, highlighted text fields
with an accent focus state, green headings and control labels, and the empty
bottom status strip removed. Each skinner runs in pcall.

]] .. G .. [[11. Changelog / About panel]] .. X .. [[

The two buttons at the bottom-left of the options window, and these two popups.

]] .. G .. [[12. Tooling]] .. X .. [[

.gitattributes (LF, vendored libs) and .luacheckrc.

]] .. D .. [[Full technical changelog: CHANGELOG.md in the addon folder.]] .. X .. [[
]]

local LINKS = {
	{ "GitHub",     "https://github.com/NeeRgY/Parrot3" },
	{ "Ko-fi",      "https://ko-fi.com/neergy" },
	{ "Discord",    "https://discord.gg/YjfyDKckCS" },
	{ "Parrot 2",   "https://github.com/nebularg/Parrot2" },
	{ "Curseforge", "https://www.curseforge.com/wow/addons/parrot-3" },
}

----------------------------------------------------------------------
-- Popups
----------------------------------------------------------------------
local function scrollText(parent)
	local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
	local sb = sf.ScrollBar or _G[sf:GetName() and sf:GetName() .. "ScrollBar"]
	if sb then
		sb:ClearAllPoints()
		sb:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, -2)
		sb:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0, 2)
		sb:SetWidth(6)
		for _, s in next, { "ScrollUpButton", "ScrollDownButton" } do
			local b = sb[s] or (sb:GetName() and _G[sb:GetName() .. s])
			if b then b:SetAlpha(0); b:SetSize(1, 1); b:EnableMouse(false) end
		end
		local th = sb.GetThumbTexture and sb:GetThumbTexture()
		if th then th:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.5) end
	end

	local content = CreateFrame("Frame", nil, sf)
	content:SetSize(1, 1)
	sf:SetScrollChild(content)

	local fs = content:CreateFontString(nil, "ARTWORK")
	fs:SetFontObject(F.normal)
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetSpacing(3)
	fs:SetPoint("TOPLEFT")
	fs:SetPoint("TOPRIGHT")

	sf:SetScript("OnSizeChanged", function(_, w) fs:SetWidth(w) content:SetHeight(fs:GetStringHeight() + 20) end)
	return sf, fs, content
end

local changelogFrame
function Parrot:ShowChangelog()
	if not changelogFrame then
		local f = UI.Window("Parrot3ChangelogFrame", 560, 520, L["Changelog"] .. "  |cff808080" .. VERSION .. "|r")
		local sf, fs, content = scrollText(f)
		sf:SetPoint("TOPLEFT", 16, -46)
		sf:SetPoint("BOTTOMRIGHT", -22, 16)
		-- The window is created hidden, so the OnSizeChanged handler in
		-- scrollText() never fires; set the real width up front instead of
		-- relying on it. fs is anchored on both sides to content, so its
		-- width must be set via content's width, not directly on fs.
		content:SetWidth(sf:GetWidth())
		fs:SetText((CHANGELOG:gsub("^%s+", "")))
		content:SetHeight(fs:GetStringHeight() + 20)
		changelogFrame = f
	end
	changelogFrame:Show()
	changelogFrame:Raise()
end

local aboutFrame
function Parrot:ShowAbout()
	if not aboutFrame then
		local f = UI.Window("Parrot3AboutFrame", 460, 426, L["About"])

		local head = f:CreateFontString(nil, "OVERLAY")
		head:SetFontObject(F.title)
		head:SetPoint("TOPLEFT", 16, -52)
		head:SetText("Parrot 3  |cff808080" .. VERSION .. "|r")

		local body = f:CreateFontString(nil, "ARTWORK")
		body:SetFontObject(F.normal)
		body:SetJustifyH("LEFT")
		body:SetSpacing(3)
		body:SetPoint("TOPLEFT", 16, -78)
		body:SetPoint("RIGHT", -16, 0)
		body:SetText(
			L["Floating Combat Text of awesomeness."] .. "\n\n" ..
			"|cff4dc78d" .. (L["Maintained by"] or "Maintained by") .. "|r  NeRgY\n" ..
			(L["A community fork of Parrot 2 by Neb, based on the original Parrot by ckknight. Not affiliated with Blizzard Entertainment."]) .. "\n\n" ..
			"|cff808080" .. (L["Donations support fork maintenance, not the original authors."] or "") .. "|r"
		)

		local y = -190
		for _, link in ipairs(LINKS) do
			local lbl = f:CreateFontString(nil, "OVERLAY")
			lbl:SetFontObject(F.small)
			lbl:SetTextColor(unpack(C.accent))
			lbl:SetPoint("TOPLEFT", 16, y)
			lbl:SetText(link[1])
			local fld = UI.LinkField(f, link[2])
			fld:SetPoint("TOPLEFT", 92, y + 4)
			fld:SetPoint("RIGHT", f, "RIGHT", -16, 0)
			y = y - 26
		end

		local hint = f:CreateFontString(nil, "ARTWORK")
		hint:SetFontObject(F.small)
		hint:SetPoint("BOTTOMLEFT", 16, 14)
		hint:SetText("|cff808080" .. (L["Click a field and press Ctrl+C to copy."] or "Click a field, Ctrl+C to copy.") .. "|r")

		aboutFrame = f
	end
	aboutFrame:Show()
	aboutFrame:Raise()
end

----------------------------------------------------------------------
-- The two buttons at the bottom-left of Parrot's options window
----------------------------------------------------------------------
local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
if AceConfigDialog then
	local done = setmetatable({}, { __mode = "k" })
	hooksecurefunc(AceConfigDialog, "Open", function(self, appName)
		if appName ~= "Parrot" then return end
		local widget = self.OpenFrames and self.OpenFrames["Parrot"]
		local frame = widget and widget.frame
		if not frame or done[frame] then return end
		done[frame] = true

		local cl = UI.Button(frame, L["Changelog"], 92)
		cl:SetPoint("BOTTOMLEFT", 16, 15)
		cl:SetScript("OnClick", function() Parrot:ShowChangelog() end)

		local ab = UI.Button(frame, L["About"], 74)
		ab:SetPoint("LEFT", cl, "RIGHT", 6, 0)
		ab:SetScript("OnClick", function() Parrot:ShowAbout() end)
	end)
end
