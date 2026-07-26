# Creates a Desktop shortcut that launches hello_world.py with pythonw (no console).
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$AppScript = Join-Path $RepoRoot "hello_world.py"
$IconPath = Join-Path $RepoRoot "hello_world.ico"

if (-not (Test-Path -LiteralPath $AppScript)) {
    throw "App script not found: $AppScript"
}

# Prefer pythonw.exe (no console window) next to the same python on PATH.
$pythonCmd = Get-Command python -ErrorAction Stop
$pythonDir = Split-Path -Parent $pythonCmd.Source
$pythonw = Join-Path $pythonDir "pythonw.exe"
if (-not (Test-Path -LiteralPath $pythonw)) {
    $pythonw = $pythonCmd.Source  # fall back to python.exe
}

$Desktop = [Environment]::GetFolderPath("Desktop")
$ShortcutPath = Join-Path $Desktop "Hello World.lnk"

$Wsh = New-Object -ComObject WScript.Shell
$Sc = $Wsh.CreateShortcut($ShortcutPath)
$Sc.TargetPath = $pythonw
$Sc.Arguments = "`"$AppScript`""
$Sc.WorkingDirectory = $RepoRoot
$Sc.WindowStyle = 1
$Sc.Description = "Hello World - Tkinter demo"
if (Test-Path -LiteralPath $IconPath) {
    $Sc.IconLocation = "$IconPath,0"
}
$Sc.Save()

Write-Output "Shortcut created: $ShortcutPath"
Write-Output "Target: $pythonw $AppScript"
Write-Output "Icon:   $IconPath"
