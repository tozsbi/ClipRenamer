# Names OBS clips with AI: looks at 6 frames + what was said in voice chat, then asks Claude for a short name.
#   -Mode Suggest : writes suggestions to names.csv (nothing is renamed)
#   -Mode Apply   : renames the files right away (never overwrites)
# Only clips that still have their OBS name (date/Replay) are processed.
param(
    [string]$Folder,
    [string[]]$Files,
    [ValidateSet('Suggest', 'Apply')][string]$Mode = 'Suggest'
)

$Root = $PSScriptRoot
$LogFile = Join-Path $Root 'log.txt'
$StatusFile = Join-Path $Root 'ai-status.txt'
$SettingsFile = Join-Path $Root 'settings.json'
$CsvFile = Join-Path $Root 'names.csv'
$Tools = Join-Path $Root 'tools'
$Ffmpeg = Join-Path $Tools 'ffmpeg.exe'
$Ffprobe = Join-Path $Tools 'ffprobe.exe'
$Whisper = Join-Path $Tools 'whisper\whisper-cli.exe'
$WhisperModel = Join-Path $Tools 'whisper\ggml-large-v3-turbo.bin'
$Model = 'claude-opus-5-5'
$NamePattern = '^(Replay )?(\d{4}-\d{2}-\d{2} \d{2}-\d{2}-\d{2})'
$VideoExt = '.mp4', '.mkv', '.mov', '.flv'

function Write-Log($msg) {
    Add-Content -LiteralPath $LogFile -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg) -Encoding UTF8
}
function Set-Status($text) { Set-Content -LiteralPath $StatusFile -Value $text -Encoding UTF8 }

# --- Checks ---
foreach ($p in $Ffmpeg, $Ffprobe, $Whisper, $WhisperModel) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Log "AI: missing tool $p. Run Setup-Tools.ps1."; Set-Status 'error:tools'; exit 1 }
}
$cfg = if (Test-Path -LiteralPath $SettingsFile) { Get-Content -LiteralPath $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json }
# 'local' = free AI on this PC through Ollama, 'claude' = Claude API (paid)
$Provider = if ($cfg.Provider) { $cfg.Provider } else { 'local' }
$LocalModel = if ($cfg.LocalModel) { $cfg.LocalModel } else { 'qwen3-vl:8b-instruct' }
$OllamaUrl = 'http://localhost:11434'
$NamedFolder = if ($cfg.NamedFolder) { $cfg.NamedFolder } else { Join-Path $env:USERPROFILE 'iCloudDrive\المقاطع المسمّاة' }

if ($Provider -eq 'claude') {
    if (-not $cfg.ApiKey) { Write-Log 'AI: no API key saved.'; Set-Status 'error:key'; exit 1 }
    try {
        # The key is stored encrypted for this Windows user only
        $sec = ConvertTo-SecureString $cfg.ApiKey
        $ApiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
    } catch { Write-Log 'AI: could not read the saved API key.'; Set-Status 'error:key'; exit 1 }
} else {
    # Make sure Ollama is running
    $up = $false
    try { Invoke-RestMethod "$OllamaUrl/api/version" -TimeoutSec 5 | Out-Null; $up = $true } catch { }
    if (-not $up) {
        $exe = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
        if (-not (Test-Path $exe)) { Write-Log 'AI: Ollama is not installed.'; Set-Status 'error:ollama'; exit 1 }
        Start-Process $exe -ArgumentList 'serve' -WindowStyle Hidden
        foreach ($i in 1..20) { Start-Sleep 1; try { Invoke-RestMethod "$OllamaUrl/api/version" -TimeoutSec 3 | Out-Null; $up = $true; break } catch { } }
        if (-not $up) { Write-Log 'AI: could not start Ollama.'; Set-Status 'error:ollama'; exit 1 }
    }
}

