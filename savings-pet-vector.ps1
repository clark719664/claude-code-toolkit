Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$ledger  = Join-Path $PSScriptRoot "llm-ledger.csv"
$posFile = Join-Path $PSScriptRoot "savings-pet.pos"
$inRate  = 10.0 / 1e6
$outRate = 50.0 / 1e6

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Qwen Savings Pet" Width="264" SizeToContent="Height" WindowStyle="None"
        AllowsTransparency="True" Background="Transparent" Topmost="True"
        ShowInTaskbar="False" ResizeMode="NoResize">
  <StackPanel>
    <Border x:Name="Bubble" CornerRadius="13" Padding="11,7" Background="#F2FFF7FB" HorizontalAlignment="Center" Margin="0,0,0,2" Visibility="Hidden" MaxWidth="244">
      <Border.Effect><DropShadowEffect BlurRadius="10" ShadowDepth="2" Opacity="0.3"/></Border.Effect>
      <TextBlock x:Name="Speech" FontFamily="Segoe UI" FontSize="12" FontWeight="SemiBold" Foreground="#FF5A3E6E" TextWrapping="Wrap" TextAlignment="Center"/>
    </Border>

    <Canvas x:Name="Stage" Width="264" Height="150">
      <Canvas.RenderTransform><TranslateTransform x:Name="StageMove"/></Canvas.RenderTransform>

      <TextBlock x:Name="Z1" Text="z" FontFamily="Segoe UI" FontSize="15" FontWeight="Bold" Foreground="#FFC9B8FF" Opacity="0"/>
      <TextBlock x:Name="Z2" Text="z" FontFamily="Segoe UI" FontSize="19" FontWeight="Bold" Foreground="#FFC9B8FF" Opacity="0"/>
      <TextBlock x:Name="H1" Text="&#9829;" FontSize="16" Foreground="#FFFF8FB4" Opacity="0"/>
      <TextBlock x:Name="H2" Text="&#9829;" FontSize="12" Foreground="#FFFFB3CC" Opacity="0"/>

      <Path x:Name="Tail" Stroke="#FFE08BAE" StrokeThickness="4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Fill="Transparent"/>
      <Ellipse x:Name="LegBL" Fill="#FFD98FB2"/>
      <Ellipse x:Name="LegBR" Fill="#FFD98FB2"/>
      <Ellipse x:Name="Body"  Fill="#FFFBBFD5" Stroke="#FFDD8FB0" StrokeThickness="2"/>
      <Ellipse x:Name="LegFL" Fill="#FFEBA6C4"/>
      <Ellipse x:Name="LegFR" Fill="#FFEBA6C4"/>
      <Ellipse x:Name="Belly" Fill="#FFFFD6E4" Opacity="0.75"/>

      <Path x:Name="EarL" Fill="#FFF3A9C6" Stroke="#FFDD8FB0" StrokeThickness="2" StrokeLineJoin="Round"/>
      <Path x:Name="EarR" Fill="#FFF3A9C6" Stroke="#FFDD8FB0" StrokeThickness="2" StrokeLineJoin="Round"/>
      <Ellipse x:Name="Head" Fill="#FFFCC6DA" Stroke="#FFDD8FB0" StrokeThickness="2"/>
      <Ellipse x:Name="CheekL" Fill="#66FF7EB0"/>
      <Ellipse x:Name="CheekR" Fill="#66FF7EB0"/>
      <Ellipse x:Name="EyeL" Fill="#FF2B1B3A"/>
      <Ellipse x:Name="EyeR" Fill="#FF2B1B3A"/>
      <Ellipse x:Name="GlintL" Fill="White"/>
      <Ellipse x:Name="GlintR" Fill="White"/>
      <Path x:Name="LidL" Stroke="#FF2B1B3A" StrokeThickness="2.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Opacity="0"/>
      <Path x:Name="LidR" Stroke="#FF2B1B3A" StrokeThickness="2.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Opacity="0"/>
      <Ellipse x:Name="Snout" Fill="#FFF79FBF" Stroke="#FFD9799F" StrokeThickness="2"/>
      <Ellipse x:Name="NoseL" Fill="#FFB5567F"/>
      <Ellipse x:Name="NoseR" Fill="#FFB5567F"/>
      <Path x:Name="Bow" Fill="#FFE8455F" Stroke="#FFB92B44" StrokeThickness="1.5" StrokeLineJoin="Round"/>
      <Ellipse x:Name="BowKnot" Fill="#FFC7revised"/>

      <Ellipse x:Name="Food" Fill="#FFFFD98A" Stroke="#FFCC9A3A" StrokeThickness="2" Opacity="0"/>
      <TextBlock x:Name="Crumb" Text="&#10024;" FontSize="13" Opacity="0"/>
    </Canvas>

    <Border CornerRadius="16" Padding="14,10,14,11" BorderThickness="1" BorderBrush="#33FFFFFF" Margin="0,-4,0,0">
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
$xaml.InnerXml = $xaml.InnerXml -replace '#FFC7revised', '#FFC7304A'
$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
foreach ($n in 'Bubble','Speech','Stage','StageMove','Z1','Z2','H1','H2','Tail','LegBL','LegBR','Body','LegFL','LegFR','Belly',
                'EarL','EarR','Head','CheekL','CheekR','EyeL','EyeR','GlintL','GlintR','LidL','LidR','Snout','NoseL','NoseR',
                'Bow','BowKnot','Food','Crumb','Rank','Dot','Money','Tokens','Calls','Bar','Next') { $ui[$n] = $win.FindName($n) }

