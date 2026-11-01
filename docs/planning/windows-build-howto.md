# Rebuilding the Windows executable

How to produce `simplyZOMBIES.exe` on a Windows machine, the way the release job does. The steps
below were run on 2026-11-01 on Windows 11 with Godot 4.7.1 and the pinned export templates. The
exe booted to the title, and the "first person (experimental)" row opened the first-person scene.

Nothing here changes the game code. The engine pin is exact (`scripts/run-godot.mjs`,
`.github/workflows/ci.yml`, `release.yml`). The export templates are pinned by SHA-512 in
`.github/workflows/release.yml`.

## 1. Engine

Install Godot 4.7.1 (win64) to `%LOCALAPPDATA%\Programs\Godot-4.7.1\`, so the runner finds it, or set
`GODOT_BIN` to the console executable. `scripts/run-godot.mjs` rejects any engine whose `--version` does
not start with `4.7.1`.

## 2. Export templates

Download the templates from the URL CI uses, verify the SHA-512, then extract the five entries CI
extracts into `%APPDATA%\Godot\export_templates\4.7.1.stable\`.

```powershell
$archive = "$env:TEMP\Godot_v4.7.1-stable_export_templates.tpz"
Invoke-WebRequest -UseBasicParsing -Uri https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_export_templates.tpz -OutFile $archive
$expected = "afcc83d8d3d298038f19c58744a0d660fa75dd4baa33cb55d1011bb2565a2a8c2381728924564cb909e37c205a23f21b521b23bd057993afd43ae4da0b2f9d47"
$sha = [System.Security.Cryptography.SHA512]::Create()
$fs = [System.IO.File]::OpenRead($archive)
$hash = ([BitConverter]::ToString($sha.ComputeHash($fs)) -replace "-", "").ToLowerInvariant()
$fs.Dispose()
if ($hash -ne $expected) { throw "Template checksum mismatch: $hash" }
```

Then extract `templates/version.txt`, `templates/web_nothreads_release.zip`, `templates/web_release.zip`,
`templates/windows_release_x86_64.exe` and `templates/windows_release_x86_64_console.exe` from the archive
(a zip) into the folder above. The release job does exactly this with `System.IO.Compression`.

Check the results: `version.txt` reads `4.7.1.stable`. Expected sizes: the Windows release template is
about 109 MB, the console one about 0.19 MB, and the two web zips about 10 MB each.

Note: on the machine used here, `Get-FileHash` was not available in Windows PowerShell 5.1, so the hash
was computed with the .NET `SHA512` class above. `sha512sum` from Git Bash gives the same digest.

## 3. Import, then export

A fresh worktree has no import cache, and the first export would run the import inside the export. Run
the import pass on its own first. On the machine used here it took about 4 minutes.

```bash
godot --headless --path godot --editor --quit
```

Then the Windows export, which is the first half of `npm run godot:export`. The output goes to
`dist-godot/windows/` inside the checkout, which is gitignored:

```bash
mkdir -p dist-godot/windows
godot --headless --path godot --export-release "Windows Desktop"
```

Export took about 2 minutes after the import. Do not kill it while it is between "savepack" messages
at 98%: it writes `simplyZOMBIES.tmp` and renames it to `simplyZOMBIES.exe` when done. The web half is
`npm run godot:export:web`.

The preset embeds the game in the exe (`binary_format/embed_pck=true`), so the exe is the whole build.

## 4. Check the exe boots

The repo's own export smoke runs the exe headless for three frames:

```bash
node scripts/smoke-godot-exports.mjs --windows
```

It must print `GODOT_WINDOWS_EXPORT_SMOKE_OK`. To see the title, run the exe directly. The title has
three rows, "new run", "first person (experimental)" and "quit", and "continue" appears only when a save
exists. Move with the arrow keys and press Enter.

## Result from the run on 2026-11-01

| Item | Value |
|---|---|
| Export command exit code | 0 |
| `simplyZOMBIES.exe` size | 148,896,632 bytes |
| `simplyZOMBIES.exe` SHA-512 | `80c2f2c7e217e8d296eb01f903aa579fc24ad3fd0d134ddd6de249804f190430478da7149986e7c1d3606c6740a17e9fcabf0ae6471f509520e4004a203b4687` |
| Export smoke | `GODOT_WINDOWS_EXPORT_SMOKE_OK` |

The exe is not committed. Keep builds outside the repository (for example `C:\Users\<you>\orca\sz-builds\`).

## Troubleshooting

- **The export looks stuck in the reimport stage.** Run the import pass (step 3) to completion first. In
  the earlier attempts on this machine, the export stalled at the reimport stage; the explicit import pass
  then finished in about 4 minutes, and the export after it completed.
- **Templates not found.** The version folder must match the engine exactly, `4.7.1.stable`.
- **Engine rejected.** The version must start with `4.7.1`.
