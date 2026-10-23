# Removes the scheduled task. Your clips are not touched.
$TaskName = 'ClipRenamer - auto move'
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Stopped and removed: '$TaskName'."
} else {
    Write-Host "Task '$TaskName' is not installed."
}
