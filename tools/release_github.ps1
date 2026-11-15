param(
    [string]$Notes = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$ghExe = "C:\Program Files\GitHub CLI\gh.exe"
if (-not (Test-Path $ghExe)) {
    $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $ghCmd) { throw "GitHub CLI (gh) not found." }
    $ghExe = $ghCmd.Source
}

$apksigner = "D:\Program Files\Android\Sdk\build-tools\34.0.0\apksigner.bat"
if (-not (Test-Path $apksigner)) {
    throw "apksigner.bat not found at $apksigner"
}

# Build using current version without double-bumping, or ensure tests pass first
& (Join-Path $PSScriptRoot "build_apk.ps1") -NoBump
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$apkPath = Join-Path $Root "StarFilm.apk"
if (-not (Test-Path $apkPath)) { throw "StarFilm.apk missing." }

Write-Host "Verifying APK signature..."
& $apksigner verify --print-certs $apkPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$code = [int](Get-Content -Path (Join-Path $Root "version.txt") -Raw).Trim()
if ($code -le 0) { throw "version.txt must be >= 1 before releasing." }
$ver = "{0}.{1:D2}" -f [math]::Floor($code / 100), ($code % 100)
$tag = "v$ver"
$sha256 = (Get-FileHash -Path $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()

if ([string]::IsNullOrWhiteSpace($Notes)) {
    $Notes = "StarFilm $tag (versionCode $code)`nSHA-256: $sha256"
}

if ($DryRun) {
    Write-Host "[DryRun] Would tag $tag and publish StarFilm.apk to gulivermaks/StarFilm"
    Write-Host $Notes
    exit 0
}

git tag -a $tag -m "StarFilm $tag"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

git push origin HEAD --tags
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $ghExe release create $tag $apkPath --repo gulivermaks/StarFilm --title "StarFilm $tag" --notes $Notes
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Published release $tag to gulivermaks/StarFilm (SHA-256: $sha256)"
