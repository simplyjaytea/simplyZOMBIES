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

// One frame at 60 fps.
const FRAME_MS = 1000 / 60;

// How much of an *overrunning* frame may sit outside our own measurement. Its job is to
// catch work we are not measuring at all: when the HUD serialized the world every frame,
// this gap was ~16 ms. See the guard below for why it only applies once frames are late.
const UNACCOUNTED_BUDGET_MS = flag("unaccounted-budget-ms", 8);

const PORT = 5179;
const URL = `http://127.0.0.1:${PORT}/?wanderers=${WANDERERS}`;

function startServer() {
  // detached puts vite in its own process group, so the teardown below can kill the whole
  // group. Signalling the child pid alone kills the `npx` wrapper and orphans vite, which
  // then holds --strictPort's 5179 and makes the *next* run fail to start.
  const child = spawn(
    "npx",
    ["vite", "--port", String(PORT), "--host", "127.0.0.1", "--strictPort"],
    { stdio: ["ignore", "pipe", "pipe"], detached: true },
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

    await page.goto(URL, { waitUntil: "networkidle" });
    await page.waitForFunction(() => globalThis.__game !== undefined, null, { timeout: 30_000 });

    if (errors.length > 0) {
      throw new Error(`page reported errors:\n  ${errors.join("\n  ")}`);
    }

    // Sample real frames via rAF. Draw time is what the renderer measured for itself;
    // frame time is the whole rAF-to-rAF interval, which is what the player experiences.
    const result = await page.evaluate(async (seconds) => {
      const frames = [];
      const draws = [];
      const works = [];
      let last = performance.now();

      await new Promise((resolve) => {
        const deadline = performance.now() + seconds * 1000;
        const sample = (now) => {
          frames.push(now - last);
          last = now;
          draws.push(globalThis.__game.renderer.lastDrawMs);
          // Everything the frame callback did, including whatever the render hook does
          // after the renderer stops its own timer. A cheap getter on purpose -- stats()
          // serializes the world, which would cost more than the thing being measured.
          works.push(globalThis.__game.workMs());
          if (now < deadline) requestAnimationFrame(sample);
          else resolve(undefined);
        };
        requestAnimationFrame(sample);
      });

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
        work: stat(works.slice(5)),
        ...globalThis.__game.stats(),
      };
    }, SECONDS);

    if (errors.length > 0) {
      throw new Error(`page reported errors:\n  ${errors.join("\n  ")}`);
    }

    const fps = 1000 / result.frame.avg;

    // Measured by the loop around its whole frame callback, not assembled from sim + draw.
    // The old sum omitted everything the render hook did after Renderer.draw returned,
    // which at 2,000 entities was ~16 ms of HUD serialization -- six times the number the
    // budget was reading, and outside the gate entirely.
    const workMs = result.work.avg;

    console.log(`  entities   ${result.entities}, ${result.visible} drawn`);
    console.log(`  ticks      ${result.tick}`);
    console.log(`  sim        ${result.simMs.toFixed(2)} ms/tick`);
    console.log(
      `  draw       ${result.draw.avg.toFixed(2)} ms avg   p95 ${result.draw.p95.toFixed(2)} ms`,
    );
    console.log(
      `  work       ${workMs.toFixed(2)} ms avg   p95 ${result.work.p95.toFixed(2)} ms` +
        `   of the 16.67 ms frame`,
    );
    console.log(
      `  frame      ${result.frame.avg.toFixed(2)} ms avg   ~${fps.toFixed(0)} fps (observed)`,
    );
    console.log(
      `  budget     ${BUDGET_MS} ms draw, ${WORK_BUDGET_MS} ms frame work, ` +
        `${UNACCOUNTED_BUDGET_MS} ms unaccounted`,
    );

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
    if (workMs > WORK_BUDGET_MS) {
      failures.push(`frame work was ${workMs.toFixed(2)} ms, over the ${WORK_BUDGET_MS} ms budget`);
    }
    // A frame that is *overrunning* while `work` claims to be cheap means our own code is
    // doing something the loop's measurement does not cover -- the exact shape of the bug
    // this harness previously had (frame 18.90 ms, reported work 2.82 ms, ~16 ms of HUD
    // serialization in between).
    //
    // The overrun condition is load-bearing, not caution. When the frame is vsync-locked
    // the interval is 16.67 ms *by definition* and the difference from `work` is idle
    // waiting, so comparing them unconditionally fails every healthy run. Only once frames
    // are actually being missed does unexplained time mean anything.
    if (result.frame.avg > FRAME_MS * 1.1 && result.frame.avg - workMs > UNACCOUNTED_BUDGET_MS) {
      failures.push(
        `frame averaged ${result.frame.avg.toFixed(2)} ms but only ${workMs.toFixed(2)} ms is ` +
          `accounted for: ${(result.frame.avg - workMs).toFixed(2)} ms is unmeasured, over the ` +
          `${UNACCOUNTED_BUDGET_MS} ms allowance`,
      );
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
    stopServer(server);
  }
}

/** Kill vite's whole process group, then stop waiting on it. */
function stopServer(child) {
  try {
    process.kill(-child.pid, "SIGTERM");
  } catch {
    // Already gone, or no process group -- either way there is nothing left to stop.
  }
  // Nothing reads these once the run is over, and an open pipe on a child that ignored the
  // signal would keep this process alive with no way to notice.
  child.stdout?.destroy();
  child.stderr?.destroy();
  child.unref();
}

// A wall-clock ceiling on the whole run.
//
// The sampling window is seconds; anything approaching this is a hang, not a slow machine.
// Without it a hang holds a CI runner until GitHub's six-hour job limit and never reports a
// conclusion -- indistinguishable, to anyone reading the PR, from "still running".
const OVERALL_TIMEOUT_MS = flag("timeout-ms", 180_000);

const watchdog = setTimeout(() => {
  console.error(`\nFAIL:\n  timed out after ${OVERALL_TIMEOUT_MS / 1000}s without finishing`);
  process.exit(1);
}, OVERALL_TIMEOUT_MS);
// Don't let the watchdog itself be the reason the process stays alive.
watchdog.unref();

main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => {
    clearTimeout(watchdog);
    // Playwright and vite can both leave handles behind. The measurement is finished and
    // reported by this point, so exiting on the recorded code is the honest outcome --
    // hanging here would report nothing at all.
    process.exit(process.exitCode ?? 0);
  });
