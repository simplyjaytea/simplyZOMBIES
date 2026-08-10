// The frame half of the performance budget harness.
//
// This exists because of what the spike measured: ~0.13 ms of simulation against ~3.7 ms
// of drawing at 1,560 zombies. A budget on the tick alone would have caught nothing,
// because the tick was never the problem
// (docs/22-performance.md#aim-the-budgets-at-the-renderer).
//
// Frame time cannot be measured headlessly in node -- there is no canvas and no
// compositor -- so this drives a real browser, the same way spike/measure.mjs did.
//
//   node bench/frame.mjs [--budget-ms 4] [--seconds 6]

import { spawn } from "node:child_process";
import { chromium } from "playwright";

const args = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : Number(args[i + 1]);
};

// docs/22's quiet-night entry, tightened by chunk 1: <=4 ms frame.
const BUDGET_MS = flag("budget-ms", 4);
const SECONDS = flag("seconds", 6);

// Measured under load rather than at rest. At the 300-entity baseline only ~20 are on
// screen after culling, so the budget could never fail and would be decoration -- the same
// mistake docs/22's original <=2 ms tick budget made. 2,000 matches the "crowded" tick
// scenario, so the two halves of the harness describe the same world.
const WANDERERS = flag("wanderers", 2000);

// How much of a 16.67 ms frame our own code may spend. Generous on purpose: the remainder
// is the browser's compositing, GC and whatever else shares the machine.
const WORK_BUDGET_MS = flag("work-budget-ms", 8);

const PORT = 5179;
const URL = `http://127.0.0.1:${PORT}/?wanderers=${WANDERERS}`;

// A budget harness that hangs is worse than one that fails: CI sits on it for the full job
// timeout and reports nothing at all. Everything below that can block gets a deadline, and
// blowing one is a failure with a message rather than silence.
const OVERALL_TIMEOUT_MS = flag("timeout-ms", 180_000);
const SAMPLE_TIMEOUT_MS = Math.max(30_000, SECONDS * 1000 * 4);

/** Reject with a useful message if `promise` outlasts `ms`. */
function withDeadline(promise, ms, what) {
  let timer;
  return Promise.race([
    promise,
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(`timed out after ${ms} ms: ${what}`)), ms);
    }),
  ]).finally(() => clearTimeout(timer));
}

function startServer() {
  const child = spawn(
    "npx",
    ["vite", "--port", String(PORT), "--host", "127.0.0.1", "--strictPort"],
    { stdio: ["ignore", "pipe", "pipe"] },
  );

  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("vite did not start within 60s")), 60_000);
    const onData = (buffer) => {
      if (buffer.toString().includes("ready in") || buffer.toString().includes(String(PORT))) {
        clearTimeout(timer);
        resolve(child);
      }
    };
    child.stdout.on("data", onData);
    child.stderr.on("data", onData);
    child.on("exit", (code) => {
      clearTimeout(timer);
      reject(new Error(`vite exited early with code ${code}`));
    });
  });
}

