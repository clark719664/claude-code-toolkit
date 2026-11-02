Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$modeFile = Join-Path $PSScriptRoot "pet-mode.txt"
if ((Test-Path $modeFile) -and ((Get-Content $modeFile -Raw).Trim() -eq 'vector')) {
    Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',(Join-Path $PSScriptRoot 'savings-pet-vector.ps1') -WindowStyle Hidden
    exit
}

$ledger   = Join-Path $PSScriptRoot "llm-ledger.csv"
$posFile  = Join-Path $PSScriptRoot "savings-pet.pos"
$frameDir = Join-Path $PSScriptRoot "pig\frames3"
$inRate   = 10.0 / 1e6
$outRate  = 50.0 / 1e6

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Qwen Savings Pet" Width="272" SizeToContent="Height" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True"
        ShowInTaskbar="False" ResizeMode="NoResize">
  <StackPanel>
    <Border x:Name="Bubble" CornerRadius="13" Padding="11,7" Background="#F2FFF7FB" HorizontalAlignment="Center" Margin="0,0,0,2" Visibility="Hidden" MaxWidth="252">
      <Border.Effect><DropShadowEffect BlurRadius="10" ShadowDepth="2" Opacity="0.3"/></Border.Effect>
      <TextBlock x:Name="Speech" FontFamily="Segoe UI" FontSize="12" FontWeight="SemiBold" Foreground="#FF5A3E6E" TextWrapping="Wrap" TextAlignment="Center"/>
    </Border>
    <Grid Height="178">
      <Canvas x:Name="Stage" Width="272" Height="178">
        <Ellipse x:Name="Shadow" Fill="#33000000" Width="110" Height="14"/>
        <Image x:Name="Pet" Height="150" Stretch="Uniform" RenderTransformOrigin="0.5,1" SnapsToDevicePixels="True">
          <Image.RenderTransform><TransformGroup><ScaleTransform x:Name="PetScale"/><RotateTransform x:Name="PetTilt"/><TranslateTransform x:Name="PetMove"/></TransformGroup></Image.RenderTransform>
          <Image.Effect><DropShadowEffect BlurRadius="14" ShadowDepth="3" Opacity="0.35"/></Image.Effect>
        </Image>
        <Ellipse x:Name="Cake" Fill="#FFFFD98A" Stroke="#FFCC9A3A" StrokeThickness="1.5" Opacity="0"/>
        <Ellipse x:Name="CakeTop" Fill="#FFFF9FBF" Stroke="#FFD9799F" StrokeThickness="1.2" Opacity="0"/>
        <Canvas x:Name="FX" IsHitTestVisible="False"/>
      </Canvas>
    </Grid>
    <Border CornerRadius="16" Padding="14,10,14,11" BorderThickness="1" BorderBrush="#33FFFFFF" Margin="0,-6,0,0">
      <Border.Background>
        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
          <GradientStop Color="#F2261A44" Offset="0"/><GradientStop Color="#F23A2560" Offset="1"/>
        </LinearGradientBrush>
      </Border.Background>
      <Border.Effect><DropShadowEffect BlurRadius="18" ShadowDepth="3" Opacity="0.5"/></Border.Effect>
      <StackPanel>
        <DockPanel>
          <TextBlock x:Name="Rank" Text="Piglet" FontFamily="Segoe UI" FontSize="12" FontWeight="SemiBold" Foreground="#FFC9B8FF" VerticalAlignment="Center"/>
          <Ellipse x:Name="Dot" Width="9" Height="9" Fill="#FF6EE7A7" HorizontalAlignment="Right" VerticalAlignment="Center"/>
        </DockPanel>
        <TextBlock x:Name="Money" Text="`$0.00" FontFamily="Segoe UI" FontSize="34" FontWeight="Bold" Foreground="#FF9CF5C8" Margin="0,2,0,0"/>
        <TextBlock Text="saved at API rates" FontFamily="Segoe UI" FontSize="10.5" Foreground="#99F3E9FF" Margin="1,-3,0,8"/>
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <StackPanel Grid.Column="0">
            <TextBlock x:Name="Tokens" Text="0" FontFamily="Segoe UI" FontSize="16" FontWeight="SemiBold" Foreground="#FFF3E9FF"/>
            <TextBlock Text="tokens eaten" FontFamily="Segoe UI" FontSize="10" Foreground="#99F3E9FF"/>
          </StackPanel>
          <StackPanel Grid.Column="1">
            <TextBlock x:Name="Calls" Text="0" FontFamily="Segoe UI" FontSize="16" FontWeight="SemiBold" Foreground="#FFF3E9FF"/>
            <TextBlock Text="meals today" FontFamily="Segoe UI" FontSize="10" Foreground="#99F3E9FF"/>
          </StackPanel>
        </Grid>
        <ProgressBar x:Name="Bar" Height="6" Minimum="0" Maximum="1" Value="0" Margin="0,8,0,0" Background="#33FFFFFF" Foreground="#FF9CF5C8" BorderThickness="0"/>
        <TextBlock x:Name="Next" FontFamily="Segoe UI" FontSize="10" Foreground="#77F3E9FF" Margin="0,3,0,0"/>
      </StackPanel>
    </Border>
  </StackPanel>
