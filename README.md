# Spawn Selector

A small Natural Selection 2 server mod that lets the **Aliens team choose where they
start** each round. Once the alien commander picks a hive location, the **Marines are
automatically assigned a different starting tech point**, so both teams know their bases
are set before the game begins.

It's handy for scrims, captains games, casual competitive play, or any server that wants
deliberate starting positions instead of the usual random spawns.

## What it does

- Before the round starts, the **alien commander** sees a **"SELECT STARTING LOCATION"**
  panel listing every hive location available on the map.
- Whatever the commander selects becomes the **alien starting hive**.
- The **marine base** is then placed at a different tech point (chosen at random from the
  remaining valid spots), so the two teams never share a starting location.
- The selection is highlighted in green and syncs to the alien team so everyone can see
  the chosen spot.

It also tightens up the pre-round so the choosing phase is orderly:

- **Field players are frozen** in place once the teams are set and the game is about to
  start (the pre-game wait), so nobody wanders off or fidgets while the spawn is picked.
  Commanders are exempt and can still set up their base.
- **Commanders can't leave the chair** until the game actually starts, preventing
  accidental or last-second logouts during the pre-round.

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

## Credits

This mod is based on the spawn-selection feature from the **NSL (Natural Selection League)**
plugin by **Dragon (xToken)** — <https://github.com/xToken/NSL>. The original code has been
adapted into this focused, standalone mod. All credit for the underlying approach goes to the
NSL project and its author.
