-- Hive Spawn Selector
-- lua/HiveSpawnSelector/GUIHiveSpawnSelectorBanner.lua
--
-- A pregame-only readout of the commander's pick, sitting just under the HUD top bar, so an alien
-- who missed (or scrolled past) the chat announcement can still see where the team is starting
-- without asking. Disappears the moment the round actually starts.
--
-- Deliberately NOT a minimap pin: a pin during PreGame is indistinguishable from the real, already
-- built structures the minimap is showing at that moment (see CLAUDE.md). A text banner is
-- unambiguously a UI element, so it can't be misread as something standing in the world.
--
-- Driven entirely off GameInfo state, never off the announce chat message. GameInfo is
-- Propagate_Always, so this stays correct for players who joined, switched teams or reconnected
-- after the pick was made - none of which the one-shot announce message covers.

class 'GUIHiveSpawnSelectorBanner' (GUIScript)

local kBackgroundColor = Color(0, 0, 0, 0.55)
local kLabelColor = Color(0.7, 0.7, 0.7, 1)
local kHiveColor = ColorIntToColor(kAlienTeamColor)
local kMarineColor = ColorIntToColor(kMarineTeamColor)

local kPadding = 10
local kLineSpacing = 4

-- Gap between the bottom of the HUD top bar and the top of this banner.
local kTopBarGap = 8
-- Used only when the top bar can't be measured - the player has turned it off entirely via the
-- topbar_m / topbar_a advanced option, or it hasn't been created yet. Keeps the banner on screen
-- in roughly the right place instead of jumping to y=0.
local kFallbackY = 70

-- The pick is only meaningful before the round is underway; once it starts, everyone can see where
-- they are. Anything not in this set hides the banner, which covers Started and all the
-- end-of-round states without having to list them.
local kPregameStates =
{
	[kGameState.NotStarted] = true,
	[kGameState.WarmUp] = true,
	[kGameState.PreGame] = true,
	[kGameState.Countdown] = true
}

