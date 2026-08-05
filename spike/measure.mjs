// Drives the spike headfully in Chromium, runs the scenarios, and prints numbers.
// Answers question 4 (what does 500 zombies cost) without anyone having to eyeball it.
//
//   npm run dev            # in one shell
//   node spike/measure.mjs # in another

import { chromium } from "playwright";
import { mkdirSync } from "node:fs";

const URL = process.env.SPIKE_URL ?? "http://127.0.0.1:5173/";
const OUT = process.env.SPIKE_OUT ?? "/tmp/spike-shots";
mkdirSync(OUT, { recursive: true });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const browser = await chromium.launch({
  executablePath: "/opt/pw-browsers/chromium",
  args: ["--use-gl=swiftshader", "--enable-unsafe-swiftshader"],
});
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
page.on("pageerror", (e) => console.error("PAGE ERROR:", e.message));
page.on("console", (m) => { if (m.type() === "error") console.error("CONSOLE:", m.text()); });

await page.goto(URL, { waitUntil: "networkidle" });
await page.waitForFunction(() => globalThis.__spike !== undefined, null, { timeout: 15000 });

const stats = () => page.evaluate(() => globalThis.__spike.stats());
const shot = async (name) => {
  await page.screenshot({ path: `${OUT}/${name}.png` });
  return `${OUT}/${name}.png`;
};

/** Let the rolling averages fill with the current condition before reading them. */
async function settle(ms = 3500) { await sleep(ms); }

const rows = [];
function record(label, s, note = "") {
  rows.push({ label, ...s, note });
  const [w, sk, i] = s.byState;
  console.log(
    `${label.padEnd(26)} z=${String(s.zombies).padStart(4)}  ` +
    `frame ${s.frameAvg.toFixed(2)}/${s.framep95.toFixed(2)}ms  ` +
    `sim ${s.simAvg.toFixed(2)}/${s.simp95.toFixed(2)}ms  ` +
    `draw ${s.drawAvg.toFixed(2)}ms  cells=${String(s.activeCells).padStart(4)}  ` +
    `w/s/m ${w}/${sk}/${i}  ${note}`,
  );
}

console.log("\n=== simplyZOMBIES attention field spike ===");
console.log("label                       count   frame avg/p95     sim avg/p95     draw    field   wander/seek/mill\n");

// --- 1. Baseline: 60 zombies, player standing still, no noise -------------
await settle();
record("baseline idle (60)", await stats(), "<- quiet costs nothing");
await shot("01-baseline-overlay");

// --- 2. Shout, then watch the seek count -----------------------------------
await page.evaluate(() => globalThis.__spike.shout());
await sleep(400);
const justAfter = await stats();
record("shout +0.4s", justAfter, "<- field lit");
await shot("02-shout-gradient");

await sleep(4000);
record("shout +4.4s", await stats(), "<- converging");
await shot("03-shout-converging");

await sleep(9000);
record("shout +13s", await stats(), "<- decayed, milling");
await shot("04-shout-milling");

// --- 3. Overlay off: is it legible? ----------------------------------------
await page.keyboard.press("KeyO");
await sleep(600);
await shot("05-overlay-off");
await page.keyboard.press("KeyO");

// --- 4. The load test: 500 more --------------------------------------------
await page.keyboard.press("KeyL");
await settle(4000);
record("+500 idle", await stats(), "<- RISK 5 CHECKPOINT");
await shot("06-load-500");

await page.evaluate(() => globalThis.__spike.shout());
await sleep(2500);
record("+500 after shout", await stats(), "<- worst case");
await shot("07-load-500-shout");

await sleep(6000);
record("+500 converged", await stats(), "");
await shot("08-load-500-converged");

// --- 5. Stress beyond spec: 1500 -------------------------------------------
await page.keyboard.press("KeyL");
await page.keyboard.press("KeyL");
await settle(4000);
await page.evaluate(() => globalThis.__spike.shout());
await sleep(3000);
record("+1500 after shout", await stats(), "<- beyond design target");
await shot("09-stress-1500");

console.log("\nscreenshots ->", OUT);
await browser.close();
