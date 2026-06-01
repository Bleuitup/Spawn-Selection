# CLAUDE.md

Guidance for AI assistants and contributors working in this repository.

## What this is

**Spawn Selector** is a server-side mod for the game **Natural Selection 2**. Before a round, the
**alien commander** picks the team's starting hive from a UI; the **marines** are then placed at a
random *legal* partner location for that hive. It also freezes players and locks commander logout
during the start-of-round countdown.

The underlying approach is adapted from the **NSL** plugin by **Dragon (xToken)** —
<https://github.com/xToken/NSL>. Files that borrow from it credit it in their header. `README.md`
is the user/server-admin facing doc; this file is for development.

## Layout

Mod files live at the repo root (standard NS2 layout). Load order is declared in
`lua/entry/SpawnSelector.entry` (`Client` / `Server` / `Predict` bootstraps + `Priority`).

- `lua/SpawnSelector/SpawnSelector_Utility.lua` — vendored `Class_ReplaceMethod`; loaded first.
- `lua/SpawnSelector/SpawnSelector_Shared.lua` — network message, a shared `TechPoint` getter,
  `GameInfo` synced fields (`spawnSelectionEnabled`, `spawnSelected`), and the countdown freeze.
  Loaded by client, server **and** predict.
- `lua/SpawnSelector/SpawnSelector_Server.lua` — all server logic (pick handler, marine selection,
  the spawn-apply mechanism, logout lock, `sv_spawnselect` admin toggle).
- `lua/SpawnSelector/SpawnSelector_Client.lua` — attaches the UI to `AlienCommander`.
- `lua/SpawnSelector/GUISpawnSelectionMenu.lua` — the "SELECT STARTING LOCATION" panel.
- `lua/SpawnSelector/SpawnSelector_Predict.lua` — loads shared defs into the prediction VM.

## NS2 specifics worth knowing before changing things

- **Spawn placement is applied via `Server.teamSpawnOverride`**, NOT by hooking
  `NS2Gamerules:ChooseTechPoint`. `ResetGame` checks, in order: `Server.teamSpawnOverride` →
  `Server.spawnSelectionOverrides` (fixed per-map pairs from `spawn_selection_override` map
  entities, common on competitive servers) → `ChooseTechPoint`. Because comp maps populate the
  middle one, a `ChooseTechPoint` hook gets silently bypassed. We set
  `Server.teamSpawnOverride = {{ marineSpawn=<lowercase>, alienSpawn=<lowercase> }}` (names must be
  lowercase to match) and clear it on random/disable/round-end.
- **The marine spawn must be a *legal* partner** of the alien pick, or `ResetGame` rejects the
  override and falls back to a random map pair. We pick the marine name randomly (`math.random`,
  not the engine's `techPointRandomizer` which kept returning the first entry) from the partners
  the map pairs with the alien hive in `Server.spawnSelectionOverrides`.
- **Pre-round states:** WarmUp → PreGame (free roam) → Countdown (engine teleports players to
  spawns + drops initial structures and freezes input) → Started. Do not key custom freezes off
  `Player:GetCountdownActive` — that flag also drives the countdown zoom camera / "Game is starting"
  text, and starts it early. Freeze via `Player:GetCanControl`→false plus a no-op
  `Player:UpdateViewAngles`, gated on `GameInfo:GetState() == kGameState.Countdown`.
- **Adding networkVars to a vanilla entity** is fine: `Class_Reload("Class", {newVars})` *merges*
  (doesn't replace). Movement/freeze overrides that affect prediction must be loaded in the
  **Predict** VM too, or the local player rubber-bands.
- `Class_ReplaceMethod(class, name, fn)` returns the original for chaining and also replaces it on
  already-derived classes. Vanilla `TechPoint:GetTeamNumberAllowed()` is server-only — the shared
  getter in `SpawnSelector_Shared.lua` exists so client UI can call it.

## Conventions

- Match the surrounding file's indentation: the server/shared/client/utility files use **tabs**;
  `GUISpawnSelectionMenu.lua` uses 4-space indent (kept from its NSL origin).
- Gate new round-affecting behavior on the synced enable flag (`GameInfo:GetSpawnSelectionEnabled()`
  / the server-side `kEnabled`) so `sv_spawnselect false` reverts cleanly to vanilla.
- Keep `README.md` user-facing; put developer notes here.
