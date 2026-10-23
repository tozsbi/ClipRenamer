# Renames clips in iCloud Drive\Clips using names.csv (columns: Old,New).
# Never overwrites: skips a row if the new name is already taken.
param([string]$Folder = "$env:USERPROFILE\iCloudDrive\Clips")

$LogFile = Join-Path $PSScriptRoot 'log.txt'
$rows = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'names.csv') -Encoding UTF8 | ConvertFrom-Csv

foreach ($r in $rows) {
    $old = Join-Path $Folder $r.Old
    $new = Join-Path $Folder $r.New
    if (-not (Test-Path -LiteralPath $old)) { $msg = "Not found (skipped): $($r.Old)" }
    elseif (Test-Path -LiteralPath $new) { $msg = "Name taken (skipped): $($r.New)" }
    else {
        try { Rename-Item -LiteralPath $old -NewName $r.New -ErrorAction Stop; $msg = "Renamed: $($r.Old) -> $($r.New)" }
        catch { $msg = "FAILED: $($r.Old): $($_.Exception.Message)" }
    }
    Write-Host $msg
    Add-Content -LiteralPath $LogFile -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg) -Encoding UTF8
}