</Window>
"@
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
foreach ($n in 'Bubble','Speech','Stage','Shadow','Pet','PetScale','PetTilt','PetMove','Cake','CakeTop','FX','Rank','Dot','Money','Tokens','Calls','Bar','Next') { $ui[$n] = $win.FindName($n) }

function SetAt($el, [double]$x, [double]$y) { [System.Windows.Controls.Canvas]::SetLeft($el, $x); [System.Windows.Controls.Canvas]::SetTop($el, $y) }
function SetBox($el, [double]$x, [double]$y, [double]$w, [double]$h) { $el.Width = [math]::Max(0.5,$w); $el.Height = [math]::Max(0.5,$h); SetAt $el ($x - $w/2) ($y - $h/2) }

function Frames([string]$row, [int[]]$idx) {
    $list = New-Object System.Collections.ArrayList
    foreach ($i in $idx) {
        $p = Join-Path $frameDir ("{0}_{1}.png" -f $row, $i)
        if (Test-Path $p) {
            $b = New-Object System.Windows.Media.Imaging.BitmapImage
            $b.BeginInit(); $b.UriSource = New-Object Uri $p; $b.CacheOption = "OnLoad"; $b.EndInit(); $b.Freeze()
            [void]$list.Add($b)
        }
    }
    return ,$list
}
function Join($a, $b) { $l = New-Object System.Collections.ArrayList; foreach ($x in $a) { [void]$l.Add($x) }; foreach ($x in $b) { [void]$l.Add($x) }; return ,$l }

# Every stage has its own full set now, named stage_animation_N.png, so the
# clip map is a straight 1:1 lookup instead of the old by-content guesswork.
$clips = @{
    'base'   = @{ idle = (Frames 'base_idle' @(1,2,3,4,5)); walk = (Frames 'base_walk' @(1,2,3,4,5,6)); happy = (Frames 'base_happy' @(1,2,3,4,5,6))
                 sad = (Frames 'base_sad' @(1,2,3,4,5)); eat = (Frames 'base_eat' @(1,2,3,4)); done = (Frames 'base_done' @(1,2)); sleep = (Frames 'base_sleep' @(1,2,3,4,5,6)) }
    'grow'   = @{ idle = (Frames 'grow_idle' @(1,2,3,4,5)); walk = (Frames 'grow_walk' @(1,2,3,4,5,6)); happy = (Frames 'grow_happy' @(1,2,3,4,5,6))
                 sad = (Frames 'grow_sad' @(1,2,3,4,5)); eat = (Frames 'grow_eat' @(1,2,3,4)); done = (Frames 'grow_done' @(1,2)); sleep = (Frames 'grow_sleep' @(1,2,3,4,5,6)) }
    'chonk'  = @{ idle = (Frames 'chonk_idle' @(1,2,3,4,5)); walk = (Frames 'chonk_walk' @(1,2,3,4,5,6)); happy = (Frames 'chonk_happy' @(1,2,3,4,5,6))
                 sad = (Frames 'chonk_sad' @(1,2,3,4,5)); eat = (Frames 'chonk_eat' @(1,2,3,4)); done = (Frames 'chonk_done' @(1,2)); sleep = (Frames 'chonk_sleep' @(1,2,3,4,5,6)) }
}