-- Mirrors the wording of the chat announcement in HiveSpawnSelector_Client.lua - one name reads
-- "Terminal", several read "Terminal or Cafeteria". Names every legal marine spawn, never the one
-- actually chosen; see AnnounceSelection in HiveSpawnSelector_Server.lua for why.
local function FormatMarineSpawns(commaSeparatedNames)

	if not commaSeparatedNames or commaSeparatedNames == "" then
		return nil
	end

	local names = { }
	for name in string.gmatch(commaSeparatedNames, "[^,]+") do
		table.insert(names, name)
	end

	if #names == 0 then
		return nil
	elseif #names == 1 then
		return names[1]
	end

	return table.concat(names, ", ", 1, #names - 1) .. " or " .. names[#names]

end

-- The pick as the local player is allowed to see it, or nil when nothing should be shown.
-- Returns hiveName, marineText.
local function GetDisplayedSelection()

	local player = Client.GetLocalPlayer()
	if not player or player:GetTeamNumber() ~= kTeam2Index then
		return nil
	end

	local gameInfo = GetGameInfoEntity()
	if not gameInfo or not gameInfo:GetSpawnSelectionEnabled() then
		return nil
	end

	if not kPregameStates[gameInfo:GetState()] then
		return nil
	end

	-- Honour the server's AnnounceToWholeTeam config: when it's off, the pick is the commander's
	-- own information and the rest of the team is meant to find out at round start. The flag rides
	-- on GameInfo because this banner reads state rather than receiving the audience-gated message.
	if not gameInfo:GetAnnounceToWholeTeam() and not player:GetIsCommander() then
		return nil
	end

	local techPoint = Shared.GetEntity(gameInfo:GetSelectedSpawn())
	if not (techPoint and techPoint:isa("TechPoint")) then
		return nil
	end

	return techPoint:GetLocationName(), FormatMarineSpawns(gameInfo:GetMarineSpawnCandidates())

end

function GUIHiveSpawnSelectorBanner:Initialize()

	self.visible = true
	self.hasSelection = false
	self.lastHiveName = nil
	self.lastMarineText = nil

	self.background = GUIManager:CreateGraphicItem()
	self.background:SetAnchor(GUIItem.Middle, GUIItem.Top)
	self.background:SetLayer(kGUILayerPlayerHUD)
	self.background:SetColor(kBackgroundColor)
	self.background:SetIsVisible(false)

	self.hiveText = GUIManager:CreateTextItem()
	self.hiveText:SetFontName(Fonts.kAgencyFB_Small)
	self.hiveText:SetScale(GetScaledVector())
	GUIMakeFontScale(self.hiveText)
	self.hiveText:SetAnchor(GUIItem.Middle, GUIItem.Top)
	self.hiveText:SetTextAlignmentX(GUIItem.Align_Center)
	self.hiveText:SetTextAlignmentY(GUIItem.Align_Min)
	self.hiveText:SetColor(kHiveColor)
	self.hiveText:SetText("")
	self.background:AddChild(self.hiveText)

	self.marineText = GUIManager:CreateTextItem()
	self.marineText:SetFontName(Fonts.kAgencyFB_Small)
	self.marineText:SetScale(GetScaledVector() * 0.8)
	GUIMakeFontScale(self.marineText)
	self.marineText:SetAnchor(GUIItem.Middle, GUIItem.Top)
	self.marineText:SetTextAlignmentX(GUIItem.Align_Center)
	self.marineText:SetTextAlignmentY(GUIItem.Align_Min)
	self.marineText:SetColor(kMarineColor)
	self.marineText:SetText("")
	self.background:AddChild(self.marineText)

end

function GUIHiveSpawnSelectorBanner:Uninitialize()

	if self.background then
		GUI.DestroyItem(self.background)
		self.background = nil
		self.hiveText = nil
		self.marineText = nil
	end

end

-- ClientUI requires both of these on every script it manages (see kImplCheck in ns2/lua/ClientUI.lua).
function GUIHiveSpawnSelectorBanner:SetIsVisible(state)
	self.visible = state
	if self.background then
		self.background:SetIsVisible(state and self.hasSelection)
	end
end

function GUIHiveSpawnSelectorBanner:GetIsVisible()
	return self.visible
end

-- Sit directly under the HUD top bar, measured rather than assumed: the bar's height depends on
-- which counters the local team is showing and on the player's HUD scale, so a hardcoded offset
-- would drift. GetScreenPosition(0.5, 1) gives its bottom-centre in screen space, scaling
-- included. It's a GUI2 object owned by ClientUI, and it's absent for anyone who disabled the bar
-- in the advanced options, hence the fallback.
local function GetBannerY()

	local topBar = ClientUI.GetScript("Hud2/topBar/GUIHudTopBarForLocalTeam")
	if topBar and topBar.GetScreenPosition then
		local bottom = topBar:GetScreenPosition(0.5, 1)
		if bottom and bottom.y > 0 then
			return bottom.y + GUIScale(kTopBarGap)
		end
	end

	return GUIScale(kFallbackY)

end

local function UpdateLayout(self, hiveName, marineText)

	local hiveLine = string.format("STARTING HIVE - %s", string.upper(hiveName))
	self.hiveText:SetText(hiveLine)

	local padding = GUIScale(kPadding)
	local lineSpacing = GUIScale(kLineSpacing)

	local width = self.hiveText:GetTextWidth(hiveLine) * self.hiveText:GetScale().x
	local height = self.hiveText:GetTextHeight(hiveLine) * self.hiveText:GetScale().y

	self.hiveText:SetPosition(Vector(0, padding, 0))

	if marineText then
		local marineLine = string.format("Marines: %s", marineText)
		self.marineText:SetIsVisible(true)
		self.marineText:SetText(marineLine)
		self.marineText:SetPosition(Vector(0, padding + height + lineSpacing, 0))

		width = math.max(width, self.marineText:GetTextWidth(marineLine) * self.marineText:GetScale().x)
		height = height + lineSpacing + self.marineText:GetTextHeight(marineLine) * self.marineText:GetScale().y
	else
		self.marineText:SetIsVisible(false)
	end

	self.backgroundWidth = width + padding * 2
	self.background:SetSize(Vector(self.backgroundWidth, height + padding * 2, 0))

end

function GUIHiveSpawnSelectorBanner:Update(deltaTime)

	PROFILE("GUIHiveSpawnSelectorBanner:Update")

	if not self.background then
		return
	end

	local hiveName, marineText = GetDisplayedSelection()

	self.hasSelection = hiveName ~= nil
	self.background:SetIsVisible(self.visible and self.hasSelection)

	if not self.hasSelection then
		self.lastHiveName = nil
		self.lastMarineText = nil
		self.lastBannerY = nil
		return
	end

	-- Text and sizing only change when the pick does, which is at most once every few seconds -
	-- no reason to rebuild strings and re-measure every frame.
	if hiveName ~= self.lastHiveName or marineText ~= self.lastMarineText then
		self.lastHiveName = hiveName
		self.lastMarineText = marineText
		self.lastBannerY = nil
		UpdateLayout(self, hiveName, marineText)
	end

	-- Y is tracked separately from the text: the top bar we hang off can be created, resized or
	-- removed (team switch, commanding, advanced-option change) without the pick itself changing.
	local bannerY = GetBannerY()
	if bannerY ~= self.lastBannerY then
		self.lastBannerY = bannerY
		self.background:SetPosition(Vector(-self.backgroundWidth / 2, bannerY, 0))
	end

end