if (-not $Files) {
    if (-not $Folder) { $Folder = $cfg.RenameFolder }
    $Files = @(Get-ChildItem -LiteralPath $Folder -File -ErrorAction SilentlyContinue |
        Where-Object { $VideoExt -contains $_.Extension.ToLower() } | Sort-Object Name | ForEach-Object FullName)
}
$Files = @($Files | Where-Object { (Split-Path $_ -Leaf) -match $NamePattern })
if ($Files.Count -eq 0) { Set-Status 'done:0'; exit 0 }

Add-Type -AssemblyName System.Net.Http
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$http = New-Object System.Net.Http.HttpClient
$http.Timeout = [TimeSpan]::FromMinutes(3)

# Only one naming run at a time (the app button and the auto-move could overlap)
$mutex = New-Object Threading.Mutex($false, 'Local\ClipRenamerNaming')
if (-not $mutex.WaitOne(0)) { Write-Log 'AI: another naming run is already working, skipped.'; exit 0 }

$work = Join-Path $env:TEMP "ClipRenamer\$PID"
New-Item -ItemType Directory $work -Force | Out-Null

$system = @'
You name short gameplay clips recorded with OBS for a Saudi gamer and their friends.
You get one image (6 frames from the clip, left to right, top to bottom) and a speech transcript of the voice chat.
Reply with ONLY the clip name, nothing else:
- Saudi Arabic dialect, 3 to 9 words, like a friend would label the clip.
- Start with the game or app name in Arabic, then " - ", then what happened.
- Prefer the funny or memorable moment from the voice chat (a joke, someone yelling, weird sounds, an argument) over what is on screen.
- Use a player's name only if it is clearly said or clearly shown as the speaker; otherwise say "واحد" or "الشباب".
- The transcript is machine-made and noisy. Lines like "اشتركوا في القناة", "ترجمة نانسي قنقر", "موسيقى" or repeated filler are recognition errors, not real speech: ignore them.
- No quotes, no emoji, no file extension, no date, and none of these characters: \ / : * ? " < > |
Examples of the style (the game part is just a placeholder):
اللعبة - هوشة مين المحور
اللعبة - واحد يصرخ والباقي يضحكون
اللعبة - تقليد صوت زورو
'@

# Games this player plays, with the Arabic name used in file names.
# Small local models guess the game badly from free text, so they first pick from this list.
$Games = [ordered]@{
    'Overwatch'                    = 'أوفرواتش'
    'Deadlock'                     = 'ديدلوك'
    'Elden Ring'                   = 'إلدن رنق'
    'Mimic Party'                  = 'ميمك بارتي'
    'Marvel Rivals'                = 'مارفل رايفلز'
    'Counter-Strike 2'             = 'كاونتر سترايك'
    'Fortnite'                     = 'فورتنايت'
    'League of Legends'            = 'ليق أوف ليجندز'
    'Call of Duty'                 = 'كول أوف ديوتي'
    'VRChat'                       = 'في آر تشات'
    'Discord call or screen share' = 'ديسكورد'
    'Anime or TV show'             = 'أنمي'
    'Web browser'                  = 'المتصفح'
    'Other'                        = ''
}
$GameHints = "Hints: Overwatch is first-person (you see the weapon in the player's hands). Deadlock is third-person (you see the player's character from behind, with a round minimap at the bottom right). Marvel Rivals is third-person with Marvel heroes. If a Discord window is visible around the content, answer 'Discord call or screen share'."

function Invoke-Claude([string]$imageB64, [string]$transcript) {
    $body = @{
        model         = $Model
        max_tokens    = 2000
        output_config = @{ effort = 'low' }
        fallbacks     = 'default'
        system        = $system
        messages      = @(@{
            role    = 'user'
            content = @(
                @{ type = 'image'; source = @{ type = 'base64'; media_type = 'image/jpeg'; data = $imageB64 } },
                @{ type = 'text'; text = "Voice chat transcript:`n$transcript" }
            )
        })
    } | ConvertTo-Json -Depth 10

    $req = New-Object System.Net.Http.HttpRequestMessage 'Post', 'https://api.anthropic.com/v1/messages'
    $req.Headers.Add('x-api-key', $ApiKey)
    $req.Headers.Add('anthropic-version', '2026-10-21')
    $req.Headers.Add('anthropic-beta', 'server-side-fallback-2026-07-01')
    $req.Content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/json')
    $res = $http.SendAsync($req).GetAwaiter().GetResult()
    $bytes = $res.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
    $json = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json

    if (-not $res.IsSuccessStatusCode) {
        $code = [int]$res.StatusCode
        if ($code -eq 401) { throw 'API key is wrong (401)' }
        if ($code -eq 402 -or $json.error.message -match 'credit') { throw 'no credit left on the AI account' }
        throw "AI error $code $($json.error.message)"
    }
    if ($json.stop_reason -eq 'refusal') { throw 'AI declined to name this clip' }
    ($json.content | Where-Object type -eq 'text' | ForEach-Object text) -join ' '
}

