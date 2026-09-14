-- Hive Spawn Selector
-- lua/HiveSpawnSelector/HiveSpawnSelector_Server.lua
--
-- Server logic: the alien commander picks a starting tech point; the marines are given a
-- random legal partner spawn for it.
--
-- Two placement mechanisms, chosen per pick depending on whether Shine's CustomSpawns plugin
-- (github.com/GhoulofGSG9/Shine-Epsilon) happens to also be running on this server and is
-- configured for the current map - this mod stays a standalone mod either way; it never depends
-- on Shine being present, it just cooperates with it opportunistically when it is. See
-- CLAUDE.md for the full reasoning.
--
-- - CustomSpawns active: placement is applied by answering CustomSpawns' own "PreChooseTechPoint"
--   Shine hook (fired from its NS2Gamerules:ChooseTechPoint override) rather than by writing
--   Server.teamSpawnOverride - CustomSpawns clears that global on every ResetGame when it's active
--   for the map (this happens regardless of whether we're a Shine plugin ourselves), so writing it
--   here would be silently undone. The legal alien spawn list and the legal marine partner for a
--   pick both come from CustomSpawns' own per-map config (Shine.Plugins.customspawns.Spawns), so
--   aliens can only ever start somewhere CustomSpawns already permits.
--
-- - CustomSpawns absent, or present but not configured for this map: the original mechanism -
--   Server.teamSpawnOverride, the highest-priority spawn path in NS2Gamerules:ResetGame (checked
--   before Server.spawnSelectionOverrides and before ChooseTechPoint), with the marine partner
--   picked randomly from the map's own spawn_selection_override pairs (the default map spawn
--   combinations).
--
-- Adapted from the NSL plugin:
-- https://github.com/xToken/NSL - lua/NSL/customspawns/server.lua - by Dragon

Script.Load("lua/HiveSpawnSelector/HiveSpawnSelector_Utility.lua")
Script.Load("lua/HiveSpawnSelector/HiveSpawnSelector_Shared.lua")

-- Server admin config: config://HiveSpawnSelectorConfig.json, written with these defaults the first
-- time the mod runs on a server. Loaded once at mod load - edits need a map change or server
-- restart to take effect, the usual convention for NS2 mod config files (see LoadConfigFile in
-- core/lua/ConfigFileUtility.lua).
local kDefaultConfig = {
	-- true (default): the whole alien team is sent "Your commander has selected X as your
	-- spawn." false: only the commander who made the pick sees it. Matters on servers where
	-- teams are shuffled and the round starts immediately after commanders sit down - the whole
	-- team seeing the message that fast spoils the pick as a surprise for round start, which
	-- doesn't happen on servers where teams are set well before everyone readies up.
	AnnounceToWholeTeam = true
}
local kConfig = LoadConfigFile("HiveSpawnSelectorConfig.json", kDefaultConfig, true)

local kEnabled = true
local kSelectedMarineSpawn
local kSelectedAlienSpawn
-- True when the current pick is being placed via the CustomSpawns PreChooseTechPoint hook rather
-- than Server.teamSpawnOverride - keeps the two placement mechanisms from ever both being "live"
-- for the same pick.
local kUsingCustomSpawnsOverride = false

local function ClearSelectedSpawns()
	kSelectedMarineSpawn = nil
	kSelectedAlienSpawn = nil
	kUsingCustomSpawnsOverride = false
	Server.teamSpawnOverride = nil
	local gameInfo = GetGameInfoEntity()
	if gameInfo then
		gameInfo:SetSelectedSpawn(Entity.invalidId)
	end
end

