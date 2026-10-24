// The CI shard layout for `godot:m2`: which chained gates each parallel `godot-m2` job runs.
//
// The chain is one `&&` list in package.json (`godot:m2:chain`), and on one runner it reached
// 40m45s on 2b48fef (gate time 2439 s, 86 gates on that branch; 85 on main, which has no
// `godot:check:motion` yet). That run is the timing source for the split below. The one gate
// that cannot be shortened is `godot:m2:balance` at 791 s (13.2 min) on its own, so it gets a
// shard to itself and the other three shards share the remaining ~1650 s (~9 min each).
//
// Rules this file keeps:
//   - Every chained script is in exactly one shard. `scripts/check-shards.mjs` refuses a gate
//     that is missing or duplicated, so a new gate cannot be dropped from CI by omission. A
//     new gate is added to a shard in the same commit that adds it to the chain.
//   - Each shard runs its gates in chain order (`shardNames` filters the chain, so the order of
//     a list here does not matter), so a gate keeps the position it had under `&&` relative to
//     the gates that share its shard.
//   - Shared state stays in one shard. Each gate boots its own Godot process, so the only
//     channel between gates is the disk. The gates that write the per-machine `user://` store
//     (`godot:check:play`, `godot:m2:save`, `godot:check:ui_skin`) run together in shard 3.
//     `godot:m2:balance` reads no file another gate writes, so it can run alone.
//
// Measured per shard, from the 2b48fef run's GATE_TIME table (seconds, sum of its gates):
//   shard 1  546 s  29 gates      shard 3  546 s  28 gates
//   shard 2  546 s  27 gates      shard 4  791 s   1 gate (balance)
// Re-measure when a shard passes 15 minutes, and move gates between shards by hand; do not
// add a rebalancing step here. The per-shard wall time is in the `godot-m2` job's log.

export const M2_SHARD_COUNT = 4;

/** Shard i (1-based) is `M2_SHARDS[i - 1]`. Names are npm script names, not modes. */
export const M2_SHARDS = [
  [
    "godot:m2:raiders",
    "godot:m2:tick",
    "godot:m2:lethality",
    "godot:m2:weather",
    "godot:m2:strangers",
    "godot:m2:heat",
    "godot:m2:recovery",
    "godot:m2:recruits",
    "godot:m2:warmth",
    "godot:m2:wounds",
    "godot:check:water",
    "godot:check:buildings",
    "godot:m2:harness",
    "godot:m2:hands",
    "godot:m2:allegiance",
    "godot:check:fx",
    "godot:check:decals",
    "godot:m2:contact",
    "godot:m2:comfort",
    "godot:m2:transform",
    "godot:m2:splint",
    "godot:m2:light_burn",
    "godot:m2:torch",
    "godot:m2:stance",
    "godot:m2:medicine",
    "godot:m2:materials",
    "godot:m2:variance",
    "godot:check:speech",
    "godot:check:weather",
    "godot:check:authored",
    "godot:ban:healthbar",
    "godot:check:camera",
    "godot:check:motion",
    "godot:check:action",
  ],
  [
    "godot:m2:needs",
    "godot:check:world_bake",
    "godot:m2:orders",
    "godot:m2:cold",
    "godot:check:worldgen",
    "godot:m2:region",
    "godot:m2:ranged",
    "godot:check:loot",
    "godot:m2:npc",
    "godot:m2:district",
    "godot:m2:noise",
    "godot:m2:dormant",
    "godot:check:hud",
    "godot:check:wrecks",
    "godot:m2:attach",
    "godot:check:context",
    "godot:check:memory",
    "godot:check:appearance",
    "godot:m2:ammo",
    "godot:check:mods",
    "godot:check:inventory",
    "godot:m2:sight",
    "godot:check:light",
    "godot:m2:upkeep",
    "godot:m2:teach",
    "godot:check:worn",
    "godot:check:web_look",
    "godot:m2:swipe",
    "godot:m2:armor",
  ],
  [
    "godot:m2:storm",
    "godot:check:shots",
    "godot:m2:settlers",
    "godot:m2:camp",
    "godot:m2:save",
    "godot:check:play",
    "godot:check:ui_skin",
    "godot:m2:jobs",
    "godot:m2:walls",
    "godot:m2:director",
    "godot:m2:filter",
    "godot:m2:fog",
    "godot:m2:vehicles",
    "godot:m2:treatment",
    "godot:m2:web",
    "godot:m2:roster",
    "godot:check:roof",
    "godot:check:trees",
    "godot:check:road",
    "godot:m2:aim",
    "godot:check:zombie_art",
    "godot:m2:armored",
    "godot:m2:autonomy",
    "godot:m2:gear",
    "godot:m2:fortify",
    "godot:m2:bench",
    "godot:check:topdown",
    "godot:m2:people",
    "godot:m2:stats",
    "godot:check:respond",
  ],
  ["godot:m2:balance"],
];

/** The names shard `index` (1-based) of `count` runs, in chain order. Throws when `count` is not
 *  the layout's shard count, so a CI matrix that drifts from this file fails loudly instead of
 *  running a short or empty shard. */
export function shardNames(chain, index, count) {
  if (count !== M2_SHARD_COUNT) {
    throw new Error(`--shard=${index}/${count}: this layout has ${M2_SHARD_COUNT} shards`);
  }
  if (!Number.isInteger(index) || index < 1 || index > count) {
    throw new Error(`--shard=${index}/${count}: index must be 1..${count}`);
  }
  const wanted = new Set(M2_SHARDS[index - 1]);
  return chain.filter((name) => wanted.has(name));
}
