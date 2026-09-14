# CLAUDE.md

Guidance for AI assistants and contributors working in this repository.

## What this is

**Hive Spawn Selector** is a server-side mod for the game **Natural Selection 2**. Before a round, the
**alien commander** picks the team's starting hive from a UI; the **marines** are then placed at a
random *legal* partner location for that hive. It also freezes players and locks commander logout
during the start-of-round countdown.

The underlying approach is adapted from the **NSL** plugin by **Dragon (xToken)** —
<https://github.com/xToken/NSL>. Files that borrow from it credit it in their header. `README.md`
is the user/server-admin facing doc; this file is for development.

## Layout

Standard NS2 Launch Pad project layout, matching the author's other mods: `mod.settings` and
`preview.jpg` sit one level **above** the mod content, which lives under `source/`.

```
mod.settings                                  workshop metadata
preview.jpg                                   workshop preview
source/lua/entry/HiveSpawnSelector.entry      Client / Server / Predict bootstraps + Priority
source/lua/HiveSpawnSelector/*.lua
output/                                       Launch Pad build output, gitignored
```

`source/` is stripped at build time, so runtime paths are `lua/...` — which is why the entry
file's own `Client = "lua/HiveSpawnSelector/HiveSpawnSelector_Client.lua"` (and every `Script.Load` inside
the Lua files) is correct as written, unprefixed with `source/`. **Do not** add `source/` to any
path inside the Lua or the entry file.

**`output/` is gitignored and must be built before publishing.** A fresh clone has none. There is
no compilation step, so the build is `rm -rf output && mkdir -p output && cp -r source/. output/`,
leaving `lua/` at the root of `output/`.

Because it is ignored, **`output/` does not follow branch switches** — it silently keeps whatever
was last built, which is an easy way to publish the wrong version. Rebuild after any checkout
before publishing.

- `lua/HiveSpawnSelector/HiveSpawnSelector_Utility.lua` — vendored `Class_ReplaceMethod`; loaded first.
- `lua/HiveSpawnSelector/HiveSpawnSelector_Shared.lua` — the two network messages (pick request, team
  announcement), a shared `TechPoint` getter, `GameInfo` synced fields (`spawnSelectionEnabled`,
  `spawnSelected`, `legalAlienSpawns`), and the countdown freeze. Loaded by client, server **and**
  predict.
- `lua/HiveSpawnSelector/HiveSpawnSelector_Server.lua` — all server logic (pick handler, both
  marine-selection mechanisms — vanilla and the optional CustomSpawns one, see below — the
  alien-team announcement, logout lock, `sv_spawnselect` admin toggle, `HiveSpawnSelectorConfig.json`
  loading).
- `lua/HiveSpawnSelector/HiveSpawnSelector_Client.lua` — attaches the UI to `AlienCommander`, and renders
  the alien-team pick announcement as a chat message for every alien player.
- `lua/HiveSpawnSelector/GUIHiveSpawnSelectorMenu.lua` — the "SELECT STARTING LOCATION" panel.
- `lua/HiveSpawnSelector/HiveSpawnSelector_Predict.lua` — loads shared defs into the prediction VM.

(All four paths above are relative to `source/`, e.g. the first is really
`source/lua/HiveSpawnSelector/HiveSpawnSelector_Utility.lua` on disk.)

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
  getter in `HiveSpawnSelector_Shared.lua` exists so client UI can call it.
- **The alien-team pick announcement is a real chat message, not a UI-only sync.** The
  `spawnSelected` `GameInfo` field only reaches the commander's own client (it drives the
  commander-only picker UI, attached via `AddClientUIScriptForClass("AlienCommander", ...)`), so
  it can't be used to notify the rest of the team. `HiveSpawnSelector_Server.lua`'s
  `AnnounceSelection` instead sends a dedicated `HiveSpawnSelector_Announce` message directly to
  every player on `kTeam2Index` (via `GetEntitiesForTeam("Player", kTeam2Index)` +
  `Server.GetOwner`), and `HiveSpawnSelector_Client.lua` renders it by hooking the global
  `ChatUI_GetMessages()` and injecting a message in vanilla's `chatMessages` shape (color, header,
  color, text, isCommander, isRookie, 0, 0 — see `ns2/lua/Chat.lua`). Adapted from NSL's
  `NSLSendTeamMessage(kTeam2Index, ...)` / `NSLSystemMessage` chat injection
  (`lua/NSL/admincommands/server.lua`, `lua/NSL/messages/client.lua`), stripped of NSL's
  localization/message-id/league-name machinery since this mod only ships one message in English.