if (Test-Path $posFile) { try { $p = (Get-Content $posFile -Raw) -split ','; $win.Left = [double]$p[0]; $win.Top = [double]$p[1] } catch {} }
else { $wa = [System.Windows.SystemParameters]::WorkArea; $win.Left = $wa.Right - 292; $win.Top = $wa.Bottom - 430 }

$menu = New-Object System.Windows.Controls.ContextMenu
$miTop = New-Object System.Windows.Controls.MenuItem; $miTop.Header = "Always on top"; $miTop.IsCheckable = $true; $miTop.IsChecked = $true
$miTop.Add_Click({ $win.Topmost = $miTop.IsChecked })
$miOpen = New-Object System.Windows.Controls.MenuItem; $miOpen.Header = "Open ledger"
$miOpen.Add_Click({ if (Test-Path $ledger) { Start-Process $ledger } })
$miSwap = New-Object System.Windows.Controls.MenuItem; $miSwap.Header = "Switch to drawn pig"
$miSwap.Add_Click({ Set-Content $modeFile "vector"; Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',(Join-Path $PSScriptRoot 'savings-pet-vector.ps1') -WindowStyle Hidden; $win.Close() })
$miExit = New-Object System.Windows.Controls.MenuItem; $miExit.Header = "Put pet away"
$miExit.Add_Click({ $win.Close() })
[void]$menu.Items.Add($miTop); [void]$menu.Items.Add($miOpen); [void]$menu.Items.Add($miSwap); [void]$menu.Items.Add($miExit)
$win.ContextMenu = $menu
$win.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch {} })
$win.Add_LocationChanged({ try { "$($win.Left),$($win.Top)" | Set-Content $posFile } catch {} })

$ranks = @(
    @{ at = 0;   name = "Piglet";        art = 'base'  },
    @{ at = 1;   name = "Snack Pig";     art = 'base'  },
    @{ at = 5;   name = "Chunky Pig";    art = 'grow'  },
    @{ at = 20;  name = "Boss Hog";      art = 'grow'  },
    @{ at = 100; name = "Golden Hog";    art = 'chonk' },
    @{ at = 500; name = "Absolute Unit"; art = 'chonk' }
)
$idleLines = @("oink", "feed me logs", "any boilerplate?", "i eat tokens", "qwen is ready", "big files pls", "*snort*")

# particle pool: hearts, zzz, sparkles, tears - glyphs so they take any colour
$pool = @()
for ($i = 0; $i -lt 14; $i++) {
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.FontFamily = "Segoe UI"; $tb.FontWeight = "Bold"; $tb.Opacity = 0
    [void]$ui.FX.Children.Add($tb)
    $pool += @{ el = $tb; life = 0.0; max = 1.0; x = 0.0; y = 0.0; vx = 0.0; vy = 0.0; g = 0.0 }
}
function Spawn([string]$glyph, [double]$x, [double]$y, [double]$vx, [double]$vy, [double]$life, [string]$color, [double]$size, [double]$grav) {
    foreach ($p in $pool) {
        if ($p.life -le 0) {
            $p.el.Text = $glyph; $p.el.Foreground = $color; $p.el.FontSize = $size
            $p.x = $x; $p.y = $y; $p.vx = $vx; $p.vy = $vy; $p.life = $life; $p.max = $life; $p.g = $grav
            return
        }
    }
}

