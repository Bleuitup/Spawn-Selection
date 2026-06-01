-- SpawnSelector
-- lua/SpawnSelector/SpawnSelector_Client.lua
--
-- Attaches the spawn-selection menu to the alien commander.

Script.Load("lua/SpawnSelector/SpawnSelector_Utility.lua")
Script.Load("lua/SpawnSelector/SpawnSelector_Shared.lua")

AddClientUIScriptForClass("AlienCommander", "SpawnSelector/GUISpawnSelectionMenu")