- **The announcement's audience (whole team vs. commander only) is a server config file, not a
  console command**, unlike `sv_spawnselect`. `kConfig` is loaded once at `HiveSpawnSelector_Server.lua`'s
  top level via NS2's core `LoadConfigFile("HiveSpawnSelectorConfig.json", kDefaultConfig, true)`
  (`core/lua/ConfigFileUtility.lua` — always available, no `Script.Load` needed) and never
  re-read, so edits need a map change or server restart, same as any other NS2 mod config file.
  `AnnounceSelection(techPointId, commanderClient, marineCandidates)` takes the picking
  commander's own `client` (already in hand in `OnSpawnSelectionMessage`) specifically so the
  `AnnounceToWholeTeam == false` branch has someone to message — don't re-derive "the commander"
  via a team lookup, the caller already has the right client.
- **The announcement names every legal marine spawn for the pick, never just the one actually
  chosen.** `PickMarineSpawnFromCustomSpawns`/`PickMarineSpawnVanilla` both now return
  `(chosenTechPoint, fullCandidateList)` — the chosen one still drives real placement as before,
  but `AnnounceSelection`'s `marineCandidates` parameter takes the *list*, encoded into the
  `HiveSpawnSelector_Announce` message as a comma-separated `marineSpawnNames` string (matching the
  `legalAlienSpawns` string-list convention already used elsewhere in this file, rather than
  inventing a fixed-size entityid-slot scheme). `HiveSpawnSelector_Client.lua` renders 1 name as
  "Marines will spawn in X.", more than 1 as "Marines will spawn in either X, Y.". Do not simplify
  this back to reporting `kSelectedMarineSpawn` alone — that would tell the alien team exactly
  where marines start, which is the opposite of the intended effect on servers where the
  round begins right after the pick and the announcement is otherwise the only new information
  either team gets before it does.
- **Only the `[Hive Spawn Selector]` tag is colored (magenta); the message body is plain white,
  and it's one line, not two.** A team-colored two-line version (alien orange hive line, marine
  light blue spawn line) was built and shipped briefly, then reverted as too cluttered — don't
  redo it without being asked again. While investigating it, confirmed directly against
  `ns2/lua/GUIChat.lua` that per-word coloring within a single line is not achievable at all
  through vanilla's chat feed regardless: `Update` reads `chatMessages` in fixed strides of
  `numberElementsPerMessage = 8`, and `AddMessage` calls exactly one `SetColor()` on the whole
  message-body text item — there's no inline color-code markup in NS2's text rendering, so a
  single queued line gets at most two colors total (header + body), never more. That constraint
  is why the team-colored attempt was two separate lines in the first place, and it still applies
  if this is revisited — genuine inline multi-color text would require hand-built GUI text items
  replacing the vanilla chat feed entirely for this message (positioning, word-wrap, fade timers,
  stacking), a much bigger undertaking than this mod currently needs.

## Optional CustomSpawns integration (this mod is still standalone)

If Shine (`Person8880/Shine`) and its third-party `customspawns` plugin
(`GhoulofGSG9/Shine-Epsilon`) both happen to be installed on the server *and* CustomSpawns has a
config for the current map, this mod restricts the alien commander's picker to CustomSpawns'
alien-legal locations and places marines using CustomSpawns' own legal pairings instead of the
map's vanilla `spawn_selection_override` pairs (the map's default allowed spawn combinations).
This is **not** achieved by converting this mod into a Shine extension — that was tried and
reverted because it made the mod harder to debug than the standalone form; don't redo that
conversion. Instead, this mod stays exactly as it is and *opportunistically* reaches for Shine's
globals if they happen to exist at runtime:

- **Detection is lazy, not at file-load time.** `EnsureShineHooksRegistered` (in
  `HiveSpawnSelector_Server.lua`) only runs from our own `NS2Gamerules:ResetGame` hook, not at the top
  of the file — this mod and Shine are independent NS2 mods with no guaranteed load order, so
  `Shine` might not exist yet when this file's top level executes. By the time a round actually
  resets, every server mod has finished loading, so it's safe to check there.
- **We register directly into Shine's hook registry without becoming a Shine plugin.**
  `Shine.Hook.Add(Event, Index, Function, Priority)` accepts any caller, not just registered Shine
  plugins (`Person8880/Shine`'s `lua/shine/core/shared/hook.lua:106`) — so
  `Shine.Hook.Add("PreChooseTechPoint", "HiveSpawnSelector", OnPreChooseTechPoint)` hooks into
  CustomSpawns' own published `"PreChooseTechPoint"` event (fired from its
  `NS2Gamerules:ChooseTechPoint` override) with no `Shine.Plugin(...)` registration, no
  `lua/shine/extensions/` folder, and no admin-menu/plugin-config involvement at all.
- **Why we can't just use `Server.teamSpawnOverride` here too:** CustomSpawns clears
  `Server.teamSpawnOverride` (and `Server.spawnSelectionOverrides`) on every `ResetGame` when it's
  active for the map — this happens purely because Shine + CustomSpawns are running on the server,
  regardless of whether *this* mod is itself a Shine plugin. Writing `teamSpawnOverride` in that
  situation would just get silently undone, which is exactly the bug this integration is built to
  avoid.
