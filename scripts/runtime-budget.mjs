// Product targets from docs/22. These do not vary by operating system or runner.
// The draw result measures the shipped GDScript _draw CPU work, not GPU completion.
export const TARGETS = Object.freeze({
  "shipped-tick": { samples: 600, warmup: 100, mean: 8, max: 16 },
  "shipped-draw": { samples: 120, warmup: 30, mean: 10 },
  "crowded-draw": { samples: 120, warmup: 30, mean: 10 },
});

export function statistics(samples) {
  const sorted = [...samples].sort((a, b) => a - b);
  return {
    mean: samples.reduce((sum, n) => sum + n, 0) / samples.length,
    p95: sorted[Math.ceil(samples.length * 0.95) - 1],
    max: sorted.at(-1),
  };
}

export function judgeRuntime(kind, stdout, engineExit = 0) {
  const errors = [];
  const summaries = [];
  const wanted = kind === "tick" ? ["shipped-tick"] : ["shipped-draw", "crowded-draw"];
  if (!["tick", "frame"].includes(kind)) errors.push(`unknown runtime kind: ${kind}`);
  if (engineExit !== 0) errors.push(`engine exited ${engineExit}`);
  if (/SCRIPT ERROR:|Parse Error:|RUNTIME_FRAME_FAIL/.test(stdout)) {
    errors.push("engine reported a script/fixture error");
  }
  if (!stdout.split(/\r?\n/).includes(`RUNTIME_MEASUREMENT_COMPLETE ${kind}`)) {
    errors.push("measurement completion marker is missing");
  }
  const results = [];
  for (const line of stdout.split(/\r?\n/)) {
    if (!line.startsWith("RUNTIME_RESULT ")) continue;
    try {
      results.push(JSON.parse(line.slice("RUNTIME_RESULT ".length)));
    } catch {
      errors.push("malformed runtime result JSON");
    }
  }
  if (results.length !== wanted.length) errors.push("missing or duplicate runtime results");
  for (const id of wanted) {
    const matches = results.filter((r) => r?.id === id);
    if (matches.length !== 1) {
      errors.push(`${id}: expected exactly one result`);
      continue;
    }
    const r = matches[0];
    const target = TARGETS[id];
    if (
      !Array.isArray(r.samples_ms) ||
      r.samples_ms.length !== target.samples ||
      r.samples_ms.some((n) => typeof n !== "number" || !Number.isFinite(n) || n <= 0)
    ) {
      errors.push(`${id}: expected ${target.samples} finite, positive samples`);
      continue;
    }
    if (r.warmup !== target.warmup || r.tiles !== 256) {
      errors.push(`${id}: fixture size or warmup changed`);
    }
    if (kind === "tick") {
      if (
        ![r.start_tick, r.end_tick, r.systems].every(Number.isInteger) ||
        r.end_tick - r.start_tick !== target.samples ||
        !(r.systems > 0)
      ) {
        errors.push(`${id}: the real world did not advance every sampled tick`);
      }
      if (r.seed !== 20260805) errors.push(`${id}: canonical seed changed or is missing`);
    } else {
      if (r.display === "headless" || !r.display || !r.renderer) {
        errors.push(`${id}: no real display/renderer`);
      }
      if (
        JSON.stringify(r.viewport) !== "[1280,720]" ||
        r.vsync_requested !== "disabled" ||
        !Number.isInteger(r.vsync_reported)
      ) {
        errors.push(`${id}: viewport/V-Sync contract changed`);
      }
      for (const name of ["server_ms", "interval_ms"]) {
        if (
          !Array.isArray(r[name]) ||
          r[name].length !== target.samples ||
          r[name].some((n) => typeof n !== "number" || !Number.isFinite(n) || n < 0)
        ) {
          errors.push(`${id}: invalid or missing supplemental ${name}`);
        }
      }
      if (
        id === "crowded-draw" &&
        (r.visible_crowd_min !== 1000 || r.textured_crowd_min !== 1000)
      ) {
        errors.push(
          `${id}: fewer than 1,000 textured fixture bodies reached the real blit consumer`,
        );
      }
    }
    const stats = statistics(r.samples_ms);
    if (stats.mean > target.mean) errors.push(`${id}: mean exceeds ${target.mean} ms`);
    if (target.max !== undefined && stats.max > target.max) {
      errors.push(`${id}: worst tick exceeds ${target.max} ms`);
    }
    const { server_ms, interval_ms, ...fixture } = r;
    delete fixture.samples_ms;
    const summary = { ...fixture, ...stats, target_mean_ms: target.mean };
    if (target.max !== undefined) summary.target_max_ms = target.max;
    if (kind === "tick" && Number.isInteger(r.campaign_ticks) && r.campaign_ticks > 0) {
      summary.ticks_per_second = 1000 / stats.mean;
      summary.projected_campaign_hours = (r.campaign_ticks * stats.mean) / 3600000;
      summary.projected_twelve_run_hours = summary.projected_campaign_hours * 12;
    }
    // Supplemental server submission and between-frame measurements are deliberately
    // not substituted for CPU _draw or asserted as GPU time / player-facing fps.
    for (const [name, values] of Object.entries({ server_ms, interval_ms })) {
      if (Array.isArray(values) && values.length === target.samples) {
        summary[name] = statistics(values);
      }
    }
    summaries.push(summary);
  }
  return { exitCode: errors.length ? 1 : 0, errors, summaries };
}