function SetBox($el, [double]$x, [double]$y, [double]$w, [double]$h) {
    $el.Width = [math]::Max(0.5, $w); $el.Height = [math]::Max(0.5, $h)
    [System.Windows.Controls.Canvas]::SetLeft($el, $x - $w / 2)
    [System.Windows.Controls.Canvas]::SetTop($el, $y - $h / 2)
}
function SetAt($el, [double]$x, [double]$y) {
    [System.Windows.Controls.Canvas]::SetLeft($el, $x); [System.Windows.Controls.Canvas]::SetTop($el, $y)
}
function Geom([string]$d) { [System.Windows.Media.Geometry]::Parse($d) }

if (Test-Path $posFile) {
    try { $p = (Get-Content $posFile -Raw) -split ','; $win.Left = [double]$p[0]; $win.Top = [double]$p[1] } catch {}
} else {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $win.Left = $wa.Right - 284; $win.Top = $wa.Bottom - 400
}

$menu = New-Object System.Windows.Controls.ContextMenu
$miTop = New-Object System.Windows.Controls.MenuItem; $miTop.Header = "Always on top"; $miTop.IsCheckable = $true; $miTop.IsChecked = $true
$miTop.Add_Click({ $win.Topmost = $miTop.IsChecked })
$miOpen = New-Object System.Windows.Controls.MenuItem; $miOpen.Header = "Open ledger"
$miOpen.Add_Click({ if (Test-Path $ledger) { Start-Process $ledger } })
$miSwap = New-Object System.Windows.Controls.MenuItem; $miSwap.Header = "Switch to sprite pig"
$miSwap.Add_Click({ Set-Content (Join-Path $PSScriptRoot "pet-mode.txt") "sprite"; Start-Process wscript.exe -ArgumentList ('"' + (Join-Path $PSScriptRoot "Qwen Savings Pet.vbs") + '"'); $win.Close() })
$miExit = New-Object System.Windows.Controls.MenuItem; $miExit.Header = "Put pet away"
$miExit.Add_Click({ $win.Close() })
[void]$menu.Items.Add($miTop); [void]$menu.Items.Add($miOpen); [void]$menu.Items.Add($miSwap); [void]$menu.Items.Add($miExit)
$win.ContextMenu = $menu
$win.Add_MouseLeftButtonDown({ try { $win.DragMove() } catch {} })
$win.Add_LocationChanged({ try { "$($win.Left),$($win.Top)" | Set-Content $posFile } catch {} })

$ranks = @(
    @{ at = 0;   name = "Piglet" },
    @{ at = 1;   name = "Snack Pig" },
    @{ at = 5;   name = "Chunky Pig" },
    @{ at = 20;  name = "Boss Hog" },
    @{ at = 100; name = "Golden Hog" },
    @{ at = 500; name = "Absolute Unit" }
)
$idleLines = @("oink", "feed me logs", "any boilerplate?", "i eat tokens", "qwen is ready", "big files pls", "*snort*")

$script:chonk       = 0.0     # 0..1, how fat the pig is - grows with savings
$script:chonkTarget = 0.0
$script:state       = 'idle'
$script:stateUntil  = [DateTime]::MaxValue
$script:phase       = 0.0
$script:shown       = 0.0
$script:target      = 0.0
$script:lastCount   = -1
$script:online      = $true
$script:offlineSince = [DateTime]::MaxValue
$script:bubbleUntil  = [DateTime]::MinValue
$script:nextIdle     = (Get-Date).AddSeconds(25)
$script:nextBlink    = (Get-Date).AddSeconds(3)
$script:blinkUntil   = [DateTime]::MinValue