- **We read CustomSpawns' internal fields directly, not a published API**
  (`GetCustomSpawnsData()`): `Shine:IsExtensionEnabled("customspawns")` plus a populated
  `CustomSpawns.Spawns` table. `CustomSpawns.Spawns[lowerLocationName]` is the **TechPoint entity
  itself**, decorated by CustomSpawns with `.team` (0=both, 1=marines, 2=aliens, 3=none) and
  `.enemyspawns` (array of legal partner location names) — see `GhoulofGSG9/Shine-Epsilon`'s
  `lua/shine/extensions/customspawns.lua`. This is a real coupling to another project's internal
  field names, not a documented API: if CustomSpawns ever renames these, `GetCustomSpawnsData()`
  starts returning `nil` and this integration silently falls back to vanilla-pair behavior rather
  than erroring — fails safe, not loud.
- **CustomSpawns' map config is not always symmetric.** Don't read
  `CustomSpawns.Spawns[alienName].enemyspawns` to find the marine partner — some of CustomSpawns'
  own map configs only declare `enemyspawns` on the marine side (e.g. `ns2_docking`'s single alien
  spot has none of its own even though its marine partner lists it). `PickMarineSpawnFromCustomSpawns`
  instead scans every marine-eligible entry for one whose `enemyspawns` lists the alien's location.
- **Plugin/mod load order does not matter here**, despite Shine auto-wiring same-named hook
  methods (for registered plugins) in alphabetical-by-plugin-name order for ties, and despite our
  own registration being lazy. Reason: CustomSpawns' own `:PreChooseTechPoint` only ever returns
  non-nil for the **aliens** call, and only if its own `:PostChooseTechPoint` already ran earlier
  in the **same** `ResetGame` (from a preceding marines call) to set `self.ValidAlienSpawn`. Since
  our `OnPreChooseTechPoint` answers the **marines** call itself whenever we have an active
  CustomSpawns-driven pick — short-circuiting the whole `ChooseTechPoint` call before CustomSpawns'
  `:PostChooseTechPoint` can run — `self.ValidAlienSpawn` never gets set, so CustomSpawns' own
  handler is a guaranteed no-op for the subsequent aliens call regardless of which listener fires
  first. Do not "fix" this by adding explicit hook priorities; it isn't needed.
- **The new `NS2Gamerules:ResetGame` hook composes correctly with Shine's own hook on the same
  method** (Shine core wraps `ResetGame` too, if installed) because both hooking mechanisms —
  our vendored `Class_ReplaceMethod` and Shine's codegen'd class hooks — capture and chain to
  whatever was in the method slot at their own install time, the standard NS2 monkey-patch-chain
  pattern. This is why `EnsureShineHooksRegistered()`/`SyncLegalAlienSpawns()` are placed before/
  after `originalResetGame(self)` respectively rather than assuming anything about install order.

## Deliberate behaviors — do not "fix" these

Each of these looks like an oversight in review and is not. Confirmed by the maintainer:

- **A selection survives `sv_reset`.** Only `EndGame` clears the cached pick, so an admin reset
  restarts the round on the same spawns. That is what a scrim reset should do.
- **`sv_spawnselect false` does not persist across a map change.** `kEnabled` is a module local
  and the Lua VM is rebuilt per map, so the mod returns to enabled. The supported way to disable
  it permanently is to remove the mod from the server.
- **There is no debug logging in the shipped build.** The `[HiveSpawnSelector]`-prefixed diagnostics
  were removed in `d2acfcb` once the feature was verified. If a remote problem needs diagnosing,
  add them back behind a `kDebug` flag (off by default) and keep the flag once it's fixed.
- **Never run alongside NSL.** Its `customspawns` feature (a *different*, unrelated `customspawns`
  from the standalone NSL mod — not to be confused with Shine-Epsilon's `customspawns` plugin this
  mod optionally integrates with) writes the same `Server.teamSpawnOverride`, so the two mods
  fight over the spawn. This is documented for admins in `README.md`; do not try to make them
  interoperate.
- **This mod is not a Shine extension, on purpose, even though it optionally integrates with
  Shine's CustomSpawns plugin.** A full Shine-extension conversion was tried and reverted because
  it was harder to debug than the standalone form — see "Optional CustomSpawns integration" above
  for how the integration works without that conversion. Don't propose redoing it.

## Conventions

- Match the surrounding file's indentation: the server/shared/client/utility files use **tabs**;
  `GUIHiveSpawnSelectorMenu.lua` uses 4-space indent (kept from its NSL origin).
- Gate new round-affecting behavior on the synced enable flag (`GameInfo:GetSpawnSelectionEnabled()`
  / the server-side `kEnabled`) so `sv_spawnselect false` reverts cleanly to vanilla.
- Keep `README.md` user-facing; put developer notes here.
