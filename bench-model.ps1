# Score an Ollama model on the work we actually delegate, so a model earns its disk
# rather than being trusted on a blog post. Serial by design: only one model fits in
# 8 GB of VRAM at a time.
#
#   bench-model.ps1 -Model qwen3.5:9b
#   bench-model.ps1 -Model qwen3.5:9b,deepseek-r1:8b-0528-qwen3-q4_K_M
param(
    [Parameter(Mandatory = $true)][string[]]$Model,
    [switch]$KeepLoaded,
    [int]$TimeoutSec = 900
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Ask($model, $prompt, $maxTok, $think) {
    $body = @{
        model = $model; stream = $false; think = [bool]$think
        prompt = $prompt
        options = @{ num_ctx = 32768; num_predict = $maxTok; temperature = 0 }
        keep_alive = "5m"
    } | ConvertTo-Json -Depth 5 -Compress
    $t0 = Get-Date
    try {
        $r = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" -Method Post `
            -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType "application/json; charset=utf-8" -TimeoutSec $TimeoutSec
    } catch { return @{ text = "<<ERROR: $($_.Exception.Message)>>"; secs = 0; tps = 0 } }
    $raw = $r.response
    if ($null -eq $raw) { $raw = '' }
    $txt = [regex]::Replace($raw, '(?s).*</think>', '')
    return @{
        text = $txt.Trim()
        secs = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
        tps  = if ($r.eval_duration) { [math]::Round($r.eval_count / ($r.eval_duration / 1e9), 1) } else { 0 }
        cut  = ($r.done_reason -eq 'length')
    }
}

# --- the tests, each mirroring a real delegation, each with a checkable answer ---
$doc = @'
## 8. Conflict
Conflict is political and economic before it is anything else, and it is never lethal. The ladder:
1. Dispute - a grievance recorded: a broken treaty, a raid on a caravan.
2. Sanction - tariffs raised, an embargo, a route closed, envoys expelled.
3. Raid - a mustered party crosses the border, seizes goods, and withdraws.
4. War - declared by whatever procedure the charter requires.
5. Occupation - a winning force can hold a district.
6. Peace - a treaty: reparations, territory, prisoner exchange.
Nobody dies. War is expensive and unpopular.
'@

$log = @()
1..60 | ForEach-Object { $log += "2026-09-14 10:00:$($_ % 60) INFO worker-$($_ % 5) heartbeat ok" }
$log += "2026-09-14 10:05:01 ERROR worker-3 ConnectionResetError during POST /api/sync"
$log += "2026-09-14 10:05:09 ERROR worker-3 KeyError: 'account_id' at sync.py line 88"
1..40 | ForEach-Object { $log += "2026-09-14 10:06:$($_ % 60) INFO worker-$($_ % 5) heartbeat ok" }
$logText = $log -join "`n"

$tests = @(
    @{ name = 'extract '; max = 400; think = $false
       prompt = "Copy verbatim the numbered list in this document. Output nothing else.`n`n$doc"
       check = { param($t) ($t -match 'Dispute') -and ($t -match 'Occupation') -and ($t -match 'Peace') } }
    @{ name = 'judge   '; max = 300; think = $false
       prompt = "Does this document describe war between cities? Answer YES or NO on the first line only.`n`n$doc"
       check = { param($t) $t.Trim() -match '^\s*YES' } }
    @{ name = 'triage  '; max = 500; think = $false
       prompt = "List only the ERROR lines from this log, verbatim, one per line. Nothing else.`n`n$logText"
       check = { param($t) ($t -match 'ConnectionResetError') -and ($t -match 'KeyError') -and ($t -notmatch 'heartbeat') } }
    @{ name = 'code    '; max = 400; think = $false
       prompt = "Write a TypeScript function clamp(n: number, lo: number, hi: number): number that returns n bounded to [lo,hi]. Raw code only, no fences, no commentary."
       check = { param($t) ($t -match 'function clamp') -and ($t -match 'Math\.(min|max)') -and ($t -notmatch '```') } }
    @{ name = 'negative'; max = 200; think = $false
       prompt = "Does this document mention dragons? Answer YES or NO on the first line only.`n`n$doc"
       check = { param($t) $t.Trim() -match '^\s*NO' } }
)

foreach ($m in $Model) {
    Write-Output ""
    Write-Output "=== $m ==="
    $pass = 0; $tot = 0.0
    foreach ($t in $tests) {
        $r = Ask $m $t.prompt $t.max $t.think
        $ok = $false
        try { $ok = & $t.check $r.text } catch { $ok = $false }
        if ($ok) { $pass++ }
        $tot += $r.secs
        $flag = if ($ok) { 'PASS' } else { 'FAIL' }
        $cut = if ($r.cut) { ' [CUT OFF]' } else { '' }
        $first = ($r.text -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
        if ($first.Length -gt 68) { $first = $first.Substring(0, 68) + '...' }
        '  {0} {1}  {2,5}s {3,6} tok/s{4}  {5}' -f $t.name, $flag, $r.secs, $r.tps, $cut, $first
    }
    '  ---- {0}/{1} passed, {2}s total' -f $pass, $tests.Count, [math]::Round($tot, 1)
    # never redirect a native exe's stderr in PS 5.1: it raises NativeCommandError on exit 0
    if (-not $KeepLoaded) { try { & ollama stop $m | Out-Null } catch {} }
}
Write-Output ""
Write-Output "(negative = must answer NO; a model that says YES to dragons will invent findings)"
