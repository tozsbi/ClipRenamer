# Moves OBS recordings / replay clips from the Videos folder into iCloud Drive\Clips.
# Never overwrites: if a file with the same name exists, adds " (2)", " (3)", ...
param(
    [string]$Source = "$env:USERPROFILE\Videos",
    [string]$Dest = "$env:USERPROFILE\iCloudDrive\Clips",
    [int]$MinAgeSeconds = 60
)

# Folders chosen in the ClipRenamer app override the defaults
$SettingsFile = Join-Path $PSScriptRoot 'settings.json'
if (Test-Path -LiteralPath $SettingsFile) {
    $cfg = Get-Content -LiteralPath $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $PSBoundParameters.ContainsKey('Source') -and $cfg.Source) { $Source = $cfg.Source }
    if (-not $PSBoundParameters.ContainsKey('Dest') -and $cfg.Dest) { $Dest = $cfg.Dest }
}
$NamedFolder = if ($cfg.NamedFolder) { $cfg.NamedFolder } else { Join-Path $env:USERPROFILE 'iCloudDrive\المقاطع المسمّاة' }
# Clips the user didn't rename within this many hours get their date as name
$GraceHours = if ($null -ne $cfg.GraceHours) { [double]$cfg.GraceHours } else { 24 }

$LogFile = Join-Path $PSScriptRoot 'log.txt'
function Write-Log($msg) {
    $line = "{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg
    Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
}

# Keep the log small
if ((Test-Path -LiteralPath $LogFile) -and (Get-Item -LiteralPath $LogFile).Length -gt 1MB) {
    Get-Content -LiteralPath $LogFile -Tail 500 | Set-Content -LiteralPath $LogFile -Encoding UTF8
}

$destParent = Split-Path $Dest -Parent
if (-not (Test-Path -LiteralPath $destParent)) {
    Write-Log "Destination folder not found ($destParent). If it is iCloud Drive, is iCloud for Windows installed and signed in? Nothing moved."
    exit 1
}
if (-not (Test-Path -LiteralPath $Dest)) { New-Item -ItemType Directory -Path $Dest | Out-Null }

# OBS file names: "2026-10-18 16-39-04.mp4", "Replay 2026-10-23 00-20-09.mp4", "... - Trim.mp4"
$namePattern = '^(Replay )?\d{4}-\d{2}-\d{2} \d{2}-\d{2}-\d{2}'
$extensions = '.mp4', '.mkv', '.mov', '.flv'
$cutoff = (Get-Date).AddSeconds(-$MinAgeSeconds)

$files = Get-ChildItem -LiteralPath $Source -File -ErrorAction SilentlyContinue | Where-Object {
    $extensions -contains $_.Extension.ToLower() -and
    $_.BaseName -match $namePattern -and
    $_.LastWriteTime -lt $cutoff
}

$moved = @()
foreach ($f in $files) {
    # Skip files OBS is still writing
    try { $s = [IO.File]::Open($f.FullName, 'Open', 'ReadWrite', 'None'); $s.Close() }
    catch { Write-Log "Skipped (in use): $($f.Name)"; continue }

    $target = Join-Path $Dest $f.Name
    $n = 2
    while (Test-Path -LiteralPath $target) {
        $target = Join-Path $Dest ("{0} ({1}){2}" -f $f.BaseName, $n, $f.Extension)
        $n++
    }

    try {
        Move-Item -LiteralPath $f.FullName -Destination $target -ErrorAction Stop
        Write-Log "Moved: $($f.Name) -> $target"
        # Mark when it arrived, so the rename wait starts now and not at recording time
        try { (Get-Item -LiteralPath $target).CreationTime = Get-Date } catch { }
        $moved += $target
    } catch {
        Write-Log "FAILED: $($f.Name): $($_.Exception.Message)"
    }
}

# Clips still unnamed after the wait: name them by their date and move them to the named folder
$dateCutoff = (Get-Date).AddHours(-$GraceHours)
$waiting = Get-ChildItem -LiteralPath $Dest -File -ErrorAction SilentlyContinue | Where-Object {
    $extensions -contains $_.Extension.ToLower() -and $_.BaseName -match $namePattern -and $_.CreationTime -lt $dateCutoff
}
foreach ($f in $waiting) {
    if (-not (Test-Path -LiteralPath $NamedFolder)) { New-Item -ItemType Directory -Path $NamedFolder -Force | Out-Null }
    $newBase = $f.BaseName -replace '^Replay ', ''
    $target = Join-Path $NamedFolder ($newBase + $f.Extension)
    $n = 2
    while (Test-Path -LiteralPath $target) {
        $target = Join-Path $NamedFolder ("{0} ({1}){2}" -f $newBase, $n, $f.Extension)
        $n++
    }
    try {
        Move-Item -LiteralPath $f.FullName -Destination $target -ErrorAction Stop
        Write-Log "Dated: $($f.Name) -> $(Split-Path $target -Leaf)"
    } catch {
        Write-Log "FAILED: $($f.Name): $($_.Exception.Message)"
    }
}