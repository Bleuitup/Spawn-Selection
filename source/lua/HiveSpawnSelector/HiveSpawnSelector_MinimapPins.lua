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

-- Adjacent candidate rooms are common (e.g. ns2_docking's Generator pairs with both Terminal and
-- Cafeteria, which sit right next to each other) - two same-color, same-icon pins landing on top of
-- each other on the minimap would just read as one, defeating the point. Nudge any that land closer
-- than a pin's own width apart so each stays individually visible. Not a real physics solver, just a
-- few relaxation passes - there are at most kMaxMarinePins points, so this is cheap.
local kMinPinSeparation = kPinSize.x * 0.95

local function DeclutterPositions(positions)
	local n = #positions
	for pass = 1, 6 do
		local moved = false
		for i = 1, n do
			for j = i + 1, n do
				local a = positions[i]
				local b = positions[j]
				local dx = b.x - a.x
				local dy = b.y - a.y
				local dist = math.sqrt(dx * dx + dy * dy)
				if dist < kMinPinSeparation then
					moved = true
					local pushX, pushY
					if dist < 0.001 then
						-- Exactly coincident (same room, distinct tech points): pick a deterministic
						-- direction from the pair's own indices so they don't fight each other.
						local angle = (i + j) * (2 * math.pi / 7)
						pushX, pushY = math.cos(angle), math.sin(angle)
					else
						pushX, pushY = dx / dist, dy / dist
					end
					local shortfall = (kMinPinSeparation - dist) / 2
					a.x = a.x - pushX * shortfall
					a.y = a.y - pushY * shortfall
					b.x = b.x + pushX * shortfall
					b.y = b.y + pushY * shortfall
				end
			end
		end
		if not moved then
			break
		end
	end
end

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

	-- Two passes: resolve every candidate's raw minimap position first, then declutter the whole
	-- set together (a pin can need to move because of a candidate discovered later in the id list),
	-- and only then write positions to the actual GUIItems.
	local positions = { }
	local resolvedPins = { }
	if marineIdsCsv and marineIdsCsv ~= "" then
		for idStr in string.gmatch(marineIdsCsv, "[^,]+") do
			if #resolvedPins >= kMaxMarinePins then
				break
			end

			local tp = Shared.GetEntity(tonumber(idStr))
			if tp and tp:isa("TechPoint") then
				local pos = tp:GetOrigin()
				table.insert(positions, Vector(minimapInstance:PlotToMap(pos.x, pos.z)))
				table.insert(resolvedPins, marinePins[#resolvedPins + 1])
			end
		end
	end

	DeclutterPositions(positions)

	for i = 1, #resolvedPins do
		resolvedPins[i]:SetPosition(positions[i] + kPinHalfSize)
		resolvedPins[i]:SetIsVisible(true)
	end

	for i = #resolvedPins + 1, kMaxMarinePins do
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
