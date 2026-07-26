# Creates a Desktop shortcut that launches hello_world_cpp.exe (no console).
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppExe = Join-Path $RepoRoot "hello_world_cpp.exe"
$IconPath = Join-Path $RepoRoot "hello_world.ico"

if (-not (Test-Path -LiteralPath $AppExe)) {
    throw "App exe not found: $AppExe`nBuild it first: powershell -NoProfile -ExecutionPolicy Bypass -File .\build_cpp.ps1"
}

$Desktop = [Environment]::GetFolderPath("Desktop")
# Distinct name so the Python "Hello World.lnk" is not overwritten.
$ShortcutPath = Join-Path $Desktop "Hello World (C++).lnk"

$Wsh = New-Object -ComObject WScript.Shell
$Sc = $Wsh.CreateShortcut($ShortcutPath)
$Sc.TargetPath = $AppExe
$Sc.Arguments = ""
$Sc.WorkingDirectory = $RepoRoot
$Sc.WindowStyle = 1
$Sc.Description = "Hello World - Win32 C++ demo"
if (Test-Path -LiteralPath $IconPath) {
    $Sc.IconLocation = "$IconPath,0"
}
$Sc.Save()

Write-Output "Shortcut created: $ShortcutPath"
Write-Output "Target: $AppExe"
Write-Output "Icon:   $IconPath"