-- Apply the alien commander's pick via Server.teamSpawnOverride - see the file header for when
-- this path is used instead of the CustomSpawns hook. The highest-priority spawn mechanism in
-- NS2Gamerules:ResetGame (checked before Server.spawnSelectionOverrides and before
-- ChooseTechPoint). Many competitive servers/maps populate Server.spawnSelectionOverrides with
-- fixed spawn pairs, which silently bypassed our earlier ChooseTechPoint override - that was the
-- cause of "picked X but spawned at Y". teamSpawnOverride wins over those, and is non-destructive:
-- we don't have to wipe the map's pairs, which still apply when there is no pick (random). Names
-- must be lowercase to match the comparison ResetGame does.
local function ApplyTeamSpawnOverride()
	if kEnabled and not kUsingCustomSpawnsOverride and kSelectedAlienSpawn and kSelectedMarineSpawn then
		Server.teamSpawnOverride = { {
			marineSpawn = string.lower(kSelectedMarineSpawn:GetLocationName()),
			alienSpawn = string.lower(kSelectedAlienSpawn:GetLocationName())
		} }
	else
		Server.teamSpawnOverride = nil
	end
end

-- Clear cached picks when a round ends so the next round starts fresh.
local originalEndGame
originalEndGame = Class_ReplaceMethod("NS2Gamerules", "EndGame",
	function(self, winningTeam)
		originalEndGame(self, winningTeam)
		ClearSelectedSpawns()
	end
)

local function ResolveTechPointByName(lowerName)
	for _, tp in ipairs(EntityListToTable(Shared.GetEntitiesWithClassname("TechPoint"))) do
		if string.lower(tp:GetLocationName()) == lowerName then
			return tp
		end
	end
	return nil
end

-- Returns Shine's CustomSpawns plugin's per-map spawn table (Spawns[lowerLocationName] -> the
-- TechPoint entity itself, decorated with .team and .enemyspawns fields) when Shine is present on
-- this server, CustomSpawns is loaded and enabled, AND it has finished parsing a config for the
-- current map - nil in every other case (Shine not installed, CustomSpawns not installed,
-- disabled, or no config for this map), which is exactly when we should fall back to the vanilla
-- Server.teamSpawnOverride path with the map's default spawn combinations. See CLAUDE.md for why
-- this alignment holds.
local function GetCustomSpawnsData()
	if not (Shine and Shine.IsExtensionEnabled) then
		return nil
	end
	local IsEnabled, CustomSpawns = Shine:IsExtensionEnabled("customspawns")
	if IsEnabled and CustomSpawns.Spawns then
		return CustomSpawns.Spawns
	end
	return nil
end

