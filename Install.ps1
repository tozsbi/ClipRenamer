# Registers a Task Scheduler task that runs Move-Clips.ps1 at logon and every 10 minutes, hidden.
$TaskName = 'ClipRenamer - auto move'
$Script = Join-Path $PSScriptRoot 'Move-Clips.ps1'
$Vbs = Join-Path $PSScriptRoot 'run-hidden.vbs'

# wscript + vbs runs PowerShell with no window flashing
Set-Content -LiteralPath $Vbs -Encoding ASCII -Value @"
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""$Script""", 0, False
"@

$user = "$env:USERDOMAIN\$env:USERNAME"
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$Vbs`""
$atLogon = New-ScheduledTaskTrigger -AtLogOn -User $user
$every10 = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1)
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $atLogon, $every10 -Settings $settings -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Write-Host "Installed: '$TaskName' (runs at logon and every 10 minutes)."