$script:art = 'base'; $script:state = 'idle'; $script:stateT = 0.0; $script:stateLen = 9e9
$script:frame = 0; $script:nextFrame = [DateTime]::Now
$script:face = 1.0; $script:walkX = 0.0; $script:walkDir = 1.0
$script:chonk = 0.0; $script:chonkTarget = 0.0
$script:pop = 0.0; $script:popT = 0.0
$script:shown = 0.0; $script:target = 0.0; $script:lastCount = -1
$script:online = $true; $script:offlineSince = [DateTime]::MaxValue
$script:bubbleUntil = [DateTime]::MinValue; $script:nextIdle = (Get-Date).AddSeconds(25)
$script:nextShift = (Get-Date).AddSeconds(4); $script:nextWalk = (Get-Date).AddSeconds(30)
$script:lastSpawn = 0.0

function Fmt([double]$n) { if ($n -ge 1000000) { "{0:N1}M" -f ($n/1e6) } elseif ($n -ge 10000) { "{0:N0}k" -f ($n/1e3) } else { "{0:N0}" -f $n } }
function Usd([double]$v) { if ($v -lt 0.1) { "`$" + ("{0:N4}" -f $v) } elseif ($v -lt 100) { "`$" + ("{0:N2}" -f $v) } else { "`$" + ("{0:N0}" -f $v) } }
function Say([string]$t, [int]$secs = 5) { $ui.Speech.Text = $t; $ui.Bubble.Visibility = "Visible"; $script:bubbleUntil = (Get-Date).AddSeconds($secs) }
function RankFor([double]$usd) { $r = $ranks[0]; foreach ($x in $ranks) { if ($usd -ge $x.at) { $r = $x } }; $r }
function NextRank([double]$usd) { foreach ($x in $ranks) { if ($usd -lt $x.at) { return $x } }; return $null }
function ChonkFor([double]$usd) { if ($usd -le 0) { return 0.0 }; [math]::Max(0.0, [math]::Min(1.0, [math]::Log10(1 + $usd * 3) / [math]::Log10(1 + 500 * 3))) }
function Clip([string]$s) { $c = $clips[$script:art]; if ($c.ContainsKey($s) -and $c[$s].Count -gt 0) { return $c[$s] }; return $c['idle'] }
function Enter([string]$s, [double]$len = 9e9) {
    if ($script:state -ne $s) { $script:pop = 1.0; $script:popT = 0.0 }   # squash-and-stretch pop masks the frame jump
    $script:state = $s; $script:stateT = 0.0; $script:stateLen = $len; $script:frame = 0; $script:nextFrame = [DateTime]::Now
}

function Refresh {
    $rows = @()
    if (Test-Path $ledger) { try { $rows = @(Import-Csv $ledger) } catch {} }
    $inTok = 0; $outTok = 0; $tCalls = 0
    $day = (Get-Date).ToString("yyyy-MM-dd")
    foreach ($r in $rows) { $inTok += [double]$r.input_tokens; $outTok += [double]$r.output_tokens; if ($r.time -like "$day*") { $tCalls++ } }
    $usd = $inTok * $inRate + $outTok * $outRate
    $ui.Tokens.Text = Fmt ($inTok + $outTok); $ui.Calls.Text = "$tCalls"
    $script:chonkTarget = ChonkFor $usd

    $rk = RankFor $usd; $nx = NextRank $usd
    $rankChanged = ($ui.Rank.Text -ne $rk.name -and $script:lastCount -ge 0)
    $ui.Rank.Text = $rk.name; $script:art = $rk.art
    if ($nx) { $ui.Bar.Value = [math]::Min(1, ($usd - $rk.at) / ($nx.at - $rk.at)); $ui.Next.Text = (Usd ($nx.at - $usd)) + " to " + $nx.name }
    else     { $ui.Bar.Value = 1; $ui.Next.Text = "max rank. absolute unit." }

    $ate = ($script:lastCount -ge 0 -and $rows.Count -gt $script:lastCount)
    if ($ate) {
        $l = $rows[-1]
        $gain = [double]$l.input_tokens * $inRate + [double]$l.output_tokens * $outRate
        Say ("nom nom! " + (Fmt ([double]$l.input_tokens + [double]$l.output_tokens)) + " tokens, saved " + (Usd $gain)) 6
    }
    $script:lastCount = $rows.Count; $script:target = $usd

    try {
        $null = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 2
        if (-not $script:online) { Say "i'm awake! ollama is back" 5; Enter 'happy' 2.6 }
        $script:online = $true; $script:offlineSince = [DateTime]::MaxValue; $ui.Dot.Fill = "#FF6EE7A7"
    } catch {
        if ($script:online) { Say "zzz... ollama is off" 6; $script:offlineSince = Get-Date }
        $script:online = $false; $ui.Dot.Fill = "#FFFF7A7A"
    }

    if (-not $script:online) {
        if ((Get-Date) -gt $script:offlineSince.AddMinutes(3)) { if ($script:state -ne 'sad') { Enter 'sad' } }
        elseif ($script:state -ne 'sleep') { Enter 'sleep' }
    } elseif ($rankChanged) { Say ("level up! i'm a " + $rk.name + " now") 7; Enter 'levelup' 1.0 }
    elseif ($ate)          { Enter 'eat' 3.0 }
    elseif ($script:state -eq 'sleep' -or $script:state -eq 'sad') { Enter 'idle' }
}

