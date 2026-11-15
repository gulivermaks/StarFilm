param(
    [switch]$NoBump,
    [switch]$DebugBuild,
    [switch]$SkipChecks,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$AsciiWorkDir = "D:\Dev\starfilm"
if ($Root -match "[^\x00-\x7F]") {
    if (-not (Test-Path $AsciiWorkDir)) {
        cmd /c mklink /J "$AsciiWorkDir" "$Root" | Out-Null
    }
    Set-Location $AsciiWorkDir
} else {
    Set-Location $Root
}

if ($ExtraArgs -contains "--no-bump") { $NoBump = $true }
if ($env:NO_VERSION_BUMP -eq "1") { $NoBump = $true }

# Ensure D:\Dev toolchains, temp, and caches are active in current shell session
$tmpDir = "D:\Dev\tmp"
if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
$env:TEMP = $tmpDir
$env:TMP = $tmpDir
if (-not $env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME = "D:\Dev\.cache" }
if (-not $env:PUB_CACHE) { $env:PUB_CACHE = "D:\Dev\.pub-cache" }
if (-not $env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME = "D:\Dev\.gradle" }
if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = "D:\Program Files\Android\Sdk" }
if (-not $env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT = "D:\Program Files\Android\Sdk" }
if (-not $env:ANDROID_USER_HOME) { $env:ANDROID_USER_HOME = "D:\Program Files\Android\.android" }
if (Test-Path "D:\Dev\jdk-21\bin\java.exe") {
    $env:JAVA_HOME = "D:\Dev\jdk-21"
} elseif (-not $env:JAVA_HOME) {
    $env:JAVA_HOME = "D:\Program Files\Java\jdk-17"
}

$neededPaths = @(
    "D:\Dev\jdk-21\bin",
    "D:\Dev\flutter\bin",
    "D:\Dev\.pub-cache\bin",
    "D:\Dev\npm-global",
    "C:\Program Files\GitHub CLI"
)
foreach ($p in $neededPaths) {
    if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) {
        $env:Path = "$p;$env:Path"
    }
}

$versionFile = Join-Path $Root "version.txt"
if (-not (Test-Path $versionFile)) {
    Set-Content -Path $versionFile -Value "0" -Encoding ascii
}

$rawCode = (Get-Content -Path $versionFile -Raw).Trim()
$currentCode = 0
if (-not [int]::TryParse($rawCode, [ref]$currentCode)) {
    throw "Invalid version.txt value: '$rawCode'"
}

if ($NoBump) {
    $nextCode = if ($currentCode -le 0) { 1 } else { $currentCode }
} else {
    $nextCode = $currentCode + 1
}

$major = [math]::Floor($nextCode / 100)
$hundredths = $nextCode % 100
$versionName = "{0}.{1:D2}" -f $major, $hundredths

Write-Host "StarFilm target version: $versionName (versionCode=$nextCode, noBump=$NoBump)"

if (-not $SkipChecks) {
    Write-Host "Running flutter analyze..."
    flutter analyze
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host "Running flutter test..."
    flutter test
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$modeFlag = if ($DebugBuild) { "--debug" } else { "--release" }
Write-Host "Building APK ($modeFlag)..."
flutter build apk $modeFlag "--build-name=$versionName" "--build-number=$nextCode"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not $NoBump) {
    $tmpVersion = "$versionFile.tmp"
    Set-Content -Path $tmpVersion -Value "$nextCode" -Encoding ascii
    Move-Item -Path $tmpVersion -Destination $versionFile -Force
}

$apkSource = if ($DebugBuild) {
    Join-Path $Root "build\app\outputs\flutter-apk\app-debug.apk"
} else {
    Join-Path $Root "build\app\outputs\flutter-apk\app-release.apk"
}

if (-not (Test-Path $apkSource)) {
    throw "Built APK not found at $apkSource"
}

$apkOut = Join-Path $Root "StarFilm.apk"
Copy-Item -Path $apkSource -Destination $apkOut -Force
$sizeMb = [math]::Round((Get-Item $apkOut).Length / 1MB, 2)
Write-Host "Built StarFilm.apk v$versionName (code $nextCode, $sizeMb MB)"