async function main() {
  const server = await startServer();

  // CHROMIUM_PATH lets a pre-provisioned browser be used instead of Playwright's own
  // download. Sandboxes and CI images often ship a Chromium whose build number doesn't
  // match the pinned Playwright, and re-downloading one per run is slow and, on a locked
  // down network, impossible.
  const browser = await chromium.launch(
    process.env.CHROMIUM_PATH === undefined
      ? {}
      : { executablePath: process.env.CHROMIUM_PATH, args: ["--no-sandbox"] },
  );

  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });

    // A silent JS error would otherwise show up as "0 fps" and send someone hunting for a
    // performance problem that is really a broken import.
    const errors = [];
    page.on("pageerror", (e) => errors.push(`page error: ${String(e)}`));
    page.on("response", (response) => {
      const url = response.url();
      // The browser always asks for a favicon and we do not ship one; that 404 is noise.
      if (response.status() >= 400 && !url.endsWith("/favicon.ico")) {
        errors.push(`${response.status()} for ${url}`);
      }
    });

    await page.goto(URL, { waitUntil: "networkidle", timeout: 60_000 });
    await page.waitForFunction(() => globalThis.__game !== undefined, null, { timeout: 30_000 });

    if (errors.length > 0) {
      throw new Error(`page reported errors:\n  ${errors.join("\n  ")}`);
    }

    // Sample real frames via rAF. Draw time is what the renderer measured for itself;
    // frame time is the whole rAF-to-rAF interval, which is what the player experiences.
    //
    // Measured mid-convergence, not at rest. A quiet district has every shambler drifting,
    // which is the cheap half of the simulation and the half a budget cannot usefully guard.
    // The shout is pushed through the ordinary command queue, so this measures exactly the
    // code path a player produces by pressing space.
    const result = await withDeadline(
      page.evaluate(async (seconds) => {
        const frames = [];
        const draws = [];
        let last = performance.now();
        let frame = 0;

        globalThis.__game.world.commands.push({ type: "shout" });

        await new Promise((resolve) => {
          const started = performance.now();
          const deadline = started + seconds * 1000;
          // Belt and braces: if rAF stops firing -- a throttled or occluded page, a renderer
          // that has died -- fall back to a timer rather than waiting forever. The sample count
          // in the result is what tells you this happened.
          const bail = setTimeout(() => resolve(undefined), seconds * 1000 + 15_000);
          const sample = (now) => {
            frames.push(now - last);
            last = now;
            draws.push(globalThis.__game.renderer.lastDrawMs);
            // Noise has a ~3 s half-life, so re-shout often enough that the sample never
            // drifts back into measuring a quiet district by accident.
            if (++frame % 120 === 0) globalThis.__game.world.commands.push({ type: "shout" });
            if (now < deadline) requestAnimationFrame(sample);
            else {
              clearTimeout(bail);
              resolve(undefined);
            }
          };
          requestAnimationFrame(sample);
        });

        if (frames.length < 10) {
          throw new Error(
            `only ${frames.length} frames in ${seconds}s -- the page stopped animating, so ` +
              `there is nothing to measure`,
          );
        }

        const stat = (xs) => {
          const sorted = [...xs].sort((a, b) => a - b);
          return {
            avg: xs.reduce((a, b) => a + b, 0) / xs.length,
            p95: sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * 0.95))],
          };
        };

        // Drop the first handful: the tile layer rasterises on the first draw, which is a
        // one-off cost and not what the budget is about.
        return {
          frame: stat(frames.slice(5)),
          draw: stat(draws.slice(5)),
          samples: frames.length,
          ...globalThis.__game.stats(),
        };
      }, SECONDS),
      SAMPLE_TIMEOUT_MS,
      "sampling frames in the browser",
    );

    if (errors.length > 0) {
      throw new Error(`page reported errors:\n  ${errors.join("\n  ")}`);
    }

    const fps = 1000 / result.frame.avg;
    const workMs = result.draw.avg + result.simMs;

    // `hidden` is reported because it is what the draw number now depends on. Occlusion
    // took the entity count on screen from tens to a handful, which means this benchmark
    // guards drawing *less* than it used to -- the same caveat docs/22 already records about
    // viewport culling, arriving a second time. It will matter when sprites replace flat
    // rectangles.
    console.log(
      `  entities   ${result.entities}, ${result.visible} drawn, ${result.hidden ?? 0} hidden`,
    );
    console.log(`  ticks      ${result.tick}`);
    console.log(`  samples    ${result.samples} frames over ${SECONDS}s`);
    console.log(`  sim        ${result.simMs.toFixed(2)} ms/tick`);
    console.log(
      `  draw       ${result.draw.avg.toFixed(2)} ms avg   p95 ${result.draw.p95.toFixed(2)} ms`,
    );
    console.log(`  work       ${workMs.toFixed(2)} ms of the 16.67 ms frame`);
    console.log(
      `  frame      ${result.frame.avg.toFixed(2)} ms avg   ~${fps.toFixed(0)} fps (observed)`,
    );
    console.log(`  budget     ${BUDGET_MS} ms draw, ${WORK_BUDGET_MS} ms sim+draw`);

    const failures = [];
    if (result.draw.avg > BUDGET_MS) {
      failures.push(
        `draw averaged ${result.draw.avg.toFixed(2)} ms against a ${BUDGET_MS} ms budget`,
      );
    }
    if (result.draw.p95 > BUDGET_MS * 2) {
      failures.push(`draw p95 was ${result.draw.p95.toFixed(2)} ms, over twice the budget`);
    }
    // The budget that actually decides whether 60 fps is reachable: how much of the
    // 16.67 ms frame our own code spends. Asserting observed fps instead would be
    // measuring the host -- a headless container's rAF pacing is not vsync, and gating on
    // it makes the harness flaky rather than strict. Observed fps is reported, not gated,
    // except at a floor low enough that only a real collapse trips it.
    //
    // Known blind spot, and it has already bitten once: this gates sim + draw, so per-frame
    // work that is neither -- the HUD's state fingerprint, at ~14 ms once the attention field
    // joined the snapshot -- falls straight through and is only caught by the fps floor
    // below. Anything expensive added to the render callback needs its own measurement.
    if (workMs > WORK_BUDGET_MS) {
      failures.push(`sim+draw was ${workMs.toFixed(2)} ms, over the ${WORK_BUDGET_MS} ms budget`);
    }
    if (fps < 30) {
      failures.push(`${fps.toFixed(0)} fps: the frame has collapsed, not merely slipped`);
    }

    if (failures.length > 0) {
      console.error(`\nFAIL:\n  ${failures.join("\n  ")}`);
      process.exitCode = 1;
      return;
    }

    console.log("\nOK: within budget.");
  } finally {
    await browser.close();
    server.kill("SIGTERM");
  }
}

// The outermost guard. Anything that escapes the per-step deadlines above -- a browser that
// never launches, a dev server that accepts the connection and then stops talking -- still
// ends as a failure with a message instead of a job that sits until CI's own timeout.
withDeadline(main(), OVERALL_TIMEOUT_MS, "the frame benchmark as a whole")
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => {
    // The deadline can win the race while a browser or dev server is still up, and a live
    // handle would keep node alive forever -- which is the hang this is here to prevent.
    process.exit(process.exitCode ?? 0);
  });