$anim = New-Object System.Windows.Threading.DispatcherTimer
$anim.Interval = [TimeSpan]::FromMilliseconds(33)
$anim.Add_Tick({
    $dt = 0.033; $now = Get-Date
    $script:stateT += $dt; $t = $script:stateT; $st = $script:state
    if ($t -gt $script:stateLen) {
        if ($st -eq 'levelup') { Enter 'happy' 3.2; $t = 0; $st = 'happy' } else { Enter 'idle'; $t = 0; $st = 'idle' }
    }
    if ([math]::Abs($script:chonkTarget - $script:chonk) -gt 0.0005) { $script:chonk += ($script:chonkTarget - $script:chonk) * 0.03 }
    $c = $script:chonk

    # ---- frame selection: the sheet supplies the pose ----
    $clip = Clip $st
    $ms = 200
    switch ($st) { 'idle' { $ms = 560 } 'walk' { $ms = 115 } 'happy' { $ms = 130 } 'eat' { $ms = 170 } 'sad' { $ms = 900 } 'sleep' { $ms = 1300 } 'levelup' { $ms = 400 } }
    if ($st -eq 'eat') {
        if ($t -lt 0.55) { $clip = Clip 'eat'; $ms = 9999 }
        elseif ($t -lt 2.05) { $clip = Clip 'eat' }
        else { $clip = Clip 'done'; $ms = 350 }
    }
    if ($st -eq 'levelup') { $clip = Clip 'happy' }
    if ($now -ge $script:nextFrame) {
        $script:nextFrame = $now.AddMilliseconds($ms)
        if ($st -eq 'idle') {
            # weight shift: step to a neighbouring pose rather than marching through the row
            $step = Get-Random -Minimum -1 -Maximum 2
            $script:frame = [math]::Max(0, [math]::Min($clip.Count - 1, $script:frame + $step))
        } else { $script:frame = ($script:frame + 1) % [math]::Max(1, $clip.Count) }
    }
    if ($script:frame -ge $clip.Count) { $script:frame = 0 }
    $ui.Pet.Source = $clip[$script:frame]

    # ---- motion: this is the animation work layered on the pose ----
    $g = 0.84 + $c * 0.26                       # continuous growth on top of the stepped art
    $sx = 1.0; $sy = 1.0; $y = 0.0; $rot = 0.0
    $breathe = [math]::Sin($t * 2.2) * 0.016

    switch ($st) {
        'idle' {
            $sy = 1 + $breathe; $sx = 1 - $breathe * 0.6
            if ($now -gt $script:nextShift) { $script:pop = 0.6; $script:popT = 0; $script:nextShift = $now.AddSeconds((Get-Random -Minimum 3 -Maximum 8)) }
            if ($script:online -and $now -gt $script:nextWalk) { Enter 'walk' ((Get-Random -Minimum 30 -Maximum 60) / 10.0); $script:nextWalk = $now.AddSeconds((Get-Random -Minimum 35 -Maximum 80)) }
        }
        'walk' {
            $script:walkX += $script:walkDir * 30 * $dt
            if ($script:walkX -gt 44) { $script:walkDir = -1; $script:pop = 0.5; $script:popT = 0 }
            if ($script:walkX -lt -44) { $script:walkDir = 1; $script:pop = 0.5; $script:popT = 0 }
            $script:face = $script:walkDir
            $y = -3.5 * [math]::Abs([math]::Sin($t * 10)); $rot = [math]::Sin($t * 10) * 1.5
        }
        'happy' {
            $ph = $t * 7.0; $s = [math]::Abs([math]::Sin($ph))
            $y = -15 * $s
            $land = [math]::Max(0, 1 - $s * 6)          # squash near the ground, stretch at the top
            $sx = 1 + 0.12 * $land - 0.04 * $s; $sy = 1 - 0.12 * $land + 0.06 * $s
            if ($t - $script:lastSpawn -gt 0.33) { $script:lastSpawn = $t; Spawn ([char]0x2665) (136 + $script:walkX + (Get-Random -Minimum -40 -Maximum 40)) 36 ((Get-Random -Minimum -12 -Maximum 12)) -42 1.4 "#FFFF7FA8" ((Get-Random -Minimum 13 -Maximum 20)) -8 }
        }
        'eat' {
            if ($t -lt 0.55) {
                $k = $t / 0.55; $e = 1 - [math]::Pow(1 - $k, 3)   # ease-out arc in from the left
                $cx = 136 + $script:walkX - 92 + 62 * $e; $cy = 150 - 70 * [math]::Sin($e * [math]::PI) - 10 * $e
                $ui.Cake.Opacity = 1; $ui.CakeTop.Opacity = 1
                SetBox $ui.Cake $cx $cy 22 13; SetBox $ui.CakeTop $cx ($cy - 5) 22 7
            } elseif ($t -lt 2.05) {
                $chew = [math]::Sin($t * 12.5)
                $sx = 1 + 0.05 * $chew; $sy = 1 - 0.05 * $chew; $y = -1.5 * [math]::Abs($chew)
                $shrink = [math]::Max(0.0, 1 - ($t - 0.55) / 1.4)
                $ui.Cake.Opacity = $shrink; $ui.CakeTop.Opacity = $shrink
                SetBox $ui.Cake (136 + $script:walkX - 30) 140 (22 * $shrink) (13 * $shrink); SetBox $ui.CakeTop (136 + $script:walkX - 30) (135) (22 * $shrink) (7 * $shrink)
                if ($t - $script:lastSpawn -gt 0.22) { $script:lastSpawn = $t; Spawn ([char]0x2726) (136 + $script:walkX + (Get-Random -Minimum -22 -Maximum 22)) 104 ((Get-Random -Minimum -30 -Maximum 30)) -25 0.7 "#FFFFE27A" 11 60 }
            } else {
                $ui.Cake.Opacity = 0; $ui.CakeTop.Opacity = 0
                $k = $t - 2.05; $rot = 4 * [math]::Sin($k * 11) * [math]::Exp(-$k * 2.2)   # satisfied wiggle, decaying
                $sy = 1 + 0.05 * [math]::Exp(-$k * 3); $sx = 1 + 0.04 * [math]::Exp(-$k * 3)
            }
        }
        'sad' {
            $sy = 0.965 + $breathe * 0.5; $y = 3; $rot = 0.5 * [math]::Sin($t * 25) * 0.6
            if ($t - $script:lastSpawn -gt 0.7) { $script:lastSpawn = $t; Spawn ([char]0x25CF) (136 + $script:walkX + (Get-Random -Minimum -22 -Maximum 22)) 78 0 20 1.1 "#FF8FD3FF" 10 260 }
        }
        'sleep' {
            $sy = 1 + [math]::Sin($t * 0.9) * 0.035; $sx = 1 - [math]::Sin($t * 0.9) * 0.02; $y = 4
            if ($t - $script:lastSpawn -gt 0.9) { $script:lastSpawn = $t; Spawn "z" (136 + $script:walkX + 46) 60 14 -22 2.2 "#FFC9B8FF" ((Get-Random -Minimum 13 -Maximum 21)) -6 }
        }
        'levelup' {
            $k = $t / 1.0
            $m = 1 + 0.38 * [math]::Exp(-$k * 3.5) * [math]::Sin($k * 14)   # damped spring: pop past 1.0 and settle
            $sx = $m; $sy = $m
            if ($t -lt 0.05 -and $script:lastSpawn -ne -1) { $script:lastSpawn = -1; for ($i = 0; $i -lt 10; $i++) { $a = $i / 10.0 * 6.2832; Spawn ([char]0x2726) (136 + $script:walkX) 90 ([math]::Cos($a) * 90) ([math]::Sin($a) * 90 - 20) 0.9 "#FFFFE27A" 16 40 } }
        }
    }
    if ($st -ne 'levelup' -and $script:lastSpawn -eq -1) { $script:lastSpawn = 0 }
    if ($st -ne 'eat' -and $st -ne 'levelup') { $ui.Cake.Opacity = 0; $ui.CakeTop.Opacity = 0 }

    # transition pop (squash-and-stretch), decays fast
    if ($script:pop -gt 0) {
        $script:popT += $dt; $e = [math]::Exp(-$script:popT * 9) * [math]::Sin($script:popT * 28)
        $sx += 0.10 * $script:pop * $e; $sy -= 0.10 * $script:pop * $e
        if ($script:popT -gt 0.45) { $script:pop = 0 }
    }

    $ui.PetScale.ScaleX = $sx * $g * $script:face; $ui.PetScale.ScaleY = $sy * $g
    $ui.PetTilt.Angle = $rot; $ui.PetMove.X = $script:walkX; $ui.PetMove.Y = $y
    SetAt $ui.Pet (136 - 168 / 2) (178 - 150)
    $shw = 110 * $g * (1 + $y / 60.0); SetBox $ui.Shadow (136 + $script:walkX) 168 $shw (13 * $g)

    foreach ($p in $pool) {
        if ($p.life -gt 0) {
            $p.life -= $dt; $p.vy += $p.g * $dt; $p.x += $p.vx * $dt; $p.y += $p.vy * $dt
            $p.el.Opacity = [math]::Max(0, [math]::Min(1, $p.life / $p.max * 1.4)); SetAt $p.el $p.x $p.y
        } elseif ($p.el.Opacity -gt 0) { $p.el.Opacity = 0 }
    }

    if ([math]::Abs($script:target - $script:shown) -gt 0.00005) {
        $script:shown += ($script:target - $script:shown) * 0.1
        if ([math]::Abs($script:target - $script:shown) -lt 0.00005) { $script:shown = $script:target }
        $ui.Money.Text = Usd $script:shown
    }
    if ($ui.Bubble.Visibility -eq "Visible" -and $now -gt $script:bubbleUntil) { $ui.Bubble.Visibility = "Hidden" }
    if ($script:online -and $now -gt $script:nextIdle) {
        if ($ui.Bubble.Visibility -ne "Visible") { Say ($idleLines | Get-Random) 4 }
        $script:nextIdle = $now.AddSeconds((Get-Random -Minimum 45 -Maximum 110))
    }
})
$poll = New-Object System.Windows.Threading.DispatcherTimer
$poll.Interval = [TimeSpan]::FromSeconds(4)
$poll.Add_Tick({ Refresh })

Refresh
$script:chonk = $script:chonkTarget
$script:shown = $script:target; $ui.Money.Text = Usd $script:shown
Say "hi! i eat the tokens qwen handles" 6
$anim.Start(); $poll.Start()
[void]$win.ShowDialog()