function Fmt([double]$n) { if ($n -ge 1000000) { "{0:N1}M" -f ($n/1e6) } elseif ($n -ge 10000) { "{0:N0}k" -f ($n/1e3) } else { "{0:N0}" -f $n } }
function Usd([double]$v) { if ($v -lt 0.1) { "`$" + ("{0:N4}" -f $v) } elseif ($v -lt 100) { "`$" + ("{0:N2}" -f $v) } else { "`$" + ("{0:N0}" -f $v) } }
function Say([string]$t, [int]$secs = 5) { $ui.Speech.Text = $t; $ui.Bubble.Visibility = "Visible"; $script:bubbleUntil = (Get-Date).AddSeconds($secs) }
function RankFor([double]$usd) { $r = $ranks[0]; foreach ($x in $ranks) { if ($usd -ge $x.at) { $r = $x } }; $r }
function NextRank([double]$usd) { foreach ($x in $ranks) { if ($usd -lt $x.at) { return $x } }; return $null }
function Enter([string]$s, [double]$secs) { $script:state = $s; $script:stateUntil = (Get-Date).AddSeconds($secs); $script:phase = 0 }

# Growth curve: log-ish so early savings visibly fatten the pig and it never maxes out early.
function ChonkFor([double]$usd) {
    if ($usd -le 0) { return 0.0 }
    $c = [math]::Log10(1 + $usd * 3) / [math]::Log10(1 + 500 * 3)
    return [math]::Max(0.0, [math]::Min(1.0, $c))
}

