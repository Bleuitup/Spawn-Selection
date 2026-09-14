-- Hive Spawn Selector
-- lua/HiveSpawnSelector/HiveSpawnSelector_MinimapPins.lua
--
-- Pins the alien commander's chosen hive, and every legal marine spawn candidate for it, on the
-- corner/large minimap the moment the pick is announced - the same "possible locations" idea as
-- the chat message, made visual. Client only.
--
-- Uses vanilla's OWN minimap blip art (ui/minimap_blip.dds) and the same CommandStation/Hive grid
-- cells + team colors GUIMinimap.lua itself uses for built structures, via the same global helpers
-- it calls (BuildClassToGrid/GetSpriteGridByClass in NS2Utility.lua, GUIGetSprite in GUIUtility.lua)
-- rather than a shipped asset - see CLAUDE.md. Technique (position via GUIMinimap:PlotToMap,
-- GUIItems parented to self.minimap) follows the same one devnull's "Fair Start" mod
-- (Workshop 2569595369) uses for its own round-start marine/alien pins, which we checked directly.
--
-- Visible from the moment of the pick until the round actually starts (kGameState.Started), then
-- hidden immediately - the pick can land well before the countdown even begins depending on the
-- server's ready-up setup, so there is no fixed pre-round duration to key off instead.

local kIconFileName = PrecacheAsset("ui/minimap_blip.dds")
local kIconCellSize = 32

-- Match GUIMinimap.lua's own kTeamColors[kMinimapBlipTeam.Alien] / [.Marine] exactly, so our pins
-- read as the same colors vanilla already uses for alien/marine blips elsewhere on this map.
local kAlienColor = Color(1, 138 / 255, 0, 1)
local kMarineColor = Color(0, 216 / 255, 1, 1)

-- Grid cells resolved through vanilla's own lookup rather than hardcoded, so this keeps working if
-- a future patch ever moves them in the atlas. Confirmed by decompressing minimap_blip.dds:
-- CommandStation = {1,4}, Hive = {2,6}, both plain white/grey top-down silhouettes meant to be
-- tinted at runtime, exactly what SetColor below does.
local kHiveTexCoords
local kChairTexCoords
do
	local classToGrid = BuildClassToGrid()
	local hiveCol, hiveRow = GetSpriteGridByClass("Hive", classToGrid)
	local chairCol, chairRow = GetSpriteGridByClass("CommandStation", classToGrid)
	kHiveTexCoords = { GUIGetSprite(hiveCol, hiveRow, kIconCellSize, kIconCellSize) }
	kChairTexCoords = { GUIGetSprite(chairCol, chairRow, kIconCellSize, kIconCellSize) }
end

-- Deliberately bigger than vanilla's own static TechPoint-sized blips (kBlipSize = GUIScale(30),
-- scaled again by the minimap's own zoom) - the whole point is for these to stand out as a
-- temporary highlight, not blend in as more map furniture.
local kPinSize = GUILinearScale(Vector(34, 34, 0))
local kPinHalfSize = kPinSize * -0.5

-- Generous headroom over any realistic number of legal marine candidates for one hive (CustomSpawns
-- configs and vanilla spawn_selection_override pairs both stay well under this in practice).
local kMaxMarinePins = 8

local function CreatePin(minimap, texCoords, color)
	local item = GetGUIManager():CreateGraphicItem()
	item:SetTexture(kIconFileName)
	item:SetTexturePixelCoordinates(unpack(texCoords))
	item:SetColor(color)
	item:SetSize(kPinSize)
	item:SetAnchor(GUIItem.Middle, GUIItem.Center)
	item:SetIsVisible(false)
	-- Above vanilla's static/dynamic blip layers (kStaticBlipsLayer=2, kDynamicBlipsLayer=3) and
	-- location name text (kLocationNameLayer=4), so a pin is never hidden under either.
	item:SetLayer(6)
	minimap:AddChild(item)
	return item
end

-- The single live GUIMinimap instance, stashed so HiveSpawnSelector_ShowPickPins (called from
-- HiveSpawnSelector_Client.lua's OnAnnounceMessage) has something to call :PlotToMap on. There is
-- only ever one on the client at a time.
local minimapInstance
local hivePin
local marinePins = { }
local pinsActive = false

local originalGUIMinimapInitialize = GUIMinimap.Initialize
function GUIMinimap:Initialize()
	originalGUIMinimapInitialize(self)

	hivePin = CreatePin(self.minimap, kHiveTexCoords, kAlienColor)

	marinePins = { }
	for i = 1, kMaxMarinePins do
		marinePins[i] = CreatePin(self.minimap, kChairTexCoords, kMarineColor)
	end

	minimapInstance = self
	pinsActive = false
end

local originalGUIMinimapUninitialize = GUIMinimap.Uninitialize
function GUIMinimap:Uninitialize()
	if minimapInstance == self then
		minimapInstance = nil
		hivePin = nil
		marinePins = { }
		pinsActive = false
	end
	originalGUIMinimapUninitialize(self)
end

local function HidePins()
	if not pinsActive then
		return
	end
	if hivePin then
		hivePin:SetIsVisible(false)
	end
	for _, pin in ipairs(marinePins) do
		pin:SetIsVisible(false)
	end
	pinsActive = false
end

-- Called from HiveSpawnSelector_Client.lua's OnAnnounceMessage with the same data the chat message
-- uses. alienTechPointId is Entity.invalidId for the random/cleared case, which hides everything
-- rather than pinning a stale pick. marineIdsCsv is HiveSpawnSelector_Announce's marineSpawnIds
-- field (see HiveSpawnSelector_Shared.lua) - the full candidate pool, not just the one actually
-- chosen, same rule as the chat text.
function HiveSpawnSelector_ShowPickPins(alienTechPointId, marineIdsCsv)

	if not (minimapInstance and hivePin) then
		return
	end

	local alienTechPoint = Shared.GetEntity(alienTechPointId)
	if not (alienTechPoint and alienTechPoint:isa("TechPoint")) then
		HidePins()
		return
	end

	local origin = alienTechPoint:GetOrigin()
	hivePin:SetPosition(Vector(minimapInstance:PlotToMap(origin.x, origin.z)) + kPinHalfSize)
	hivePin:SetIsVisible(true)

	local shown = 0
	if marineIdsCsv and marineIdsCsv ~= "" then
		for idStr in string.gmatch(marineIdsCsv, "[^,]+") do
			if shown >= kMaxMarinePins then
				break
			end
			shown = shown + 1

			local pin = marinePins[shown]
			local tp = Shared.GetEntity(tonumber(idStr))
			if tp and tp:isa("TechPoint") then
				local pos = tp:GetOrigin()
				pin:SetPosition(Vector(minimapInstance:PlotToMap(pos.x, pos.z)) + kPinHalfSize)
				pin:SetIsVisible(true)
			else
				pin:SetIsVisible(false)
			end
		end
	end

	for i = shown + 1, kMaxMarinePins do
		marinePins[i]:SetIsVisible(false)
	end

	pinsActive = true

end

-- The only cutoff: hide everything the instant the round actually starts. See the file header for
-- why there is no fixed pre-round duration instead.
local originalGUIMinimapUpdate = GUIMinimap.Update
function GUIMinimap:Update(deltaTime)
	if pinsActive then
		local gameInfo = GetGameInfoEntity()
		if gameInfo and gameInfo:GetState() == kGameState.Started then
			HidePins()
		end
	end
	originalGUIMinimapUpdate(self, deltaTime)
end
