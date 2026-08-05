// Isolates one variable: gradient ascent with and without per-individual angular spread.
// Same seed, same shout, same elapsed time — only `spreadEnabled` differs.

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

async function run(spread, name) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  await page.goto(URL, { waitUntil: "networkidle" });
  await page.waitForFunction(() => globalThis.__spike !== undefined, null, { timeout: 15000 });

  await page.evaluate((s) => { globalThis.__spike.horde.spreadEnabled = s; }, spread);
  await page.keyboard.press("KeyO");          // overlay off — judge the movement, not the heat map
  await page.evaluate(() => globalThis.__spike.spawn(400));
  await sleep(500);
  await page.evaluate(() => globalThis.__spike.shout());
  await sleep(11000);

  const s = await page.evaluate(() => globalThis.__spike.stats());
  await page.screenshot({ path: `${OUT}/${name}.png` });
  console.log(
    `spread=${String(spread).padEnd(5)}  z=${s.zombies}  ` +
    `sim ${s.simAvg.toFixed(2)}/${s.simp95.toFixed(2)}ms  frame ${s.frameAvg.toFixed(2)}ms  ` +
    `seek=${s.byState[1]}  -> ${name}.png`,
  );
  await page.close();
}

console.log("\n=== conga-line check: does per-individual spread fix horde shape? ===\n");
await run(false, "10-spread-off");
await run(true, "11-spread-on");
await browser.close();