function Draw {
    $t = $script:phase
    $c = $script:chonk
    $st = $script:state

    $breathe = [math]::Sin($t * 2.0) * (0.8 + $c * 0.7)
    if ($st -eq 'sleep') { $breathe = [math]::Sin($t * 0.9) * (1.8 + $c * 1.6) }

    $cx = 132.0
    $hop = 0.0
    if ($st -eq 'happy') { $hop = -[math]::Abs([math]::Sin($t * 6.5)) * 12 }
    if ($st -eq 'eat')   { $hop = -[math]::Abs([math]::Sin($t * 7.0)) * 4 }
    if ($st -eq 'sleep') { $hop = 4 }
    $ui.StageMove.Y = $hop

    # Front-facing sitting pig, laid out on fixed anchors so head, body and bow never
    # collide. Growth widens the body far more than it heightens it and puffs the cheeks.
    $bw = 92 + $c * 70
    $bh = 58 + $c * 22 + $breathe
    $by = 104.0
    SetBox $ui.Body $cx $by $bw $bh
    SetBox $ui.Belly $cx ($by + $bh * 0.16) ($bw * 0.55) ($bh * 0.46)

    $legW = 16 + $c * 6; $legH = 12 + $c * 2
    $legY = $by + $bh * 0.44
    SetBox $ui.LegFL ($cx - $bw * 0.22) $legY $legW $legH
    SetBox $ui.LegFR ($cx + $bw * 0.22) $legY $legW $legH
    SetBox $ui.LegBL ($cx - $bw * 0.40) ($legY - 3) ($legW * 0.7) ($legH * 0.8)
    SetBox $ui.LegBR ($cx + $bw * 0.40) ($legY - 3) ($legW * 0.7) ($legH * 0.8)

    $tx = $cx + $bw / 2 - 2
    $ty = $by + 2
    $wig = [math]::Sin($t * 3.0) * 3
    $ui.Tail.Data = Geom ("M {0},{1} c 11,-5 15,6 7,9 c -6,2 -9,-3 -5,-6" -f $tx, ($ty + $wig))

    $hw = 68 + $c * 22
    $hh = 60 + $c * 16
    $dip = 0.0
    if ($st -eq 'eat') { $dip = 5 + [math]::Sin($t * 7.0) * 3 }
    $hy = 54.0 + $dip + $breathe * 0.5
    if ($st -eq 'sleep') { $hy = 62.0 }
    SetBox $ui.Head $cx $hy $hw $hh

    # ears: soft leaf shapes angled outward from the top of the head
    $eo = $hw * 0.33; $eu = $hh * 0.34
    $flap = if ($st -eq 'happy') { [math]::Sin($t * 6.5) * 3.5 } else { [math]::Sin($t * 2.0) * 1.0 }
    $ui.EarL.Data = Geom ("M {0},{1} C {2},{3} {4},{5} {6},{7} Z" -f `
        ($cx - $eo * 0.35), ($hy - $eu * 0.80), `
        ($cx - $eo * 1.35), ($hy - $eu - 16 - $flap), `
        ($cx - $eo * 1.30), ($hy - $eu * 0.20), `
        ($cx - $eo * 0.62), ($hy - $eu * 0.10))
    $ui.EarR.Data = Geom ("M {0},{1} C {2},{3} {4},{5} {6},{7} Z" -f `
        ($cx + $eo * 0.35), ($hy - $eu * 0.80), `
        ($cx + $eo * 1.35), ($hy - $eu - 16 + $flap), `
        ($cx + $eo * 1.30), ($hy - $eu * 0.20), `
        ($cx + $eo * 0.62), ($hy - $eu * 0.10))

    $eyeO = $hw * 0.20; $eyeY = $hy - $hh * 0.14
    $blinking = ((Get-Date) -lt $script:blinkUntil)
    $shut = ($st -eq 'sleep') -or $blinking
    $smiley = ($st -eq 'happy')
    $eh = 12 + $c * 2
    SetBox $ui.EyeL ($cx - $eyeO) $eyeY (9.5 + $c) $eh
    SetBox $ui.EyeR ($cx + $eyeO) $eyeY (9.5 + $c) $eh
    $vis = if ($shut -or $smiley) { 0 } else { 1 }
    $ui.EyeL.Opacity = $vis; $ui.EyeR.Opacity = $vis
    SetBox $ui.GlintL ($cx - $eyeO + 2.5) ($eyeY - 3.5) 3.2 3.2
    SetBox $ui.GlintR ($cx + $eyeO + 2.5) ($eyeY - 3.5) 3.2 3.2
    $ui.GlintL.Opacity = $vis; $ui.GlintR.Opacity = $vis

    if ($shut) {
        $ui.LidL.Opacity = 1; $ui.LidR.Opacity = 1
        $ui.LidL.Data = Geom ("M {0},{1} q 6,5 12,0" -f ($cx - $eyeO - 6), $eyeY)
        $ui.LidR.Data = Geom ("M {0},{1} q 6,5 12,0" -f ($cx + $eyeO - 6), $eyeY)
    } elseif ($smiley) {
        $ui.LidL.Opacity = 1; $ui.LidR.Opacity = 1
        $ui.LidL.Data = Geom ("M {0},{1} q 6,-7 12,0" -f ($cx - $eyeO - 6), ($eyeY + 3))
        $ui.LidR.Data = Geom ("M {0},{1} q 6,-7 12,0" -f ($cx + $eyeO - 6), ($eyeY + 3))
    } else { $ui.LidL.Opacity = 0; $ui.LidR.Opacity = 0 }

    $chW = 16 + $c * 14
    SetBox $ui.CheekL ($cx - $hw * 0.34) ($eyeY + $hh * 0.19) $chW (9 + $c * 5)
    SetBox $ui.CheekR ($cx + $hw * 0.34) ($eyeY + $hh * 0.19) $chW (9 + $c * 5)

    $chew = if ($st -eq 'eat') { [math]::Abs([math]::Sin($t * 9.0)) * 0.20 } else { 0 }
    $sw = (30 + $c * 12) * (1 + $chew)
    $sh = (21 + $c * 7) * (1 + $chew * 0.5)
    $sy = $hy + $hh * 0.20
    SetBox $ui.Snout $cx $sy $sw $sh
    SetBox $ui.NoseL ($cx - $sw * 0.17) $sy 5 6
    SetBox $ui.NoseR ($cx + $sw * 0.17) $sy 5 6

    $bowY = $hy + $hh * 0.50 + 4
    $bs = 1 + $c * 0.3
    $ui.Bow.Data = Geom ("M {0},{1} l {2},{3} l 0,{4} z M {0},{1} l {5},{3} l 0,{4} z" -f `
        $cx, $bowY, (-12 * $bs), (-8 * $bs), (16 * $bs), (12 * $bs))
    SetBox $ui.BowKnot $cx $bowY (7.5 * $bs) (7.5 * $bs)

    if ($st -eq 'eat') {
        $ui.Food.Opacity = [math]::Max(0, 1 - $t / 1.6)
        SetBox $ui.Food ($cx - $hw * 0.52 - 6) ($sy + 6 - $t * 5) ([math]::Max(3, 17 - $t * 6)) ([math]::Max(3, 17 - $t * 6))
        $ui.Crumb.Opacity = [math]::Max(0, [math]::Sin($t * 6)) * 0.9
        SetAt $ui.Crumb ($cx + $hw * 0.30) ($sy - 26 - $t * 4)
    } else { $ui.Food.Opacity = 0; $ui.Crumb.Opacity = 0 }

    if ($st -eq 'sleep') {
        $p1 = ($t * 0.55) % 1.0; $p2 = (($t * 0.55) + 0.5) % 1.0
        $ui.Z1.Opacity = [math]::Max(0, 1 - $p1); SetAt $ui.Z1 ($cx + $hw * 0.46 + $p1 * 14) ($hy - 30 - $p1 * 22)
        $ui.Z2.Opacity = [math]::Max(0, 1 - $p2) * 0.8; SetAt $ui.Z2 ($cx + $hw * 0.46 + $p2 * 18) ($hy - 24 - $p2 * 26)
    } else { $ui.Z1.Opacity = 0; $ui.Z2.Opacity = 0 }

    if ($st -eq 'happy') {
        $q1 = ($t * 0.8) % 1.0; $q2 = (($t * 0.8) + 0.45) % 1.0
        $ui.H1.Opacity = [math]::Max(0, 1 - $q1); SetAt $ui.H1 ($cx - $hw * 0.55 - $q1 * 8) ($hy - 22 - $q1 * 34)
        $ui.H2.Opacity = [math]::Max(0, 1 - $q2) * 0.85; SetAt $ui.H2 ($cx + $hw * 0.48 + $q2 * 8) ($hy - 16 - $q2 * 30)
    } else { $ui.H1.Opacity = 0; $ui.H2.Opacity = 0 }
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
    $ui.Rank.Text = $rk.name
    if ($nx) { $ui.Bar.Value = [math]::Min(1, ($usd - $rk.at) / ($nx.at - $rk.at)); $ui.Next.Text = (Usd ($nx.at - $usd)) + " to " + $nx.name }
    else     { $ui.Bar.Value = 1; $ui.Next.Text = "max rank. absolute unit." }

    $ate = ($script:lastCount -ge 0 -and $rows.Count -gt $script:lastCount)
    if ($ate) {
        $l = $rows[-1]
        $gain = [double]$l.input_tokens * $inRate + [double]$l.output_tokens * $outRate
        Say ("nom nom! " + (Fmt ([double]$l.input_tokens + [double]$l.output_tokens)) + " tokens, saved " + (Usd $gain)) 6
    }
    $script:lastCount = $rows.Count
    $script:target = $usd

    try {
        $null = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 2
        if (-not $script:online) { Say "i'm awake! ollama is back" 5; Enter 'happy' 2.5 }
        $script:online = $true; $script:offlineSince = [DateTime]::MaxValue; $ui.Dot.Fill = "#FF6EE7A7"
    } catch {
        if ($script:online) { Say "zzz... ollama is off" 6; $script:offlineSince = Get-Date }
        $script:online = $false; $ui.Dot.Fill = "#FFFF7A7A"
    }

    if (-not $script:online) { Enter 'sleep' 9999 }
    elseif ($rankChanged)    { Say ("level up! i'm a " + $rk.name + " now") 7; Enter 'happy' 3.5 }
    elseif ($ate)            { Enter 'eat' 1.8 }
    elseif ($script:state -eq 'sleep') { Enter 'idle' 9999 }
}

$anim = New-Object System.Windows.Threading.DispatcherTimer
$anim.Interval = [TimeSpan]::FromMilliseconds(33)
$anim.Add_Tick({
    $now = Get-Date
    $script:phase += 0.033
    if ($now -gt $script:stateUntil) { Enter 'idle' 9999 }

    # growth eases in so a level-up visibly inflates the pig
    if ([math]::Abs($script:chonkTarget - $script:chonk) -gt 0.0005) {
        $script:chonk += ($script:chonkTarget - $script:chonk) * 0.04
    }
    if ($script:state -eq 'idle' -and $script:online -and $now -gt $script:nextBlink) {
        $script:blinkUntil = $now.AddMilliseconds(130)
        $script:nextBlink = $now.AddSeconds((Get-Random -Minimum 2 -Maximum 6))
    }
    Draw

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
