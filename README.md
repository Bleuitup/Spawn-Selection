# Hive Spawn Selector

A small Natural Selection 2 server mod that lets the **Aliens team choose where they
start** each round. Once the alien commander picks a hive location, the **Marines are
automatically assigned a different starting tech point**, so both teams know their bases
are set before the game begins.

It's handy for scrims, captains games, casual competitive play, or any server that wants
deliberate starting positions instead of the usual random spawns.

## What it does

- Before the round starts, the **alien commander** sees a **"SELECT STARTING LOCATION"**
  panel listing every hive location available on the map (or, if the server also runs Shine's
  CustomSpawns plugin with a config for the current map, only the locations it allows aliens to
  start at — see Compatibility below).
- Whatever the commander selects becomes the **alien starting hive**.
- The **marine base** is then placed at a different start location, chosen at random from the
  map's valid opposing spawns for the alien's pick (falling back to any other tech point on
  maps that don't define spawn pairs), so the two teams never share a starting location.
- The selection is highlighted in green and syncs to the alien team so everyone can see
  the chosen spot.
- The alien team gets a chat message announcing the pick, tagged **`[Hive Spawn Selector]`** in
  magenta (e.g. "**[Hive Spawn Selector]** Your commander has selected Reception as your spawn.
  Marines will spawn in either Cargo, Warehouse."), or that a random spawn will be used if the
  commander clicks **Random Spawn** or picks somewhere that turns out to have no legal partner
  spawn. The marine part lists every legal marine spawn for the pick, not which one actually won
  the random draw. By default this goes to the whole team; see **Server admin** below to send it
  to the commander only instead.

It also tightens up the start of the round:

- **Players are frozen** in place during the start-of-round countdown, so nobody drifts
  out of position as the round begins.
- **Commanders can't leave the chair during the countdown**, preventing accidental or
  last-second logouts right before the round begins. (They can still freely enter and
  leave chairs while setting up earlier in the pre-game.)

## How to use it

1. **Install the mod** on your server (subscribe via the Steam Workshop, or place it in
   the server's `localmods` folder), then launch the server with the mod active.
2. **Join the Aliens** and take the **commander** chair (the menu only appears for the
   alien commander).
3. During the pre-game, the **SELECT STARTING LOCATION** panel appears on the right side
   of the screen. **Click a location** to choose your starting hive.
4. Prefer the classic behavior for a round? Click **Random Spawn** to clear your pick and
   let the game decide both teams' spawns normally.
5. **Start the round** — the aliens spawn at the chosen hive and the marines spawn at a
   different tech point.

> Note: the picker is tied to the alien commander, so make sure someone is in the alien
> chair before the round begins. If no selection is made, spawns fall back to the game's
> normal random placement.

## Server admin

Spawn selection is **enabled by default**. Admins can toggle it from the server console:

```
sv_spawnselect true     -- enable alien spawn selection (default)
sv_spawnselect false    -- disable; spawns revert to vanilla random placement
```

When disabled, the commander panel is hidden, the pre-round freeze and commander-logout
lock are lifted, and the game uses its standard spawn logic.

Two things worth knowing about the toggle:

- It lasts for the **current map only**. A map change puts the mod back to enabled. To turn
  spawn selection off for good, unsubscribe from or disable the mod on the server rather than
  relying on the console command.
- An admin **`sv_reset` keeps the current selection**, so a reset scrim restarts on the same
  agreed spawns. Click **Random Spawn** first if you want the reset round placed normally.

### Who sees the pick announcement

By default, the whole alien team gets the "Your commander has selected X as your spawn." chat
message. On servers where teams are locked in and everyone's ready well before the round starts,
that's harmless — by the time it matters, the team would see the pick on the panel anyway.

On servers where teams are shuffled right as commanders sit down and the round starts almost
immediately after, that same team-wide message can spoil the pick as a surprise before the round
even begins. If that's your server, edit `configs/HiveSpawnSelectorConfig.json` (created
automatically the first time the mod runs) and set:

```json
{
    "AnnounceToWholeTeam": false
}
```

This sends the announcement to the picking commander only — nobody else on the team sees it in
chat. Everything else (the picker UI, the green highlight, the actual spawn placement) is
unaffected either way. This setting is read once per map load, so a map change or server restart
is needed after editing it.

## Compatibility

**Do not run this mod alongside NSL.** NSL contains its own spawn-selection feature that drives
the same underlying game setting, and running both means neither can be relied on to decide
where a team starts. Pick one or the other.

**Works alongside Shine's CustomSpawns plugin, automatically.** If your server also runs
[Shine](https://github.com/Person8880/Shine) with the third-party **CustomSpawns** plugin from
[Shine-Epsilon](https://github.com/GhoulofGSG9/Shine-Epsilon), and CustomSpawns has a config for
the map you're on, the picker automatically restricts itself to the hive locations CustomSpawns
allows aliens to start at, and the marine partner is chosen from CustomSpawns' own legal pairings
instead of the map's vanilla spawn pairs. This needs no configuration here — it's detected
automatically — and on any map or server where CustomSpawns isn't active, the picker falls back
to the map's own default allowed spawn combinations, exactly as described above. This mod is
still standalone and does not require Shine to be installed; the CustomSpawns integration simply
activates itself when both happen to be present.

Otherwise the mod expects no other mods to be present.

## Credits

This mod is based on the spawn-selection feature from the **NSL (Natural Selection League)**
plugin by **Dragon (xToken)** — <https://github.com/xToken/NSL>. The original code has been
adapted into this focused, standalone mod. All credit for the underlying approach goes to the
NSL project and its author.
