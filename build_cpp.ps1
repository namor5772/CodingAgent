# Build hello_world.cpp -> hello_world_cpp.exe (MSVC x64, Windows subsystem).
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $RepoRoot

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe not found. Install Visual Studio with the Desktop development with C++ workload."
}

$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) {
    throw "MSVC toolset not found. Install the VC++ tools via the Visual Studio Installer."
}

$vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) {
    throw "vcvars64.bat not found at $vcvars"
}

$outExe = Join-Path $RepoRoot "hello_world_cpp.exe"
$bat = Join-Path $env:TEMP ("build_hello_world_{0}.bat" -f [guid]::NewGuid().ToString("N"))

if ($vcvars.Contains('"') -or $RepoRoot.Contains('"')) {
    throw "Paths containing double quotes are not supported: $vcvars / $RepoRoot"
}

# Pass paths to the .bat via env vars instead of interpolating them: cmd expands
# %-sequences and re-splits quotes in baked-in paths when the bat runs.
$env:HW_VCVARS = $vcvars
$env:HW_ROOT = $RepoRoot

@"
@echo off
setlocal
call "%HW_VCVARS%" || exit /b 1
cd /d "%HW_ROOT%" || exit /b 1
cl /nologo /EHsc /std:c++17 /W4 /O2 /DUNICODE /D_UNICODE hello_world.cpp /Fe:hello_world_cpp.exe /link /SUBSYSTEM:WINDOWS user32.lib gdi32.lib comctl32.lib
exit /b %ERRORLEVEL%
"@ | Set-Content -Path $bat -Encoding ASCII

try {
    $p = Start-Process -FilePath "cmd.exe" -ArgumentList @("/c", "`"$bat`"") -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) {
        throw "Build failed with exit code $($p.ExitCode)"
    }
}
finally {
    Remove-Item -LiteralPath $bat -Force -ErrorAction SilentlyContinue
    Remove-Item Env:HW_VCVARS -ErrorAction SilentlyContinue
    Remove-Item Env:HW_ROOT -ErrorAction SilentlyContinue
}

if (-not (Test-Path -LiteralPath $outExe)) {
    throw "Build reported success but $outExe was not created."
}

Write-Output "Built: $outExe"