function Send-Ollama([hashtable]$body) {
    $req = New-Object System.Net.Http.HttpRequestMessage 'Post', "$OllamaUrl/api/chat"
    $req.Content = New-Object System.Net.Http.StringContent(($body | ConvertTo-Json -Depth 10), [Text.Encoding]::UTF8, 'application/json')
    $res = $http.SendAsync($req).GetAwaiter().GetResult()
    $bytes = $res.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
    $json = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
    if (-not $res.IsSuccessStatusCode) {
        if ($json.error -match 'not found') { throw "local AI model $LocalModel is not downloaded" }
        throw "local AI error: $($json.error)"
    }
    # Some models still write their reasoning in <think> tags
    [string]$json.message.content -replace '(?s)<think>.*?</think>', ''
}

# Step 1 (local AI): pick the game from the fixed list
function Get-LocalGame([string]$imageB64) {
    $options = @($Games.Keys)
    $answer = Send-Ollama @{
        model    = $LocalModel
        stream   = $false
        options  = @{ temperature = 0 }
        format   = @{ type = 'object'; properties = @{ app = @{ type = 'string'; enum = $options } }; required = @('app') }
        messages = @(@{ role = 'user'; content = "These are 6 frames from one screen recording. Which ONE of these is on screen? $GameHints Options: $($options -join ', ')"; images = @($imageB64) })
    }
    try { $Games[($answer | ConvertFrom-Json).app] } catch { '' }
}

