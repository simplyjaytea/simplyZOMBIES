import { createReadStream, existsSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { extname, resolve, sep } from "node:path";
import { spawnSync } from "node:child_process";
import { chromium } from "playwright";

const root = process.cwd();
const requested = new Set(process.argv.slice(2));
const smokeWindows = requested.size === 0 || requested.has("--windows");
const smokeWeb = requested.size === 0 || requested.has("--web");

function testWindows() {
  if (process.platform !== "win32") {
    if (requested.has("--windows")) throw new Error("Windows export smoke requires Windows");
    return;
  }
  const executable = resolve(root, "dist-godot/windows/simplyZOMBIES.exe");
  if (!existsSync(executable))
    throw new Error("Windows export is missing; run npm run godot:export");
  const result = spawnSync(executable, ["--headless", "--quit-after", "3"], {
    encoding: "utf8",
    timeout: 30_000,
  });
  if (result.error !== undefined) throw result.error;
  const output = `${result.stdout}\n${result.stderr}`;
  // ponytail: --quit-after always prints ObjectDB/resource leaks as ERROR and may
  // exit 1; that is shutdown noise, not a failed boot.
  const bootError =
    /SCRIPT ERROR:/.test(output) ||
    /(?:^|\n)ERROR:(?! \d+ resources still in use at exit)/.test(output);
  if (!output.includes("GODOT_R1_READY") || bootError) {
    throw new Error(`Windows export failed to boot:\n${result.stdout}\n${result.stderr}`);
  }
  console.log("GODOT_WINDOWS_EXPORT_SMOKE_OK");
}

function staticServer(directory) {
  const prefix = directory.endsWith(sep) ? directory : `${directory}${sep}`;
  return createServer((request, response) => {
    const pathname = decodeURIComponent(new URL(request.url ?? "/", "http://localhost").pathname);
    const relative = pathname === "/" ? "index.html" : pathname.slice(1);
    const file = resolve(directory, relative);
    if (!file.startsWith(prefix) || !existsSync(file) || !statSync(file).isFile()) {
      response.writeHead(404).end();
      return;
    }
    const mime = {
      ".html": "text/html; charset=utf-8",
      ".js": "text/javascript; charset=utf-8",
      ".pck": "application/octet-stream",
      ".png": "image/png",
      ".wasm": "application/wasm",
    }[extname(file)];
    response.writeHead(200, { "Content-Type": mime ?? "application/octet-stream" });
    createReadStream(file).pipe(response);
  });
}

async function testWeb() {
  const directory = resolve(root, "dist-godot/web");
  if (!existsSync(resolve(directory, "index.html"))) {
    throw new Error("Web export is missing; run npm run godot:export");
  }
  const server = staticServer(directory);
  await new Promise((resolveListen, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolveListen);
  });
  const address = server.address();
  if (address === null || typeof address === "string") throw new Error("Web smoke server failed");

  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width: 1024, height: 720 } });
    const errors = [];
    let ready;
    const godotReady = new Promise((resolveReady) => {
      ready = resolveReady;
    });
    page.on("pageerror", (error) => errors.push(`page: ${String(error)}`));
    page.on("console", (message) => {
      if (message.type() === "error") errors.push(`console: ${message.text()}`);
      if (message.text().includes("GODOT_R1_READY")) ready();
    });
    page.on("response", (response) => {
      if (response.status() >= 400) errors.push(`${response.status()} for ${response.url()}`);
    });
    await page.goto(`http://127.0.0.1:${address.port}/`, {
      waitUntil: "networkidle",
      timeout: 60_000,
    });
    await page.waitForFunction(
      () => {
        const canvas = globalThis.document.querySelector("canvas");
        return (
          canvas instanceof globalThis.HTMLCanvasElement && canvas.width > 0 && canvas.height > 0
        );
      },
      null,
      { timeout: 30_000 },
    );
    let readyTimeout;
    await Promise.race([
      godotReady,
      new Promise((_, reject) => {
        readyTimeout = setTimeout(
          () => reject(new Error("Godot web main scene did not become ready")),
          30_000,
        );
      }),
    ]).finally(() => clearTimeout(readyTimeout));
    if (errors.length > 0) throw new Error(`Web export reported errors:\n${errors.join("\n")}`);
    console.log("GODOT_WEB_EXPORT_SMOKE_OK");
  } finally {
    await browser.close();
    await new Promise((resolveClose) => server.close(resolveClose));
  }
}

if (smokeWindows) testWindows();
if (smokeWeb) await testWeb();
