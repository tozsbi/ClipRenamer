# Registers a Task Scheduler task that runs Move-Clips.ps1 once every 24 hours, hidden.
# If the PC was off at that time, it runs as soon as possible afterwards.
$TaskName = 'ClipRenamer - auto move'
$Script = Join-Path $PSScriptRoot 'Move-Clips.ps1'
$Vbs = Join-Path $PSScriptRoot 'run-hidden.vbs'

# wscript + vbs runs PowerShell with no window flashing
Set-Content -LiteralPath $Vbs -Encoding ASCII -Value @"
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$Script""", 0, False
"@

$user = "$env:USERDOMAIN\$env:USERNAME"
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$Vbs`""
$daily = New-ScheduledTaskTrigger -Daily -At (Get-Date)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1)
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $daily -Settings $settings -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Write-Host "Installed: '$TaskName' (runs every 24 hours)."
