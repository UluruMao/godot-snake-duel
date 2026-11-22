param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [string]$Python = 'python',
    [string]$VsDevCmd,
    [ValidateSet('Debug', 'Release', 'Both')][string]$Target = 'Both',
    [ValidateRange(1, 32)][int]$Jobs = 4
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskCache = Join-Path $taskRoot '.godot\native_ai'
$taskDeps = Get-Content -LiteralPath (Join-Path $taskRoot 'native\dependencies.json') -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Force -Path $taskCache,(Join-Path $taskCache 'tmp') | Out-Null
$taskPython = (Get-Command $Python -ErrorAction Stop).Source
$taskGodot = (Get-Item -LiteralPath $Godot).FullName
if (-not $VsDevCmd) {
    $taskVsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $taskVsWhere) {
        $taskInstall = & $taskVsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($taskInstall) { $VsDevCmd = Join-Path $taskInstall 'Common7\Tools\VsDevCmd.bat' }
    }
}
if (-not $VsDevCmd -or -not (Test-Path -LiteralPath $VsDevCmd)) { throw 'Pass -VsDevCmd with the Visual Studio x64 C++ developer command script.' }
$VsDevCmd = (Get-Item -LiteralPath $VsDevCmd).FullName
$taskBindings = Join-Path $taskCache 'godot-cpp'
if (-not (Test-Path -LiteralPath $taskBindings)) {
    & git clone --depth 1 --no-checkout $taskDeps.godot_cpp_repository $taskBindings
    if ($LASTEXITCODE -ne 0) { throw 'Could not download the official godot-cpp dependency.' }
    & git -C $taskBindings fetch --depth 1 origin $taskDeps.godot_cpp_revision
    if ($LASTEXITCODE -ne 0) { throw 'Could not fetch pinned godot-cpp revision.' }
    & git -C $taskBindings checkout --detach $taskDeps.godot_cpp_revision
    if ($LASTEXITCODE -ne 0) { throw 'Could not check out pinned godot-cpp revision.' }
}
$taskRevision = & git -C $taskBindings rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $taskRevision -ne $taskDeps.godot_cpp_revision) { throw 'Cached godot-cpp does not match native/dependencies.json; preserve local edits and use a clean dependency cache.' }
$taskOldTemp = $env:TEMP
$taskOldTmp = $env:TMP
try {
    $env:TEMP = Join-Path $taskCache 'tmp'
    $env:TMP = $env:TEMP
    if (-not (Test-Path -LiteralPath (Join-Path $taskCache 'python\SCons\__init__.py'))) {
        & $taskPython -m pip install --disable-pip-version-check --no-compile --cache-dir (Join-Path $taskCache 'pip-cache') --target (Join-Path $taskCache 'python') ('scons==' + $taskDeps.scons_version)
        if ($LASTEXITCODE -ne 0) { throw 'Could not install task-local SCons.' }
    }
    Push-Location $taskCache
    try {
        & $taskGodot --headless --dump-extension-api
        if ($LASTEXITCODE -ne 0) { throw 'Could not obtain the installed engine API.' }
    } finally { Pop-Location }
    $taskApi = Get-Content -LiteralPath (Join-Path $taskCache 'extension_api.json') -Raw | ConvertFrom-Json
    if ($taskApi.header.version_major -ne 4 -or $taskApi.header.version_minor -ne 7) { throw 'This integration currently targets Godot 4.7. Use the documented version or deliberately update the API target.' }
    $taskTargets = if ($Target -eq 'Both') { @('template_debug','template_release') } elseif ($Target -eq 'Debug') { @('template_debug') } else { @('template_release') }
    foreach ($taskBuild in $taskTargets) {
        # All generated helpers and dependencies stay in the ignored task cache.
        $taskBatch = Join-Path $taskCache ('build_' + $taskBuild + '.cmd')
        $taskLines = @(
            '@echo off',
            ('call "' + $VsDevCmd + '" -arch=x64 -host_arch=x64 >nul'),
            'if errorlevel 1 exit /b 1',
            ('cd /d "' + $taskRoot + '"'),
            ('set "PYTHONPATH=' + (Join-Path $taskCache 'python') + '"'),
            ('set "TEMP=' + $env:TEMP + '"'),
            'set "TMP=%TEMP%"',
            'set "PROCESSOR_ARCHITECTURE=AMD64"',
            ('"' + $taskPython + '" -m SCons -C native -j' + $Jobs + ' platform=windows arch=x86_64 target=' + $taskBuild + ' optimize=speed debug_symbols=no build_profile="' + (Join-Path $taskRoot 'native\build_profile.json') + '" custom_api_file="' + (Join-Path $taskCache 'extension_api.json') + '"'),
            'exit /b %errorlevel%'
        )
        [System.IO.File]::WriteAllLines($taskBatch, $taskLines, [System.Text.UTF8Encoding]::new($false))
        & cmd.exe /d /c $taskBatch
        if ($LASTEXITCODE -ne 0) { throw "Native $taskBuild build failed. Close running Snake Duel editor/game processes before rebuilding a loaded Windows DLL." }
    }
} finally { $env:TEMP = $taskOldTemp; $env:TMP = $taskOldTmp }
Write-Output 'NATIVE AI BUILD: PASS (Windows x86_64)'