# Step 2 (local AI): describe what happened, with the game already decided
function Invoke-Local([string]$imageB64, [string]$transcript, [string]$game, [double]$temperature) {
    $gameLine = if ($game) { "The clip is from: $game. Start the name with exactly `"$game - `"." } else { 'Start with the game or app name in Arabic.' }
    $body = @{
        model    = $LocalModel
        stream   = $false
        think    = $false
        options  = @{ temperature = $temperature; num_predict = 200; repeat_penalty = 1.1 }
        messages = @(
            @{ role = 'system'; content = $system },
            @{ role = 'user'; content = "$gameLine`nVoice chat transcript:`n$transcript`n`nReply with the clip name only, in Saudi Arabic."; images = @($imageB64) }
        )
    }
    $name = Send-Ollama $body
    # Make sure the game part is the one we picked, not a guess
    if ($game) {
        $name = ([string]$name).Trim()
        $rest = if ($name -match '^(.{1,30}?)\s+-\s+(.+)$') { $Matches[2] } else { $name }
        $name = "$game - $rest"
    }
    $name
}

function Get-ClipName([string]$path) {
    $base = [IO.Path]::GetFileNameWithoutExtension($path)
    $jpg = Join-Path $work "$base.jpg"
    $wav = Join-Path $work "$base.wav"

    $dur = [double](& $Ffprobe -v error -show_entries format=duration -of csv=p=0 $path)
    $fps = [math]::Round(6 / [math]::Max($dur, 1), 4)
    & $Ffmpeg -v error -y -i $path -vf "fps=$fps,scale=512:-1,tile=3x2" -frames:v 1 -q:v 4 $jpg
    & $Ffmpeg -v error -y -i $path -vn -ar 16000 -ac 1 $wav
    $threads = [Math]::Max(1, [Environment]::ProcessorCount - 1)
    & $Whisper -m $WhisperModel -l ar -t $threads -otxt -of (Join-Path $work $base) -np $wav 2>$null | Out-Null
    $txtFile = Join-Path $work "$base.txt"
    $transcript = if (Test-Path -LiteralPath $txtFile) { ([string](Get-Content -LiteralPath $txtFile -Raw -Encoding UTF8)).Trim() } else { '' }
    # Drop lines whisper invents when nobody is talking
    $transcript = (($transcript -split "`r?`n") | Where-Object { $_.Trim() -and $_ -notmatch 'اشتركوا في القناة|ترجمة نانسي قنقر|^\s*موسيقى\W*$|^\s*شكرا\W*$' }) -join "`n"
    if (-not $transcript) { $transcript = '(no speech)' }
    if (-not (Test-Path -LiteralPath $jpg)) { throw 'could not read video frames' }

    $imageB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($jpg))
    Remove-Item -LiteralPath $jpg, $wav, $txtFile -ErrorAction SilentlyContinue
    $text = if ($Provider -eq 'claude') { Invoke-Claude $imageB64 $transcript }
        else {
            # Small local models sometimes loop on one word; one retry with more randomness usually fixes it
            $game = Get-LocalGame $imageB64
            try { Invoke-Local $imageB64 $transcript $game 0.4 }
            catch { if ($_.Exception.Message -match 'repeat') { Invoke-Local $imageB64 $transcript $game 0.9 } else { throw } }
        }
    $text = [string](@($text) -join ' ')

    # Clean up into a safe file name
    $name = [string]($text -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
    $name = $name -replace '[\\/:*?"<>|]', '' -replace '\s+', ' '
    $name = $name.Trim().Trim('.').Trim()
    if ($name.Length -gt 80) { $name = $name.Substring(0, 80).Trim() }
    if (-not $name) { throw 'AI returned an empty name' }

    $date = ([regex]::Match($base, $NamePattern)).Groups[2].Value
    "$name - $date$([IO.Path]::GetExtension($path))"
}

# Load existing suggestions so they are kept
$suggest = [ordered]@{}
if (Test-Path -LiteralPath $CsvFile) {
    Get-Content -LiteralPath $CsvFile -Encoding UTF8 | ConvertFrom-Csv | ForEach-Object { $suggest[$_.Old] = $_.New }
}

$i = 0; $ok = 0
foreach ($f in $Files) {
    $i++
    $old = Split-Path $f -Leaf
    Set-Status "run:$i/$($Files.Count)"
    try {
        $new = Get-ClipName $f
    } catch {
        Write-Log "AI FAILED: ${old}: $($_.Exception.Message)"
        # Stop only when no clip can succeed (bad key, no credit, model missing, Ollama down)
        if ($_.Exception.Message -match '401|credit|not downloaded|actively refused|No connection') { break }
        continue
    }
    if ($Mode -eq 'Suggest') {
        $suggest[$old] = $new
        $suggest.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Old = $_.Key; New = $_.Value } } |
            ConvertTo-Csv -NoTypeInformation | Set-Content -LiteralPath $CsvFile -Encoding UTF8
        Write-Log "AI suggested: $old -> $new"
        $ok++
    } else {
        # Named clips go to their own folder so they don't mix with the unnamed ones
        if (-not (Test-Path -LiteralPath $NamedFolder)) { New-Item -ItemType Directory -Path $NamedFolder -Force | Out-Null }
        $target = Join-Path $NamedFolder $new
        $n = 2
        while (Test-Path -LiteralPath $target) {
            $target = Join-Path $NamedFolder ("{0} ({1}){2}" -f [IO.Path]::GetFileNameWithoutExtension($new), $n, [IO.Path]::GetExtension($new)); $n++
        }
        try { Move-Item -LiteralPath $f -Destination $target -ErrorAction Stop; Write-Log "Renamed: $old -> $(Split-Path $target -Leaf)"; $ok++ }
        catch { Write-Log "FAILED: ${old}: $($_.Exception.Message)" }
    }
}
Set-Status "done:$ok"
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
$mutex.ReleaseMutex()