-- Pick a random VALID marine tech point for the alien's chosen hive, using CustomSpawns' own
-- per-map legality data. Scans every marine-eligible entry for one whose enemyspawns lists the
-- alien's location, rather than trusting the alien entry's own enemyspawns field - CustomSpawns'
-- map configs aren't always filled in on both sides (e.g. ns2_docking's single alien spot has no
-- enemyspawns of its own even though its marine partner lists it), so only this direction is
-- reliable.
--
-- Returns the chosen tech point AND the full candidate list it was drawn from (used to announce
-- "marines will spawn in either X, Y" - see AnnounceSelection - without revealing which one was
-- actually chosen).
local function PickMarineSpawnFromCustomSpawns(spawns, alienTechPoint)
	local alienName = string.lower(alienTechPoint:GetLocationName())
	local validMarineSpawns = { }

	for name, data in pairs(spawns) do
		if type(name) == "string" and (data.team == 0 or data.team == kTeam1Index) and data.enemyspawns then
			for _, partner in ipairs(data.enemyspawns) do
				if string.lower(partner) == alienName then
					table.insert(validMarineSpawns, data)
					break
				end
			end
		end
	end

	if #validMarineSpawns > 0 then
		return validMarineSpawns[math.random(#validMarineSpawns)], validMarineSpawns
	end
	return nil, validMarineSpawns
end

-- Pick a random VALID marine tech point for the alien's chosen hive using the vanilla map's own
-- spawn_selection_override pairs (Server.spawnSelectionOverrides) - the map's default allowed
-- spawn combinations, common on competitive maps. Falls back to any other tech point on maps that
-- don't define pairs. Uses math.random (the old techPointRandomizer:random call kept returning
-- the first tech point, so the marine spawn was effectively fixed).
--
-- Returns the chosen tech point AND the full candidate list it was drawn from - see
-- PickMarineSpawnFromCustomSpawns above for why.
local function PickMarineSpawnVanilla(alienTechPoint)

	local alienName = string.lower(alienTechPoint:GetLocationName())

	if Server.spawnSelectionOverrides then
		local validMarineNames = { }
		for _, pair in ipairs(Server.spawnSelectionOverrides) do
			if pair.alienSpawn == alienName and pair.marineSpawn and pair.marineSpawn ~= alienName then
				table.insertunique(validMarineNames, pair.marineSpawn)
			end
		end
		if #validMarineNames > 0 then
			local validTechPoints = { }
			for _, name in ipairs(validMarineNames) do
				local tp = ResolveTechPointByName(name)
				if tp then
					table.insert(validTechPoints, tp)
				end
			end
			if #validTechPoints > 0 then
				return validTechPoints[math.random(#validTechPoints)], validTechPoints
			end
		end
	end

	-- Fallback: any random valid marine tech point that isn't the alien's pick.
	local validTechPoints = { }
	for _, tp in ipairs(EntityListToTable(Shared.GetEntitiesWithClassname("TechPoint"))) do
		local teamNum = tp:GetTeamNumberAllowed()
		if tp ~= alienTechPoint and (teamNum == 0 or teamNum == kTeam1Index) then
			table.insert(validTechPoints, tp)
		end
	end
	if #validTechPoints > 0 then
		return validTechPoints[math.random(#validTechPoints)], validTechPoints
	end
	return nil, validTechPoints

end

-- Answers CustomSpawns' published "PreChooseTechPoint" Shine hook (see file header) - only when
-- the current pick is being placed through CustomSpawns. Registered defensively via
-- EnsureShineHooksRegistered below, never invoked at all when Shine/CustomSpawns aren't present.
local function OnPreChooseTechPoint(gamerules, techPoints, teamNumber)
	if not kEnabled or not kUsingCustomSpawnsOverride then return end

	if teamNumber == kTeam1Index and kSelectedMarineSpawn then
		return kSelectedMarineSpawn
	elseif teamNumber == kTeam2Index and kSelectedAlienSpawn then
		return kSelectedAlienSpawn
	end
end

-- Registers our PreChooseTechPoint listener directly with Shine's hook registry (Shine.Hook.Add
-- takes any caller, not just registered Shine plugins - we deliberately do NOT convert this mod
-- into a real Shine extension for this, see CLAUDE.md). Done lazily from the ResetGame hook below
-- rather than at file-load time: this mod's entry script and Shine's mod (if installed at all) load
-- as independent NS2 mods with no guaranteed order, so `Shine` might not exist yet when this file's
-- top level runs. By the time a round actually resets, every server mod has finished loading.
local kShineHooksRegistered = false
local function EnsureShineHooksRegistered()
	if kShineHooksRegistered then return end
	if not (Shine and Shine.Hook and Shine.Hook.Add) then return end
	Shine.Hook.Add("PreChooseTechPoint", "HiveSpawnSelector", OnPreChooseTechPoint)
	kShineHooksRegistered = true
end

-- Recomputes the legal-alien-spawn list synced to clients (see HiveSpawnSelector_Shared.lua /
-- GUIHiveSpawnSelectorMenu.lua). CustomSpawns lazily parses its map config from its own
-- "OnGameReset" handler, itself triggered by the same underlying NS2Gamerules:ResetGame call this
-- runs from - since this runs AFTER originalResetGame() below, CustomSpawns (if present) has
-- already had a chance to parse this map's config by the time we read its data, regardless of
-- which of our two independent method-hooks on ResetGame happens to wrap the other.
local function SyncLegalAlienSpawns()
	local gameInfo = GetGameInfoEntity()
	if not gameInfo then return end

	local customSpawnsData = GetCustomSpawnsData()
	if not customSpawnsData then
		gameInfo:SetLegalAlienSpawns("")
		return
	end

	local legalNames = { }
	for name, data in pairs(customSpawnsData) do
		if type(name) == "string" and (data.team == 0 or data.team == kTeam2Index) then
			table.insert(legalNames, name)
		end
	end
	gameInfo:SetLegalAlienSpawns(table.concat(legalNames, ","))
end

-- EnsureShineHooksRegistered must run BEFORE the real ResetGame logic, since that's what actually
-- calls ChooseTechPoint (and so Shine.Hook.Call("PreChooseTechPoint", ...)) for this round -
-- SyncLegalAlienSpawns must run AFTER it, since that's what gives CustomSpawns a chance to parse
-- its map config first.
local originalResetGame
originalResetGame = Class_ReplaceMethod("NS2Gamerules", "ResetGame",
	function(self)
		EnsureShineHooksRegistered()
		originalResetGame(self)
		SyncLegalAlienSpawns()
	end
)

-- Block the commander from voluntarily leaving the chair during the final countdown. The logout
-- button, the Exit key, and the "logout" console command all route through OnCommandLogout, which
-- checks GetCommanderLogoutAllowed(). A forced Eject() / disconnect calls Commander:Logout()
-- directly and bypasses this gate, so server-side cleanup of a leaving commander still works.
-- The lock only applies during the countdown - commanders may freely enter/leave chairs while
-- setting up during the rest of the pre-game.
local originalGetCommanderLogoutAllowed = GetCommanderLogoutAllowed
function GetCommanderLogoutAllowed()
	if kEnabled then
		local gamerules = GetGamerules()
		if gamerules and gamerules:GetGameState() == kGameState.Countdown then
			return false
		end
	end
	return originalGetCommanderLogoutAllowed()
end

-- Relays the commander's pick as a chat message (client.lua renders it), e.g. "Your commander
-- has selected Reception as your spawn. Marines will spawn in either Cargo, Warehouse." Pass
-- Entity.invalidId for the random/cleared case (marineCandidates is meaningless then, pass nil),
-- and the picking commander's own client so the commander-only mode
-- (kConfig.AnnounceToWholeTeam == false) has someone to send it to. marineCandidates is the full
-- candidate list PickMarineSpawnFromCustomSpawns/PickMarineSpawnVanilla drew from, NOT just the
-- one actually chosen - the message names every legal marine spawn rather than spoiling which one
-- won the random pick. Adapted from NSL's NSLSendTeamMessage(kTeam2Index, ...) calls in
-- lua/NSL/customspawns/server.lua, without NSL's localization/message-id machinery.
local function AnnounceSelection(techPointId, commanderClient, marineCandidates)
	local marineSpawnNames = ""
	if marineCandidates and #marineCandidates > 0 then
		local names = { }
		for _, tp in ipairs(marineCandidates) do
			table.insert(names, tp:GetLocationName())
		end
		marineSpawnNames = table.concat(names, ",")
	end

	if kConfig.AnnounceToWholeTeam then
		local players = GetEntitiesForTeam("Player", kTeam2Index)
		for _, player in ipairs(players) do
			local client = Server.GetOwner(player)
			if client then
				Server.SendNetworkMessage(client, "HiveSpawnSelector_Announce",
					{ techPointId = techPointId, marineSpawnNames = marineSpawnNames }, true)
			end
		end
	elseif commanderClient then
		Server.SendNetworkMessage(commanderClient, "HiveSpawnSelector_Announce",
			{ techPointId = techPointId, marineSpawnNames = marineSpawnNames }, true)
	end
end

local function OnSpawnSelectionMessage(client, message)

	if not kEnabled or not client or not message then
		return
	end

	local player = client:GetControllingPlayer()
	if not player then
		return
	end

	-- Only the alien commander may choose.
	if not (player:GetIsCommander() and player:GetTeamNumber() == kTeam2Index) then
		return
	end

	local tp = Shared.GetEntity(message.techPointId)
	if not (tp and tp:isa("TechPoint")) then
		ClearSelectedSpawns()
		AnnounceSelection(Entity.invalidId, client)
		return
	end

	local customSpawnsData = GetCustomSpawnsData()

	if customSpawnsData then
		-- CustomSpawns is present and configured for this map: aliens may only pick a location
		-- it marks alien-legal, and the marine partner comes from its own pairing data.
		local name = string.lower(tp:GetLocationName())
		local spawnInfo = customSpawnsData[name]
		local alienEligible = spawnInfo and (spawnInfo.team == 0 or spawnInfo.team == kTeam2Index)

		local marineTechPoint, marineCandidates
		if alienEligible then
			marineTechPoint, marineCandidates = PickMarineSpawnFromCustomSpawns(customSpawnsData, tp)
		end

		if marineTechPoint then
			kSelectedAlienSpawn = tp
			kSelectedMarineSpawn = marineTechPoint
			kUsingCustomSpawnsOverride = true
			Server.teamSpawnOverride = nil
			local gameInfo = GetGameInfoEntity()
			if gameInfo then
				gameInfo:SetSelectedSpawn(tp:GetId())
			end
			AnnounceSelection(tp:GetId(), client, marineCandidates)
		else
			-- Not alien-legal under CustomSpawns, or no legal marine partner: do not show a
			-- choice we would not honour.
			ClearSelectedSpawns()
			AnnounceSelection(Entity.invalidId, client)
		end

		return
	end

	-- Vanilla fallback path (CustomSpawns absent, or not configured for this map) - the map's
	-- default allowed spawn combinations.
	local marineTechPoint, marineCandidates
	if tp:GetTeamNumberAllowed() == 0 or tp:GetTeamNumberAllowed() == kTeam2Index then
		marineTechPoint, marineCandidates = PickMarineSpawnVanilla(tp)
	end

	if marineTechPoint then
		-- Valid alien-allowed pick with a legal marine partner: cache both and install the
		-- override so it actually wins at round start.
		kSelectedAlienSpawn = tp
		kSelectedMarineSpawn = marineTechPoint
		kUsingCustomSpawnsOverride = false
		ApplyTeamSpawnOverride()
		local gameInfo = GetGameInfoEntity()
		if gameInfo then
			gameInfo:SetSelectedSpawn(tp:GetId())
		end
		AnnounceSelection(tp:GetId(), client, marineCandidates)
	else
		-- Random / clear request, an invalid id, or a pick we cannot pair a marine spawn with -
		-- revert to vanilla selection rather than showing a choice we would not honour.
		ClearSelectedSpawns()
		AnnounceSelection(Entity.invalidId, client)
	end

end

Server.HookNetworkMessage("HiveSpawnSelector_SelectSpawn", OnSpawnSelectionMessage)

-- Admin toggle. Defaults to enabled; "sv_spawnselect false" disables (UI hides, spawns vanilla).
local function SetSpawnSelectEnabled(client, enabledArg)

	if enabledArg ~= nil then
		kEnabled = enabledArg == "true" or enabledArg == "1"
	else
		kEnabled = not kEnabled
	end

	local gameInfo = GetGameInfoEntity()
	if gameInfo then
		gameInfo:SetSpawnSelectionEnabled(kEnabled)
	end

	if not kEnabled then
		ClearSelectedSpawns()
	end

	Shared.Message("Hive Spawn Selector: alien spawn selection " .. (kEnabled and "ENABLED" or "DISABLED"))

end

CreateServerAdminCommand("Console_sv_spawnselect", SetSpawnSelectEnabled,
	"<true/false>, Enables or disables alien spawn selection (default enabled).")
