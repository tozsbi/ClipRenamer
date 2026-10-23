# Downloads the tools ClipRenamer needs for AI naming into .\tools (about 1.8 GB, one time):
#   ffmpeg (reads video frames and sound)  - https://www.gyan.dev/ffmpeg/builds/
#   whisper.cpp (speech to text)           - https://github.com/ggml-org/whisper.cpp
#   whisper large-v3-turbo model (Arabic)  - https://huggingface.co/ggerganov/whisper.cpp
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Tools = Join-Path $PSScriptRoot 'tools'
$Tmp = Join-Path $env:TEMP 'ClipRenamer-setup'
New-Item -ItemType Directory $Tools, (Join-Path $Tools 'whisper'), $Tmp -Force | Out-Null

try {
    if (-not (Test-Path (Join-Path $Tools 'ffmpeg.exe'))) {
        Write-Host '1/3  Downloading ffmpeg...'
        $zip = Join-Path $Tmp 'ffmpeg.zip'
        $url = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
        Invoke-WebRequest $url -OutFile $zip -UseBasicParsing
        $expected = (Invoke-WebRequest "$url.sha256" -UseBasicParsing).Content.Trim()
        if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $expected) { throw 'ffmpeg download is damaged (checksum mismatch)' }
        Expand-Archive $zip (Join-Path $Tmp 'ffmpeg') -Force
        Get-ChildItem (Join-Path $Tmp 'ffmpeg') -Recurse -Include ffmpeg.exe, ffprobe.exe | Copy-Item -Destination $Tools
    }

    if (-not (Test-Path (Join-Path $Tools 'whisper\whisper-cli.exe'))) {
        Write-Host '2/3  Downloading whisper...'
        $rels = Invoke-RestMethod 'https://api.github.com/repos/ggml-org/whisper.cpp/releases?per_page=10'
        $asset = $rels | ForEach-Object { $_.assets } | Where-Object name -eq 'whisper-bin-x64.zip' | Select-Object -First 1
        if (-not $asset) { throw 'could not find whisper-bin-x64.zip on GitHub' }
        $zip = Join-Path $Tmp 'whisper.zip'
        Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing
        Expand-Archive $zip (Join-Path $Tmp 'whisper') -Force
        $rel = Get-ChildItem (Join-Path $Tmp 'whisper') -Recurse -Filter whisper-cli.exe | Select-Object -First 1
        Get-ChildItem $rel.DirectoryName | Where-Object { $_.Extension -eq '.dll' -or $_.Name -eq 'whisper-cli.exe' } |
            Copy-Item -Destination (Join-Path $Tools 'whisper')
    }

    $model = Join-Path $Tools 'whisper\ggml-large-v3-turbo.bin'
    if (-not (Test-Path $model)) {
        Write-Host '3/3  Downloading the speech model (about 1.6 GB, this takes a while)...'
        Invoke-WebRequest 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin' -OutFile "$model.part" -UseBasicParsing
        Move-Item "$model.part" $model -Force
    }
    Write-Host ''
    Write-Host 'Done. All tools are ready.' -ForegroundColor Green
} catch {
    Write-Host ''
    Write-Host "Setup failed: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
Read-Host 'Press Enter to close'
