-- SpawnSelector
-- lua/SpawnSelector/SpawnSelector_Predict.lua
--
-- Loads the shared defs into the client prediction VM. This is needed so the pre-round
-- movement freeze (the Player:GetCountdownActive override in the shared file) is applied
-- when the local player's movement is predicted, keeping it in sync with the server and
-- avoiding rubber-banding / jitter during the frozen pre-round.

Script.Load("lua/SpawnSelector/SpawnSelector_Utility.lua")
Script.Load("lua/SpawnSelector/SpawnSelector_Shared.lua")
