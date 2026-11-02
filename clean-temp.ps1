# Reclaim stale files from %TEMP%. Written after 24.6 GB of HLS video cache
# (495k .ts segments from PC Cast) was found sitting on a disk at 3% free.
#
#   clean-temp.ps1                 # what would go, older than 7 days (dry run)
#   clean-temp.ps1 -Days 7 -Go     # actually delete
#   clean-temp.ps1 -Days 0 -Go -Only 'pccast_grid','pccast_web'
param(
    [int]$Days = 7,
    [switch]$Go,
    [string[]]$Only = @(),
    [switch]$Quiet
)
$ErrorActionPreference = 'SilentlyContinue'
$temp = $env:TEMP
$cutoff = (Get-Date).AddDays(-$Days)

# Never touch live agent state: scratchpads and hook counters are in use right now.
$keep = @('claude', 'claude-read-guard', 'claude-turn-guard')

function SizeOf($item) {
    if ($item.PSIsContainer) {
        return ((Get-ChildItem $item.FullName -Recurse -File -Force) | Measure-Object Length -Sum).Sum
    }
    return $item.Length
}

$targets = Get-ChildItem $temp -Force | Where-Object {
    if ($keep -contains $_.Name) { return $false }
    if ($Only.Count -gt 0) { return $Only -contains $_.Name }
    # A directory counts as stale only when nothing inside it is newer than the cutoff.
    if ($_.PSIsContainer) {
        $newest = (Get-ChildItem $_.FullName -Recurse -File -Force | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
        if ($null -eq $newest) { return $_.LastWriteTime -lt $cutoff }
        return $newest -lt $cutoff
    }
    return $_.LastWriteTime -lt $cutoff
}

$total = 0L; $done = 0; $failed = 0
foreach ($t in $targets) {
    $sz = SizeOf $t
    if ($null -eq $sz) { $sz = 0 }
    if (-not $Go) {
        if (-not $Quiet -and $sz -gt 10MB) { '  would free {0,8:N2} GB  {1}' -f ($sz / 1GB), $t.Name }
        $total += $sz; continue
    }
    # rd /s /q tears down huge trees far faster than Remove-Item
    if ($t.PSIsContainer) { & cmd.exe /c rd /s /q "`"$($t.FullName)`"" 2>$null }
    else { Remove-Item $t.FullName -Force -Confirm:$false 2>$null }
    if (Test-Path $t.FullName) { $failed++ } else { $total += $sz; $done++ }
}

$verb = if ($Go) { 'freed' } else { 'would free' }
if (-not $Quiet) {
    '{0} {1:N2} GB from {2} items (older than {3} days){4}' -f $verb, ($total / 1GB), $(if ($Go) { $done } else { @($targets).Count }), $Days, $(if ($failed) { "; $failed still in use, skipped" } else { '' })
    $free = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB
    '  C: now {0:N1} GB free' -f $free
}
