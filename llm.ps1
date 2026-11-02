param(
    [Parameter(Position = 0)][string]$Prompt = "",
    [string]$System = "",
    [string]$File = "",
    [string]$Model = "",
    [switch]$Reason,          # deepseek-r1: slow, best at hard judgement / math / tricky bugs
    [switch]$Think,           # let a reasoning model think first (slower, better on judgement)
    [switch]$Stdin,
    [string]$Image = "",     # screenshot/photo to read (qwen3.5:9b is a VLM)
    [int]$Ctx = 32768,
    [int]$MaxTokens = 4096,
    [double]$Temp = 0.1,
    [string]$Out = "",
    [switch]$Stats
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$DEFAULT_MODEL = "qwen3.5:9b"
$REASON_MODEL  = "deepseek-r1:8b-0528-qwen3-q4_K_M"
if ($Model -eq "") { $Model = if ($Reason) { $REASON_MODEL } else { $DEFAULT_MODEL } }

$ledger = Join-Path $PSScriptRoot "llm-ledger.csv"
if ($Stats) {
    if (-not (Test-Path $ledger)) { Write-Output "No llm calls recorded yet."; exit 0 }
    $rows = Import-Csv $ledger
    $inTok = ($rows | Measure-Object -Property input_tokens -Sum).Sum
    $outTok = ($rows | Measure-Object -Property output_tokens -Sum).Sum
    $today = $rows | Where-Object { $_.time -like ((Get-Date).ToString("yyyy-MM-dd") + "*") }
    $tIn = ($today | Measure-Object -Property input_tokens -Sum).Sum
    $tOut = ($today | Measure-Object -Property output_tokens -Sum).Sum
    Write-Output ("llm calls: {0} total, {1} today" -f $rows.Count, @($today).Count)
    Write-Output ("Claude tokens avoided (approx): {0:N0} total ({1:N0} today) = {2:N0} input never read + {3:N0} output never written" -f ($inTok+$outTok), ($tIn+$tOut), $inTok, $outTok)
    exit 0
}

$images = @()
if ($Image -ne "") {
    if (-not (Test-Path $Image)) { Write-Error "Image not found: $Image"; exit 2 }
    $images = @([Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $Image))))
}
$attached = ""
if ($File -ne "") {
    if (-not (Test-Path $File)) { Write-Error "File not found: $File"; exit 2 }
    $attached = [IO.File]::ReadAllText($File)
} elseif ($Stdin) {
    $attached = [Console]::In.ReadToEnd()
}
if ($Prompt -eq "" -and $attached -eq "" -and $images.Count -eq 0) { Write-Error "No prompt given"; exit 2 }
if ($attached -ne "") { $Prompt = "$Prompt`n`n<input>`n$attached`n</input>" }

$estTok = [int]($Prompt.Length / 3.5)
if ($estTok -gt ($Ctx - 512)) {
    Write-Error "llm: input is ~$estTok tokens but the context window is $Ctx. The model would silently see only the first part. Slice it first (grep -n / sed -n), or ask a narrower question."
    exit 3
}
if ($System -eq "") {
    $System = "You are a precise assistant. Follow the instructions exactly. Output only what is asked: no preamble, no explanation, no markdown code fences unless explicitly requested. If asked for code, output raw code only."
}

# Reasoning models put their chain of thought in a separate field and will happily
# spend the whole budget there, returning an EMPTY answer. Thinking is therefore off
# unless asked for, and the budget is raised when it is on.
if ($images.Count -gt 0) {
    $System = "You transcribe images literally. Report only what is actually visible. Never guess at text you cannot read - write [unreadable] instead."
}
$body = @{
    model      = $Model
    stream     = $false
    system     = $System
    prompt     = $Prompt
    keep_alive = "5m"
    think      = [bool]$Think
    images     = $images
    options    = @{ num_ctx = $Ctx; num_predict = $(if ($Think) { [math]::Max($MaxTokens, 2048) } else { $MaxTokens }); temperature = $Temp }
} | ConvertTo-Json -Depth 5 -Compress
$bytes = [System.Text.Encoding]::UTF8.GetBytes($body)

try {
    $resp = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" -Method Post -Body $bytes -ContentType "application/json; charset=utf-8" -TimeoutSec 1800
} catch {
    Write-Error "Ollama request failed (is it running? is the model pulled?): $($_.Exception.Message)"; exit 1
}

$text = $resp.response
if ([string]::IsNullOrWhiteSpace($text)) {
    if ($resp.done_reason -eq 'length') {
        Write-Error "llm: the model used its whole budget and returned nothing. If it is a reasoning model, drop -Think or raise -MaxTokens."
        exit 4
    }
    Write-Error "llm: the model returned an empty answer."; exit 4
}
if ($resp.done_reason -eq 'length') { Write-Warning "llm: output hit the token limit and is CUT OFF; raise -MaxTokens." }
if ($resp.prompt_eval_count -ge ($Ctx - 64)) { Write-Warning "llm: input filled the $Ctx-token context window; the model may have seen a TRUNCATED input." }

$text = $text -replace '(?s)^\s*```[a-zA-Z0-9_+-]*\r?\n', '' -replace '(?s)\r?\n```\s*$', ''
# deepseek-r1 embeds its chain of thought inline in the answer (qwen3.5 returns it
# in a separate field); strip it either way so callers only ever get the answer.
$text = [System.Text.RegularExpressions.Regex]::Replace($text, '(?s).*</think>', '')
$text = [System.Text.RegularExpressions.Regex]::Replace($text, '(?s)<think>.*$', '')
$text = $text.Trim()
$text = $text.TrimEnd()

try {
    $tps = if ($resp.eval_duration) { [math]::Round($resp.eval_count / ($resp.eval_duration / 1e9), 1) } else { 0 }
    $row = "{0},{1},{2},{3},{4}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Model, $resp.prompt_eval_count, $resp.eval_count, $tps
    $mtx = New-Object System.Threading.Mutex($false, "Global\qwen-llm-ledger")
    [void]$mtx.WaitOne(5000)
    try {
        if (-not (Test-Path $ledger)) { "time,model,input_tokens,output_tokens,tok_per_s" | Out-File $ledger -Encoding utf8 }
        $row | Out-File $ledger -Append -Encoding utf8
    } finally { $mtx.ReleaseMutex(); $mtx.Dispose() }
} catch {}

if ($Out -ne "") {
    [IO.File]::WriteAllText($Out, $text + "`n", (New-Object System.Text.UTF8Encoding $false))
    Write-Output ("wrote {0} ({1} tokens, {2} tok/s, {3})" -f $Out, $resp.eval_count, $tps, $Model)
} else {
    Write-Output $text
}
