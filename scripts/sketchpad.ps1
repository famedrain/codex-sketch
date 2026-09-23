param(
    [string]$OutputPath,
    [string]$ResultPath,
    [switch]$SelfTest,
    [switch]$UiSelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-SketchResult {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [int]$Depth = 4
    )
    $json = $Value | ConvertTo-Json -Depth $Depth -Compress
    if (-not [string]::IsNullOrWhiteSpace($ResultPath)) {
        $fullResultPath = [System.IO.Path]::GetFullPath($ResultPath)
        [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($fullResultPath)) | Out-Null
        $temporaryResultPath = "$fullResultPath.tmp-$([Guid]::NewGuid().ToString('N'))"
        [System.IO.File]::WriteAllText($temporaryResultPath, $json, (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::Move($temporaryResultPath, $fullResultPath)
    }
    Write-Output $json
}

if ($env:OS -ne 'Windows_NT') {
    Write-SketchResult ([pscustomobject]@{ status = 'error'; message = 'Sketch supports Windows only.' })
    exit 1
}

if (-not $SelfTest -and -not $UiSelfTest) {
    $script:InstanceMutex = New-Object System.Threading.Mutex($false, 'Local\CodexSketchCanvas')
    try { $script:HasInstanceLock = $script:InstanceMutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $script:HasInstanceLock = $true }
    if (-not $script:HasInstanceLock) {
        Write-SketchResult ([pscustomobject]@{ status = 'error'; message = 'A sketch canvas is already open.' })
        exit 1
    }
}

if (-not $SelfTest -and -not $UiSelfTest) {
    # User sketches are conversation-only artifacts. Always keep them outside
    # the skill/workspace so they cannot be staged or committed by accident.
    $outputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'codex-sketch'
    $OutputPath = Join-Path $outputDirectory ("sketch-{0}.png" -f [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff'))
}
elseif ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputDirectory = Join-Path ([System.IO.Path]::GetTempPath()) 'codex-sketch'
    $OutputPath = Join-Path $outputDirectory ("sketch-test-{0}.png" -f [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff'))
}

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($OutputPath)) | Out-Null

try {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    Add-Type -AssemblyName System.Xaml
}
catch {
    Write-SketchResult ([pscustomobject]@{ status = 'error'; message = "WPF could not be loaded: $($_.Exception.Message)" })
    exit 1
}

try {
    if ($null -eq ('SketchShapeRecognizer' -as [type])) {
        $recognizerAssembly = Join-Path $PSScriptRoot 'SketchShapeRecognizer.dll'
        $recognizerSource = Join-Path $PSScriptRoot 'SketchShapeRecognizer.cs'
        if (Test-Path -LiteralPath $recognizerAssembly) {
            Add-Type -Path $recognizerAssembly
        }
        else {
            Add-Type -TypeDefinition (Get-Content -LiteralPath $recognizerSource -Raw) -Language CSharp
        }
    }
}
catch {
    Write-SketchResult ([pscustomobject]@{ status = 'error'; message = "Shape recognizer could not be loaded: $($_.Exception.Message)" })
    exit 1
}

function Save-BitmapSource {
    param([Parameter(Mandatory = $true)]$Bitmap, [Parameter(Mandatory = $true)][string]$Path)
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($Bitmap))
    $stream = [System.IO.File]::Create($Path)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}

function Get-Recognition {
    param([double[]]$X, [double[]]$Y)
    return [SketchShapeRecognizer]::Recognize($X, $Y)
}

function Write-SelfTestImage {
    param([string]$Path)

    [double[]]$lineX = @(120, 300, 520, 760)
    [double[]]$lineY = @(145, 150, 143, 148)

    $circleX = New-Object System.Collections.Generic.List[double]
    $circleY = New-Object System.Collections.Generic.List[double]
    for ($i = 0; $i -le 64; $i++) {
        $angle = 2.0 * [Math]::PI * $i / 64.0
        $circleX.Add(1120.0 + 190.0 * [Math]::Cos($angle))
        $circleY.Add(250.0 + 188.0 * [Math]::Sin($angle))
    }

    $rectX = New-Object System.Collections.Generic.List[double]
    $rectY = New-Object System.Collections.Generic.List[double]
    foreach ($i in 0..12) { $rectX.Add(180.0 + 46.0 * $i); $rectY.Add(520.0) }
    foreach ($i in 1..6) { $rectX.Add(732.0); $rectY.Add(520.0 + 43.0 * $i) }
    foreach ($i in 1..12) { $rectX.Add(732.0 - 46.0 * $i); $rectY.Add(778.0) }
    foreach ($i in 1..6) { $rectX.Add(180.0); $rectY.Add(778.0 - 43.0 * $i) }

    $openCircleX = New-Object System.Collections.Generic.List[double]
    $openCircleY = New-Object System.Collections.Generic.List[double]
    foreach ($i in 0..58) {
        $angle = 0.18 + ((2.0 * [Math]::PI - 0.38) * $i / 58.0)
        $jitter = 4.0 * [Math]::Sin(5.0 * $angle)
        $openCircleX.Add(1080.0 + (165.0 + $jitter) * [Math]::Cos($angle))
        $openCircleY.Add(610.0 + (160.0 + $jitter) * [Math]::Sin($angle))
    }

    $handRectX = New-Object System.Collections.Generic.List[double]
    $handRectY = New-Object System.Collections.Generic.List[double]
    foreach ($i in 0..14) { $handRectX.Add(170.0 + 38.0 * $i); $handRectY.Add(515.0 + 5.0 * [Math]::Sin($i)) }
    foreach ($i in 1..7) { $handRectX.Add(704.0 + 4.0 * [Math]::Sin($i)); $handRectY.Add(515.0 + 37.0 * $i) }
    foreach ($i in 1..14) { $handRectX.Add(704.0 - 38.0 * $i); $handRectY.Add(774.0 + 5.0 * [Math]::Sin($i)) }
    foreach ($i in 1..6) { $handRectX.Add(170.0 + 4.0 * [Math]::Sin($i)); $handRectY.Add(774.0 - 37.0 * $i) }

    [double[]]$tearX = @(800, 850, 940, 1010, 1040, 1000, 900, 800, 700, 600, 560, 590, 650, 740, 800)
    [double[]]$tearY = @(360, 430, 520, 620, 720, 790, 835, 850, 835, 790, 720, 620, 520, 430, 360)
    $scribbleX = New-Object System.Collections.Generic.List[double]
    $scribbleY = New-Object System.Collections.Generic.List[double]
    foreach ($i in 0..80) {
        $angle = 2.0 * [Math]::PI * $i / 80.0
        $scribbleX.Add(800.0 + 220.0 * [Math]::Sin($angle))
        $scribbleY.Add(450.0 + 150.0 * [Math]::Sin(2.0 * $angle))
    }
    $arcX = New-Object System.Collections.Generic.List[double]
    $arcY = New-Object System.Collections.Generic.List[double]
    foreach ($i in 0..48) {
        $angle = 1.40 * [Math]::PI * $i / 48.0
        $arcX.Add(800.0 + 180.0 * [Math]::Cos($angle))
        $arcY.Add(450.0 + 180.0 * [Math]::Sin($angle))
    }

    $line = Get-Recognition -X $lineX -Y $lineY
    $circle = Get-Recognition -X $circleX.ToArray() -Y $circleY.ToArray()
    $rectangle = Get-Recognition -X $rectX.ToArray() -Y $rectY.ToArray()
    $openCircle = Get-Recognition -X $openCircleX.ToArray() -Y $openCircleY.ToArray()
    $handRectangle = Get-Recognition -X $handRectX.ToArray() -Y $handRectY.ToArray()
    $tear = Get-Recognition -X $tearX -Y $tearY
    $scribble = Get-Recognition -X $scribbleX.ToArray() -Y $scribbleY.ToArray()
    $arc = Get-Recognition -X $arcX.ToArray() -Y $arcY.ToArray()
    if ($null -eq $line -or $line.Type -ne 'Line' -or
        $null -eq $circle -or $circle.Type -ne 'Circle' -or
        $null -eq $rectangle -or $rectangle.Type -ne 'Rectangle' -or
        $null -eq $openCircle -or $openCircle.Type -ne 'Circle' -or
        $null -eq $handRectangle -or $handRectangle.Type -ne 'Rectangle' -or
        $null -ne $tear -or $null -ne $scribble -or $null -ne $arc) {
        throw "Recognition self-test failed: line=$($line.Type), circle=$($circle.Type), rectangle=$($rectangle.Type), openCircle=$($openCircle.Type), handRectangle=$($handRectangle.Type), tear=$($tear.Type), scribble=$($scribble.Type), arc=$($arc.Type)"
    }

    $visual = New-Object System.Windows.Media.DrawingVisual
    $context = $visual.RenderOpen()
    try {
        $context.DrawRectangle([System.Windows.Media.Brushes]::White, $null, (New-Object System.Windows.Rect(0, 0, 1600, 900)))
        $pen = New-Object System.Windows.Media.Pen([System.Windows.Media.Brushes]::Black, 7)
        $pen.StartLineCap = 'Round'; $pen.EndLineCap = 'Round'; $pen.LineJoin = 'Round'
        $context.DrawLine($pen, (New-Object System.Windows.Point($line.StartX, $line.StartY)), (New-Object System.Windows.Point($line.EndX, $line.EndY)))
        $context.DrawEllipse($null, $pen, (New-Object System.Windows.Point(($circle.X + $circle.Width / 2), ($circle.Y + $circle.Height / 2))), ($circle.Width / 2), ($circle.Height / 2))
        $context.DrawRectangle($null, $pen, (New-Object System.Windows.Rect($rectangle.X, $rectangle.Y, $rectangle.Width, $rectangle.Height)))
    }
    finally { $context.Close() }

    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(1600, 900, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    Save-BitmapSource -Bitmap $bitmap -Path $Path
    return @{ line = $line.Type; circle = $circle.Type; rectangle = $rectangle.Type; openCircle = $openCircle.Type; handRectangle = $handRectangle.Type; rejected = @('tear', 'scribble', 'arc') }
}

if ($SelfTest) {
    try {
        $test = Write-SelfTestImage -Path $OutputPath
        Write-SketchResult ([pscustomobject]@{ status = 'self_test'; path = $OutputPath; width = 1600; height = 900; recognized = $test })
        exit 0
    }
    catch {
        Write-SketchResult ([pscustomobject]@{ status = 'error'; message = $_.Exception.Message })
        exit 1
    }
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Codex Sketch" WindowState="Normal" WindowStartupLocation="CenterScreen"
        WindowStyle="SingleBorderWindow" ResizeMode="CanResize" MinWidth="720" MinHeight="480"
        Background="#E5E7EB" FontFamily="Microsoft YaHei UI" UseLayoutRounding="True" SnapsToDevicePixels="True">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="58"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="58"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="#F8FAFC" BorderBrush="#CBD5E1" BorderThickness="0,0,0,1">
      <StackPanel Orientation="Horizontal" Margin="18,9">
        <Button x:Name="PenButton" Width="112" Height="38" Margin="0,0,10,0" Focusable="False"
                BorderThickness="1" Cursor="Hand" Content="1  Pen / &#x753B;&#x7B14;" ToolTip="Pen / &#x753B;&#x7B14;"/>
        <Button x:Name="EraserButton" Width="128" Height="38" Margin="0,0,10,0" Focusable="False"
                BorderThickness="1" Cursor="Hand" Content="2  Eraser / &#x6A61;&#x76AE;" ToolTip="Eraser / &#x6A61;&#x76AE;"/>
        <Button x:Name="AutoFixButton" Width="142" Height="38" Focusable="False"
                BorderThickness="1" Cursor="Hand" Content="3  Auto-fix / &#x4FEE;&#x590D;" ToolTip="Auto-fix / &#x81EA;&#x52A8;&#x4FEE;&#x590D;"/>
      </StackPanel>
    </Border>

    <Viewbox Grid.Row="1" Stretch="Uniform" Margin="18,12">
      <Border Width="1600" Height="900" Background="White" BorderBrush="#CBD5E1" BorderThickness="1">
        <InkCanvas x:Name="Ink" Width="1600" Height="900" Background="White" Cursor="Cross"/>
      </Border>
    </Viewbox>

    <Border Grid.Row="2" Background="#F8FAFC" BorderBrush="#CBD5E1" BorderThickness="0,1,0,0">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
        <Button x:Name="PreviousPageButton" Width="58" Height="36" Margin="0,0,14,0" Focusable="False"
                BorderThickness="1" FontSize="24" Cursor="Hand" Content="&#x2039;" ToolTip="Previous page / &#x4E0A;&#x4E00;&#x5F20;"/>
        <Border MinWidth="84" Height="36" Background="White" BorderBrush="#94A3B8" BorderThickness="1" CornerRadius="7">
          <TextBlock x:Name="PageText" Text="1 / 1" HorizontalAlignment="Center" VerticalAlignment="Center"
                     Foreground="#0F172A" FontSize="15" FontWeight="SemiBold"/>
        </Border>
        <Button x:Name="NextPageButton" Width="58" Height="36" Margin="14,0,0,0" Focusable="False"
                BorderThickness="1" FontSize="24" Cursor="Hand" Content="&#x203A;" ToolTip="Next page / &#x4E0B;&#x4E00;&#x5F20;"/>
      </StackPanel>
    </Border>

    <Border x:Name="ShortcutHint" Grid.Row="1" VerticalAlignment="Bottom" HorizontalAlignment="Center" Margin="20"
            Background="#D91F2937" CornerRadius="10" Padding="14,8" IsHitTestVisible="False">
      <TextBlock Foreground="White" FontSize="13" Text="Left/&#x5DE6;: black/&#x9ED1;  |  Right/&#x53F3;: red/&#x7EA2;  |  Shift: rectangle/&#x77E9;&#x5F62;  |  Alt: circle/&#x5706;  |  Wheel/&#x6EDA;&#x8F6E;: size/&#x7B14;&#x7C97;  |  4: help/&#x5E2E;&#x52A9;"/>
    </Border>

    <Border x:Name="StatusChip" Grid.Row="1" VerticalAlignment="Top" HorizontalAlignment="Center" Margin="20"
            Background="#E61F2937" CornerRadius="10" Padding="14,8" Visibility="Collapsed" IsHitTestVisible="False">
      <TextBlock x:Name="StatusText" Foreground="White" FontSize="14" FontWeight="SemiBold"/>
    </Border>

    <Grid x:Name="HelpPanel" Grid.RowSpan="3" Background="#730F172A" Visibility="Collapsed">
      <Border Width="660" HorizontalAlignment="Center" VerticalAlignment="Center"
              Background="#F21F2937" CornerRadius="18" Padding="20">
        <StackPanel>
          <TextBlock Text="Sketch shortcuts / &#x5FEB;&#x6377;&#x952E;" Foreground="White" FontSize="20" FontWeight="SemiBold" Margin="0,0,0,12"/>
          <TextBlock Foreground="#F8FAFC" FontSize="12" LineHeight="22" TextWrapping="NoWrap"
                     Text="Left drag / &#x5DE6;&#x952E;&#x62D6;&#x52A8;       Black pen / &#x9ED1;&#x7B14;&#x0a;Right drag / &#x53F3;&#x952E;&#x62D6;&#x52A8;      Red pen / &#x7EA2;&#x7B14;&#x0a;Shift + drag / &#x62D6;&#x52A8;          Rectangle / &#x77E9;&#x5F62;&#x0a;Alt + drag / &#x62D6;&#x52A8;            Circle / &#x5706;&#x0a;Mouse wheel / &#x6EDA;&#x8F6E;            Pen size / &#x7B14;&#x7C97;&#x0a;1 / 2 / 3                     Pen / eraser / auto-fix  &#x753B;&#x7B14; / &#x6A61;&#x76AE; / &#x4FEE;&#x590D;&#x0a;4                             Help / &#x5E2E;&#x52A9;&#x0a;Ctrl+N                        New page / &#x65B0;&#x5EFA;&#x4E0B;&#x4E00;&#x5F20;&#x0a;PageUp / PageDown             Previous / next page  &#x4E0A;&#x4E00;&#x5F20; / &#x4E0B;&#x4E00;&#x5F20;&#x0a;Ctrl+Delete                   Delete page / &#x5220;&#x9664;&#x5F53;&#x524D;&#x9875;&#x0a;Ctrl+Z                        Undo / &#x64A4;&#x9500;&#x0a;Ctrl+Y / Ctrl+Shift+Z         Redo / &#x91CD;&#x505A;&#x0a;Ctrl+Backspace                Clear with confirmation / &#x786E;&#x8BA4;&#x540E;&#x6E05;&#x7A7A;&#x0a;Ctrl+Enter                    Add note, then finish / &#x6DFB;&#x52A0;&#x8BF4;&#x660E;&#x540E;&#x5B8C;&#x6210;&#x0a;Ctrl+Shift+Enter              Quick finish / &#x5FEB;&#x901F;&#x5B8C;&#x6210;&#x0a;Esc                           Back or cancel / &#x8FD4;&#x56DE;&#x6216;&#x53D6;&#x6D88;"/>
        </StackPanel>
      </Border>
    </Grid>

    <Grid x:Name="NoteOverlay" Grid.RowSpan="3" Background="#730F172A" Visibility="Collapsed">
      <Border Width="660" HorizontalAlignment="Center" VerticalAlignment="Center"
              Background="#FFFDFD" BorderBrush="#CBD5E1" BorderThickness="1" CornerRadius="18" Padding="28">
        <StackPanel>
          <TextBlock Text="Add a note / &#x6DFB;&#x52A0;&#x8BF4;&#x660E;" Foreground="#0F172A" FontSize="23" FontWeight="SemiBold"/>
          <TextBlock Text="Optional context for all sketches / &#x53EF;&#x9009;&#xFF0C;&#x5C06;&#x4E0E;&#x5168;&#x90E8;&#x8349;&#x56FE;&#x4E00;&#x8D77;&#x4EA4;&#x7ED9; Codex" Foreground="#64748B" FontSize="13" Margin="0,6,0,14"/>
          <TextBox x:Name="NoteBox" Height="150" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                   FontSize="16" Padding="12" BorderBrush="#94A3B8" BorderThickness="1" Background="White" Foreground="#0F172A"/>
          <TextBlock Text="Ctrl+Enter: submit / &#x63D0;&#x4EA4;    Esc: back / &#x8FD4;&#x56DE;" Foreground="#64748B" FontSize="13" HorizontalAlignment="Right" Margin="0,12,0,0"/>
        </StackPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
'@

try {
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $window = [Windows.Markup.XamlReader]::Load($reader)
}
catch {
    Write-SketchResult ([pscustomobject]@{ status = 'error'; message = "Canvas UI could not be created: $($_.Exception.Message)" })
    exit 1
}

$workArea = [System.Windows.SystemParameters]::WorkArea
$window.Width = [Math]::Floor($workArea.Width * 0.75)
$window.Height = [Math]::Floor($workArea.Height * 0.75)

$ink = $window.FindName('Ink')
$shortcutHint = $window.FindName('ShortcutHint')
$statusChip = $window.FindName('StatusChip')
$statusText = $window.FindName('StatusText')
$helpPanel = $window.FindName('HelpPanel')
$noteOverlay = $window.FindName('NoteOverlay')
$noteBox = $window.FindName('NoteBox')
$penButton = $window.FindName('PenButton')
$eraserButton = $window.FindName('EraserButton')
$autoFixButton = $window.FindName('AutoFixButton')
$previousPageButton = $window.FindName('PreviousPageButton')
$nextPageButton = $window.FindName('NextPageButton')
$pageText = $window.FindName('PageText')

$script:Completed = $false
$script:ExportWidth = 0
$script:ExportHeight = 0
$script:Note = ''
$script:SavedPaths = New-Object System.Collections.Generic.List[string]
$script:MaxPages = 6
$script:Pages = New-Object System.Collections.ArrayList
$script:CurrentPageIndex = 0
$script:AutoFix = $true
$script:IsSnapping = $false
$script:AllowClose = $false
$script:CurrentMode = 'Pen'
$script:RedColor = [System.Windows.Media.Color]::FromRgb(220, 38, 38)
$script:RightStroke = $null
$script:ManualShapeKind = $null
$script:ManualShapeStart = $null
$script:ManualShapeStroke = $null
$script:ManualShapeColor = [System.Windows.Media.Colors]::Black
$script:ManualShapeButton = $null
$script:PenSizes = @(2.5, 4.0, 6.0, 9.0, 13.0, 18.0)
$script:PenSizeIndex = 2
$script:StatusTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:StatusTimer.Interval = [TimeSpan]::FromMilliseconds(1100)
$script:HintTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:HintTimer.Interval = [TimeSpan]::FromSeconds(4)

function Convert-UiText {
    param([string]$Text)
    return [regex]::Unescape($Text)
}

$script:Ui = @{
    Pen = Convert-UiText 'Pen / \u753b\u7b14'
    Eraser = Convert-UiText 'Eraser / \u6a61\u76ae'
    NothingToUndo = Convert-UiText 'Nothing to undo / \u6ca1\u6709\u53ef\u64a4\u9500\u7684\u5185\u5bb9'
    Undone = Convert-UiText 'Undone / \u5df2\u64a4\u9500'
    NothingToRedo = Convert-UiText 'Nothing to redo / \u6ca1\u6709\u53ef\u91cd\u505a\u7684\u5185\u5bb9'
    Redone = Convert-UiText 'Redone / \u5df2\u91cd\u505a'
    AutoOn = Convert-UiText 'Auto-fix: on / \u81ea\u52a8\u4fee\u590d\uff1a\u5f00'
    AutoOff = Convert-UiText 'Auto-fix: off / \u81ea\u52a8\u4fee\u590d\uff1a\u5173'
    NothingToClear = Convert-UiText 'Nothing to clear / \u753b\u677f\u5df2\u7ecf\u662f\u7a7a\u7684'
    Cleared = Convert-UiText 'Cleared / \u5df2\u6e05\u7a7a'
    ClearTitle = Convert-UiText 'Clear canvas / \u6e05\u7a7a\u753b\u677f'
    ClearMessage = Convert-UiText 'Clear everything on the canvas? / \u786e\u5b9a\u6e05\u7a7a\u753b\u677f\u4e0a\u7684\u6240\u6709\u5185\u5bb9\u5417\uff1f'
    FixedLine = Convert-UiText 'Fixed: line / \u5df2\u4fee\u6b63\uff1a\u76f4\u7ebf'
    FixedCircle = Convert-UiText 'Fixed: circle / \u5df2\u4fee\u6b63\uff1a\u5706'
    FixedEllipse = Convert-UiText 'Fixed: ellipse / \u5df2\u4fee\u6b63\uff1a\u692d\u5706'
    FixedRectangle = Convert-UiText 'Fixed: rectangle / \u5df2\u4fee\u6b63\uff1a\u77e9\u5f62'
    EmptyPage = Convert-UiText 'Draw something first / \u8bf7\u5148\u753b\u4e00\u4e9b\u5185\u5bb9'
    MaxPages = Convert-UiText 'Maximum 6 sketches / \u6700\u591a\u652f\u6301 6 \u5f20\u8349\u56fe'
    PageAdded = Convert-UiText 'New page added / \u5df2\u65b0\u5efa\u4e00\u9875'
    PageDeleted = Convert-UiText 'Page deleted / \u5df2\u5220\u9664\u5f53\u524d\u9875'
    DeleteTitle = Convert-UiText 'Delete page / \u5220\u9664\u5f53\u524d\u9875'
    DeleteMessage = Convert-UiText 'Delete the current page? / \u786e\u5b9a\u5220\u9664\u5f53\u524d\u9875\u5417\uff1f'
    CloseTitle = Convert-UiText 'Discard sketches? / \u653e\u5f03\u8349\u56fe\uff1f'
    CloseMessage = Convert-UiText 'Close and discard all unsent sketches? / \u5173\u95ed\u5e76\u653e\u5f03\u6240\u6709\u672a\u63d0\u4ea4\u7684\u8349\u56fe\u5417\uff1f'
}

function New-PageState {
    return [pscustomobject]@{
        Snapshot = ''
        UndoStack = New-Object System.Collections.Generic.List[string]
        RedoStack = New-Object System.Collections.Generic.List[string]
    }
}

[void]$script:Pages.Add((New-PageState))

function Get-CurrentPage {
    return $script:Pages[$script:CurrentPageIndex]
}

function Update-ToolbarState {
    $selectedBackground = [System.Windows.Media.Brushes]::White
    $selectedBorder = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(37, 99, 235))
    $normalBackground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(241, 245, 249))
    $normalBorder = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(148, 163, 184))

    foreach ($button in @($penButton, $eraserButton)) {
        $button.Background = $normalBackground
        $button.BorderBrush = $normalBorder
        $button.Foreground = [System.Windows.Media.Brushes]::Black
    }
    $modeButton = if ($script:CurrentMode -eq 'Pen') { $penButton } else { $eraserButton }
    $modeButton.Background = $selectedBackground
    $modeButton.BorderBrush = $selectedBorder
    $modeButton.Foreground = $selectedBorder
    $modeButton.BorderThickness = New-Object System.Windows.Thickness(2)
    $(if ($modeButton -eq $penButton) { $eraserButton } else { $penButton }).BorderThickness = New-Object System.Windows.Thickness(1)

    if ($script:AutoFix) {
        $autoFixButton.Background = $selectedBackground
        $autoFixButton.BorderBrush = $selectedBorder
        $autoFixButton.Foreground = $selectedBorder
        $autoFixButton.BorderThickness = New-Object System.Windows.Thickness(2)
    }
    else {
        $autoFixButton.Background = $normalBackground
        $autoFixButton.BorderBrush = $normalBorder
        $autoFixButton.Foreground = [System.Windows.Media.Brushes]::Black
        $autoFixButton.BorderThickness = New-Object System.Windows.Thickness(1)
    }
}

function Update-PageNavigation {
    $pageText.Text = '{0} / {1}' -f ($script:CurrentPageIndex + 1), $script:Pages.Count
    $previousPageButton.IsEnabled = $script:CurrentPageIndex -gt 0
    $nextPageButton.IsEnabled = $script:CurrentPageIndex -lt ($script:Pages.Count - 1)
}

function Set-DrawingMode {
    param([ValidateSet('Pen', 'Eraser')][string]$Mode)
    $script:CurrentMode = $Mode
    $size = [double]$script:PenSizes[$script:PenSizeIndex]
    if ($Mode -eq 'Pen') {
        $ink.EditingMode = [System.Windows.Controls.InkCanvasEditingMode]::Ink
        $ink.Cursor = [System.Windows.Input.Cursors]::Cross
    }
    else {
        $ink.EditingMode = [System.Windows.Controls.InkCanvasEditingMode]::EraseByPoint
        $ink.EraserShape = New-Object System.Windows.Ink.EllipseStylusShape(($size * 3.2), ($size * 3.2))
        $ink.Cursor = [System.Windows.Input.Cursors]::Hand
    }
    Update-ToolbarState
}

function New-DrawingAttributes {
    param(
        [System.Windows.Media.Color]$Color,
        [bool]$FitToCurve = $true
    )
    $size = [double]$script:PenSizes[$script:PenSizeIndex]
    $attributes = New-Object System.Windows.Ink.DrawingAttributes
    $attributes.Color = $Color
    $attributes.Width = $size
    $attributes.Height = $size
    $attributes.FitToCurve = $FitToCurve
    $attributes.IgnorePressure = $true
    $attributes.StylusTip = [System.Windows.Ink.StylusTip]::Ellipse
    return $attributes
}

function Update-DrawingAttributes {
    $size = [double]$script:PenSizes[$script:PenSizeIndex]
    $ink.DefaultDrawingAttributes = New-DrawingAttributes -Color ([System.Windows.Media.Colors]::Black) -FitToCurve $true
    if ($ink.EditingMode -eq [System.Windows.Controls.InkCanvasEditingMode]::EraseByPoint) {
        $ink.EraserShape = New-Object System.Windows.Ink.EllipseStylusShape(($size * 3.2), ($size * 3.2))
    }
}

function Show-Status {
    param([string]$Text)
    $statusText.Text = $Text
    $statusChip.Visibility = [System.Windows.Visibility]::Visible
    $script:StatusTimer.Stop()
    $script:StatusTimer.Start()
}

$script:StatusTimer.Add_Tick({
    $script:StatusTimer.Stop()
    $statusChip.Visibility = [System.Windows.Visibility]::Collapsed
})

$script:HintTimer.Add_Tick({
    $script:HintTimer.Stop()
    $shortcutHint.Visibility = [System.Windows.Visibility]::Collapsed
})

function Get-StrokesSnapshot {
    if ($ink.Strokes.Count -eq 0) { return '' }
    $stream = New-Object System.IO.MemoryStream
    try {
        $ink.Strokes.Save($stream)
        return [Convert]::ToBase64String($stream.ToArray())
    }
    finally { $stream.Dispose() }
}

function Restore-StrokesSnapshot {
    param([AllowEmptyString()][string]$Snapshot)
    $script:IsSnapping = $true
    try {
        $ink.Strokes.Clear()
        if (-not [string]::IsNullOrEmpty($Snapshot)) {
            $bytes = [Convert]::FromBase64String($Snapshot)
            $stream = New-Object System.IO.MemoryStream(,$bytes)
            try { $ink.Strokes = New-Object System.Windows.Ink.StrokeCollection($stream) }
            finally { $stream.Dispose() }
        }
    }
    finally { $script:IsSnapping = $false }
}

function Add-UndoSnapshot {
    param([AllowEmptyString()][string]$Snapshot)
    $page = Get-CurrentPage
    $page.UndoStack.Add($Snapshot)
    if ($page.UndoStack.Count -gt 60) { $page.UndoStack.RemoveAt(0) }
    $page.RedoStack.Clear()
}

function Invoke-Undo {
    $page = Get-CurrentPage
    if ($page.UndoStack.Count -eq 0) {
        Show-Status $script:Ui.NothingToUndo
        return
    }
    $page.RedoStack.Add((Get-StrokesSnapshot))
    $index = $page.UndoStack.Count - 1
    $snapshot = $page.UndoStack[$index]
    $page.UndoStack.RemoveAt($index)
    Restore-StrokesSnapshot -Snapshot $snapshot
    $page.Snapshot = $snapshot
    Show-Status $script:Ui.Undone
}

function Invoke-Redo {
    $page = Get-CurrentPage
    if ($page.RedoStack.Count -eq 0) {
        Show-Status $script:Ui.NothingToRedo
        return
    }
    $page.UndoStack.Add((Get-StrokesSnapshot))
    $index = $page.RedoStack.Count - 1
    $snapshot = $page.RedoStack[$index]
    $page.RedoStack.RemoveAt($index)
    Restore-StrokesSnapshot -Snapshot $snapshot
    $page.Snapshot = $snapshot
    Show-Status $script:Ui.Redone
}

function New-StylusStroke {
    param([System.Collections.Generic.List[System.Windows.Point]]$Points, [System.Windows.Ink.DrawingAttributes]$Attributes)
    $stylusPoints = New-Object System.Windows.Input.StylusPointCollection
    foreach ($point in $Points) {
        $stylusPoints.Add((New-Object System.Windows.Input.StylusPoint($point.X, $point.Y)))
    }
    $stroke = New-Object System.Windows.Ink.Stroke($stylusPoints, $Attributes.Clone())
    return $stroke
}

function New-RectanglePoints {
    param([double]$X, [double]$Y, [double]$Width, [double]$Height)
    $points = New-Object System.Collections.Generic.List[System.Windows.Point]
    $points.Add((New-Object System.Windows.Point($X, $Y)))
    $points.Add((New-Object System.Windows.Point(($X + $Width), $Y)))
    $points.Add((New-Object System.Windows.Point(($X + $Width), ($Y + $Height))))
    $points.Add((New-Object System.Windows.Point($X, ($Y + $Height))))
    $points.Add((New-Object System.Windows.Point($X, $Y)))
    return ,$points
}

function New-EllipsePoints {
    param([double]$X, [double]$Y, [double]$Width, [double]$Height)
    $points = New-Object System.Collections.Generic.List[System.Windows.Point]
    $centerX = $X + $Width / 2.0
    $centerY = $Y + $Height / 2.0
    foreach ($i in 0..96) {
        $angle = 2.0 * [Math]::PI * $i / 96.0
        $points.Add((New-Object System.Windows.Point(($centerX + $Width / 2.0 * [Math]::Cos($angle)), ($centerY + $Height / 2.0 * [Math]::Sin($angle)))))
    }
    return ,$points
}

function New-ManualShapeStroke {
    param(
        [ValidateSet('Rectangle', 'Circle')][string]$Kind,
        [System.Windows.Point]$Start,
        [System.Windows.Point]$End,
        [System.Windows.Media.Color]$Color
    )

    $dx = $End.X - $Start.X
    $dy = $End.Y - $Start.Y
    if ($Kind -eq 'Rectangle') {
        if ([Math]::Abs($dx) -lt 4 -or [Math]::Abs($dy) -lt 4) { return $null }
        $x = [Math]::Min($Start.X, $End.X)
        $y = [Math]::Min($Start.Y, $End.Y)
        $width = [Math]::Abs($dx)
        $height = [Math]::Abs($dy)
        $points = New-RectanglePoints -X $x -Y $y -Width $width -Height $height
    }
    else {
        $side = [Math]::Min([Math]::Abs($dx), [Math]::Abs($dy))
        if ($side -lt 4) { return $null }
        $x = if ($dx -ge 0) { $Start.X } else { $Start.X - $side }
        $y = if ($dy -ge 0) { $Start.Y } else { $Start.Y - $side }
        $points = New-EllipsePoints -X $x -Y $y -Width $side -Height $side
    }

    $attributes = New-DrawingAttributes -Color $Color -FitToCurve $false
    return New-StylusStroke -Points $points -Attributes $attributes
}

function Start-ManualShape {
    param(
        [ValidateSet('Rectangle', 'Circle')][string]$Kind,
        [System.Windows.Point]$Point,
        [System.Windows.Media.Color]$Color,
        [ValidateSet('Left', 'Right')][string]$Button
    )
    Add-UndoSnapshot -Snapshot (Get-StrokesSnapshot)
    $script:ManualShapeKind = $Kind
    $script:ManualShapeStart = $Point
    $script:ManualShapeColor = $Color
    $script:ManualShapeButton = $Button
    $script:ManualShapeStroke = $null
    $ink.CaptureMouse() | Out-Null
}

function Update-ManualShape {
    param([System.Windows.Point]$Point)
    if ($null -eq $script:ManualShapeKind -or $null -eq $script:ManualShapeStart) { return }
    $newStroke = New-ManualShapeStroke -Kind $script:ManualShapeKind -Start $script:ManualShapeStart -End $Point -Color $script:ManualShapeColor
    $script:IsSnapping = $true
    try {
        if ($null -ne $script:ManualShapeStroke -and $ink.Strokes.Contains($script:ManualShapeStroke)) {
            $ink.Strokes.Remove($script:ManualShapeStroke)
        }
        $script:ManualShapeStroke = $newStroke
        if ($null -ne $newStroke) { $ink.Strokes.Add($newStroke) }
    }
    finally { $script:IsSnapping = $false }
}

function Finish-ManualShape {
    param([System.Windows.Point]$Point)
    Update-ManualShape -Point $Point
    $script:ManualShapeKind = $null
    $script:ManualShapeStart = $null
    $script:ManualShapeStroke = $null
    $script:ManualShapeButton = $null
    $ink.ReleaseMouseCapture()
}

function Start-RightStroke {
    param([System.Windows.Point]$Point)
    Add-UndoSnapshot -Snapshot (Get-StrokesSnapshot)
    $points = New-Object System.Collections.Generic.List[System.Windows.Point]
    $points.Add($Point)
    $attributes = New-DrawingAttributes -Color $script:RedColor -FitToCurve $true
    $script:RightStroke = New-StylusStroke -Points $points -Attributes $attributes
    $script:IsSnapping = $true
    try { $ink.Strokes.Add($script:RightStroke) }
    finally { $script:IsSnapping = $false }
    $ink.CaptureMouse() | Out-Null
}

function Update-RightStroke {
    param([System.Windows.Point]$Point)
    if ($null -eq $script:RightStroke) { return }
    $last = $script:RightStroke.StylusPoints[$script:RightStroke.StylusPoints.Count - 1]
    $dx = $Point.X - $last.X
    $dy = $Point.Y - $last.Y
    if (($dx * $dx) + ($dy * $dy) -ge 2.25) {
        $script:RightStroke.StylusPoints.Add((New-Object System.Windows.Input.StylusPoint($Point.X, $Point.Y)))
        $ink.InvalidateVisual()
    }
}

function Finish-RightStroke {
    param([System.Windows.Point]$Point)
    if ($null -eq $script:RightStroke) { return }
    Update-RightStroke -Point $Point
    $finishedStroke = $script:RightStroke
    $script:RightStroke = $null
    $ink.ReleaseMouseCapture()
    if ($script:AutoFix -and $finishedStroke.StylusPoints.Count -ge 3) {
        Invoke-AutoFix -Stroke $finishedStroke
    }
}

function Convert-ToCorrectedStroke {
    param([System.Windows.Ink.Stroke]$Stroke, $Match)

    $points = New-Object System.Collections.Generic.List[System.Windows.Point]
    if ($Match.Type -eq 'Line') {
        foreach ($i in 0..24) {
            $t = $i / 24.0
            $points.Add((New-Object System.Windows.Point(($Match.StartX + ($Match.EndX - $Match.StartX) * $t), ($Match.StartY + ($Match.EndY - $Match.StartY) * $t))))
        }
    }
    elseif ($Match.Type -eq 'Rectangle') {
        $points = New-RectanglePoints -X $Match.X -Y $Match.Y -Width $Match.Width -Height $Match.Height
    }
    else {
        $points = New-EllipsePoints -X $Match.X -Y $Match.Y -Width $Match.Width -Height $Match.Height
    }
    $attributes = $Stroke.DrawingAttributes.Clone()
    $attributes.FitToCurve = $false
    return New-StylusStroke -Points $points -Attributes $attributes
}

function Invoke-AutoFix {
    param([System.Windows.Ink.Stroke]$Stroke)

    $count = $Stroke.StylusPoints.Count
    if ($count -lt 3) { return }
    $xs = New-Object double[] $count
    $ys = New-Object double[] $count
    for ($i = 0; $i -lt $count; $i++) {
        $xs[$i] = $Stroke.StylusPoints[$i].X
        $ys[$i] = $Stroke.StylusPoints[$i].Y
    }
    $match = Get-Recognition -X $xs -Y $ys
    if ($null -eq $match) { return }

    $rawSnapshot = Get-StrokesSnapshot
    $corrected = Convert-ToCorrectedStroke -Stroke $Stroke -Match $match

    $script:IsSnapping = $true
    try {
        $ink.Strokes.Remove($Stroke)
        $ink.Strokes.Add($corrected)
    }
    finally { $script:IsSnapping = $false }

    Add-UndoSnapshot -Snapshot $rawSnapshot
    $message = switch ($match.Type) {
        'Line' { $script:Ui.FixedLine }
        'Circle' { $script:Ui.FixedCircle }
        'Ellipse' { $script:Ui.FixedEllipse }
        'Rectangle' { $script:Ui.FixedRectangle }
        default { $script:Ui.FixedLine }
    }
    Show-Status $message
}

function Get-PageOutputPath {
    param([int]$PageNumber)
    if ($PageNumber -eq 1) { return $OutputPath }

    $directory = [System.IO.Path]::GetDirectoryName($OutputPath)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($OutputPath)
    $extension = [System.IO.Path]::GetExtension($OutputPath)
    return Join-Path $directory ("{0}-{1:D2}{2}" -f $name, $PageNumber, $extension)
}

function Export-Snapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Snapshot
    )
    Restore-StrokesSnapshot -Snapshot $Snapshot
    $ink.UpdateLayout()
    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(1600, 900, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($ink)
    Save-BitmapSource -Bitmap $bitmap -Path $Path
    $script:ExportWidth = 1600
    $script:ExportHeight = 900
}

function Save-CurrentPageState {
    (Get-CurrentPage).Snapshot = Get-StrokesSnapshot
}

function Switch-ToPage {
    param([int]$Index)
    if ($Index -lt 0 -or $Index -ge $script:Pages.Count -or $Index -eq $script:CurrentPageIndex) { return }
    Save-CurrentPageState
    $script:CurrentPageIndex = $Index
    Restore-StrokesSnapshot -Snapshot (Get-CurrentPage).Snapshot
    Update-PageNavigation
    $ink.Focus() | Out-Null
}

function Add-NewPage {
    Save-CurrentPageState
    if ([string]::IsNullOrEmpty((Get-CurrentPage).Snapshot)) {
        Show-Status $script:Ui.EmptyPage
        return
    }
    if ($script:Pages.Count -ge $script:MaxPages) {
        Show-Status $script:Ui.MaxPages
        return
    }
    [void]$script:Pages.Add((New-PageState))
    $script:CurrentPageIndex = $script:Pages.Count - 1
    Restore-StrokesSnapshot -Snapshot ''
    $helpPanel.Visibility = [System.Windows.Visibility]::Collapsed
    Update-PageNavigation
    Show-Status $script:Ui.PageAdded
    $ink.Focus() | Out-Null
}

function Remove-CurrentPage {
    param([switch]$SkipConfirmation)
    Save-CurrentPageState
    if (-not $SkipConfirmation) {
        $choice = [System.Windows.MessageBox]::Show(
            $window,
            $script:Ui.DeleteMessage,
            $script:Ui.DeleteTitle,
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning,
            [System.Windows.MessageBoxResult]::No
        )
        if ($choice -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }

    if ($script:Pages.Count -eq 1) {
        (Get-CurrentPage).Snapshot = ''
        (Get-CurrentPage).UndoStack.Clear()
        (Get-CurrentPage).RedoStack.Clear()
        Restore-StrokesSnapshot -Snapshot ''
    }
    else {
        $script:Pages.RemoveAt($script:CurrentPageIndex)
        if ($script:CurrentPageIndex -ge $script:Pages.Count) { $script:CurrentPageIndex = $script:Pages.Count - 1 }
        Restore-StrokesSnapshot -Snapshot (Get-CurrentPage).Snapshot
    }
    Update-PageNavigation
    Show-Status $script:Ui.PageDeleted
    $ink.Focus() | Out-Null
}

function Test-HasContent {
    Save-CurrentPageState
    foreach ($page in $script:Pages) {
        if (-not [string]::IsNullOrEmpty($page.Snapshot)) { return $true }
    }
    return $false
}

function Export-AllPages {
    Save-CurrentPageState
    $activeSnapshot = (Get-CurrentPage).Snapshot
    Remove-SavedSketchFiles
    $exportNumber = 0
    try {
        foreach ($page in $script:Pages) {
            if ([string]::IsNullOrEmpty($page.Snapshot)) { continue }
            $exportNumber++
            $pagePath = Get-PageOutputPath -PageNumber $exportNumber
            Export-Snapshot -Path $pagePath -Snapshot $page.Snapshot
            $script:SavedPaths.Add($pagePath)
        }
    }
    catch {
        Remove-SavedSketchFiles
        throw
    }
    finally {
        Restore-StrokesSnapshot -Snapshot $activeSnapshot
    }
}

function Remove-SavedSketchFiles {
    foreach ($path in $script:SavedPaths) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
    $script:SavedPaths.Clear()
}

function Show-NoteOverlay {
    $helpPanel.Visibility = [System.Windows.Visibility]::Collapsed
    $noteOverlay.Visibility = [System.Windows.Visibility]::Visible
    $noteBox.Focus() | Out-Null
    $noteBox.CaretIndex = $noteBox.Text.Length
}

function Hide-NoteOverlay {
    $noteOverlay.Visibility = [System.Windows.Visibility]::Collapsed
    $ink.Focus() | Out-Null
}

function Complete-Sketch {
    try {
        $script:Note = $noteBox.Text.Trim()
        Export-AllPages
        if ($script:SavedPaths.Count -eq 0) {
            Hide-NoteOverlay
            Show-Status $script:Ui.EmptyPage
            return
        }
        $script:Completed = $true
        $script:AllowClose = $true
        $window.DialogResult = $true
        $window.Close()
    }
    catch {
        [System.Windows.MessageBox]::Show($window, $_.Exception.Message, 'Sketch export error', 'OK', 'Error') | Out-Null
    }
}

function Confirm-ClearCanvas {
    if ($ink.Strokes.Count -eq 0) {
        Show-Status $script:Ui.NothingToClear
        return
    }
    $choice = [System.Windows.MessageBox]::Show(
        $window,
        $script:Ui.ClearMessage,
        $script:Ui.ClearTitle,
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning,
        [System.Windows.MessageBoxResult]::No
    )
    if ($choice -eq [System.Windows.MessageBoxResult]::Yes) {
        Add-UndoSnapshot -Snapshot (Get-StrokesSnapshot)
        $ink.Strokes.Clear()
        (Get-CurrentPage).Snapshot = ''
        Show-Status $script:Ui.Cleared
    }
}

function Get-ModifierShapeKind {
    $modifiers = [System.Windows.Input.Keyboard]::Modifiers
    if (($modifiers -band [System.Windows.Input.ModifierKeys]::Shift) -ne 0) { return 'Rectangle' }
    if (($modifiers -band [System.Windows.Input.ModifierKeys]::Alt) -ne 0) { return 'Circle' }
    return $null
}

$ink.Add_PreviewMouseLeftButtonDown({
    param($sender, $eventArgs)
    if ($noteOverlay.Visibility -eq [System.Windows.Visibility]::Visible -or $helpPanel.Visibility -eq [System.Windows.Visibility]::Visible) {
        $eventArgs.Handled = $true
        return
    }
    $shapeKind = Get-ModifierShapeKind
    if ($null -ne $shapeKind) {
        Start-ManualShape -Kind $shapeKind -Point ($eventArgs.GetPosition($ink)) -Color ([System.Windows.Media.Colors]::Black) -Button Left
        $eventArgs.Handled = $true
        return
    }
    if (-not $script:IsSnapping) { Add-UndoSnapshot -Snapshot (Get-StrokesSnapshot) }
})

$ink.Add_PreviewMouseRightButtonDown({
    param($sender, $eventArgs)
    if ($noteOverlay.Visibility -eq [System.Windows.Visibility]::Visible -or $helpPanel.Visibility -eq [System.Windows.Visibility]::Visible) {
        $eventArgs.Handled = $true
        return
    }
    $point = $eventArgs.GetPosition($ink)
    $shapeKind = Get-ModifierShapeKind
    if ($null -ne $shapeKind) {
        Start-ManualShape -Kind $shapeKind -Point $point -Color $script:RedColor -Button Right
    }
    else {
        Start-RightStroke -Point $point
    }
    $eventArgs.Handled = $true
})

$ink.Add_PreviewMouseMove({
    param($sender, $eventArgs)
    if ($null -ne $script:ManualShapeKind) {
        $isPressed = if ($script:ManualShapeButton -eq 'Left') {
            $eventArgs.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed
        }
        else {
            $eventArgs.RightButton -eq [System.Windows.Input.MouseButtonState]::Pressed
        }
        if ($isPressed) { Update-ManualShape -Point ($eventArgs.GetPosition($ink)) }
        $eventArgs.Handled = $true
    }
    elseif ($null -ne $script:RightStroke -and $eventArgs.RightButton -eq [System.Windows.Input.MouseButtonState]::Pressed) {
        Update-RightStroke -Point ($eventArgs.GetPosition($ink))
        $eventArgs.Handled = $true
    }
})

$ink.Add_PreviewMouseLeftButtonUp({
    param($sender, $eventArgs)
    if ($null -ne $script:ManualShapeKind -and $script:ManualShapeButton -eq 'Left') {
        Finish-ManualShape -Point ($eventArgs.GetPosition($ink))
        $eventArgs.Handled = $true
    }
})

$ink.Add_PreviewMouseRightButtonUp({
    param($sender, $eventArgs)
    if ($null -ne $script:ManualShapeKind -and $script:ManualShapeButton -eq 'Right') {
        Finish-ManualShape -Point ($eventArgs.GetPosition($ink))
    }
    elseif ($null -ne $script:RightStroke) {
        Finish-RightStroke -Point ($eventArgs.GetPosition($ink))
    }
    $eventArgs.Handled = $true
})

$ink.Add_StrokeCollected({
    param($sender, $eventArgs)
    if ($script:AutoFix -and -not $script:IsSnapping) { Invoke-AutoFix -Stroke $eventArgs.Stroke }
})

$window.Add_PreviewMouseWheel({
    param($sender, $eventArgs)
    if ($noteOverlay.Visibility -eq [System.Windows.Visibility]::Visible -or $helpPanel.Visibility -eq [System.Windows.Visibility]::Visible) {
        $eventArgs.Handled = $true
        return
    }
    if ($eventArgs.Delta -gt 0) { $script:PenSizeIndex = [Math]::Min($script:PenSizes.Count - 1, $script:PenSizeIndex + 1) }
    else { $script:PenSizeIndex = [Math]::Max(0, $script:PenSizeIndex - 1) }
    Update-DrawingAttributes
    $size = $script:PenSizes[$script:PenSizeIndex]
    Show-Status (Convert-UiText "Pen size: $size / \u7b14\u7c97\uff1a$size")
    $eventArgs.Handled = $true
})

$window.Add_PreviewKeyDown({
    param($sender, $eventArgs)
    $modifiers = [System.Windows.Input.Keyboard]::Modifiers
    $ctrl = ($modifiers -band [System.Windows.Input.ModifierKeys]::Control) -ne 0
    $shift = ($modifiers -band [System.Windows.Input.ModifierKeys]::Shift) -ne 0

    if ($noteOverlay.Visibility -eq [System.Windows.Visibility]::Visible) {
        if ($ctrl -and $eventArgs.Key -eq [System.Windows.Input.Key]::Enter) {
            Complete-Sketch
            $eventArgs.Handled = $true
        }
        elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
            Hide-NoteOverlay
            $eventArgs.Handled = $true
        }
        return
    }

    if ($helpPanel.Visibility -eq [System.Windows.Visibility]::Visible) {
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::D4 -or $eventArgs.Key -eq [System.Windows.Input.Key]::NumPad4 -or $eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
            $helpPanel.Visibility = [System.Windows.Visibility]::Collapsed
            $ink.Focus() | Out-Null
        }
        $eventArgs.Handled = $true
        return
    }

    if ($ctrl -and $shift -and $eventArgs.Key -eq [System.Windows.Input.Key]::Enter) {
        Complete-Sketch
        $eventArgs.Handled = $true
        return
    }
    elseif ($ctrl -and $eventArgs.Key -eq [System.Windows.Input.Key]::Enter) {
        Show-NoteOverlay
        $eventArgs.Handled = $true
        return
    }
    elseif ($ctrl -and $eventArgs.Key -eq [System.Windows.Input.Key]::N) {
        Add-NewPage
        $eventArgs.Handled = $true
        return
    }
    elseif ($ctrl -and $eventArgs.Key -eq [System.Windows.Input.Key]::Delete) {
        Remove-CurrentPage
        $eventArgs.Handled = $true
        return
    }
    elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::PageUp) {
        Switch-ToPage -Index ($script:CurrentPageIndex - 1)
        $eventArgs.Handled = $true
        return
    }
    elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::PageDown) {
        Switch-ToPage -Index ($script:CurrentPageIndex + 1)
        $eventArgs.Handled = $true
        return
    }
    if ($eventArgs.Key -eq [System.Windows.Input.Key]::D4 -or $eventArgs.Key -eq [System.Windows.Input.Key]::NumPad4) {
        $helpPanel.Visibility = if ($helpPanel.Visibility -eq [System.Windows.Visibility]::Visible) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
        $eventArgs.Handled = $true
    }
    elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::D1 -or $eventArgs.Key -eq [System.Windows.Input.Key]::NumPad1) {
        Set-DrawingMode -Mode Pen; Show-Status $script:Ui.Pen; $eventArgs.Handled = $true
    }
    elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::D2 -or $eventArgs.Key -eq [System.Windows.Input.Key]::NumPad2) {
        Set-DrawingMode -Mode Eraser; Show-Status $script:Ui.Eraser; $eventArgs.Handled = $true
    }
    elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::D3 -or $eventArgs.Key -eq [System.Windows.Input.Key]::NumPad3) {
        $script:AutoFix = -not $script:AutoFix
        Update-ToolbarState
        Show-Status $(if ($script:AutoFix) { $script:Ui.AutoOn } else { $script:Ui.AutoOff })
        $eventArgs.Handled = $true
    }
    elseif ($ctrl -and (($shift -and $eventArgs.Key -eq [System.Windows.Input.Key]::Z) -or $eventArgs.Key -eq [System.Windows.Input.Key]::Y)) {
        Invoke-Redo; $eventArgs.Handled = $true
    }
    elseif ($ctrl -and $eventArgs.Key -eq [System.Windows.Input.Key]::Z) {
        Invoke-Undo; $eventArgs.Handled = $true
    }
    elseif ($ctrl -and $eventArgs.Key -eq [System.Windows.Input.Key]::Back) {
        Confirm-ClearCanvas
        $eventArgs.Handled = $true
    }
    elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::Escape) {
        if ($helpPanel.Visibility -eq [System.Windows.Visibility]::Visible) {
            $helpPanel.Visibility = [System.Windows.Visibility]::Collapsed
            $ink.Focus() | Out-Null
        }
        else {
            $window.Close()
        }
        $eventArgs.Handled = $true
    }
})

$penButton.Add_Click({ Set-DrawingMode -Mode Pen; Show-Status $script:Ui.Pen })
$eraserButton.Add_Click({ Set-DrawingMode -Mode Eraser; Show-Status $script:Ui.Eraser })
$autoFixButton.Add_Click({
    $script:AutoFix = -not $script:AutoFix
    Update-ToolbarState
    Show-Status $(if ($script:AutoFix) { $script:Ui.AutoOn } else { $script:Ui.AutoOff })
})
$previousPageButton.Add_Click({ Switch-ToPage -Index ($script:CurrentPageIndex - 1) })
$nextPageButton.Add_Click({ Switch-ToPage -Index ($script:CurrentPageIndex + 1) })

$window.Add_Closing({
    param($sender, $eventArgs)
    if ($script:AllowClose) { return }
    if (-not (Test-HasContent)) { return }
    $choice = [System.Windows.MessageBox]::Show(
        $window,
        $script:Ui.CloseMessage,
        $script:Ui.CloseTitle,
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning,
        [System.Windows.MessageBoxResult]::No
    )
    if ($choice -ne [System.Windows.MessageBoxResult]::Yes) {
        $eventArgs.Cancel = $true
    }
    else {
        $script:AllowClose = $true
    }
})

$window.Add_Loaded({
    Update-DrawingAttributes
    Set-DrawingMode -Mode Pen
    Update-PageNavigation
    $script:HintTimer.Start()
    $ink.Focus() | Out-Null
})

if ($UiSelfTest) {
    $window.WindowState = [System.Windows.WindowState]::Normal
    $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::Manual
    $window.Left = -10000
    $window.Top = -10000
    $window.Width = 1280
    $window.Height = 760
    $window.ShowInTaskbar = $false
    $window.ShowActivated = $false
    $window.Add_ContentRendered({
        try {
            if ($null -eq $penButton -or $null -eq $eraserButton -or $null -eq $autoFixButton -or $null -eq $pageText) {
                throw 'Toolbar or page navigation controls are missing.'
            }
            if ($pageText.Text -ne '1 / 1' -or -not $penButton.IsEnabled) { throw 'Initial UI state is invalid.' }

            $rightPoints = New-Object System.Collections.Generic.List[System.Windows.Point]
            foreach ($i in 0..20) {
                $rightPoints.Add((New-Object System.Windows.Point((180.0 + 48.0 * $i), (120.0 + 5.0 * [Math]::Sin($i)))))
            }
            $script:RightStroke = New-StylusStroke -Points $rightPoints -Attributes (New-DrawingAttributes -Color $script:RedColor -FitToCurve $true)
            $script:IsSnapping = $true
            try { $ink.Strokes.Add($script:RightStroke) }
            finally { $script:IsSnapping = $false }
            Finish-RightStroke -Point $rightPoints[$rightPoints.Count - 1]
            if ($ink.Strokes.Count -ne 1 -or $ink.Strokes[0].DrawingAttributes.Color -ne $script:RedColor -or $ink.Strokes[0].StylusPoints.Count -ne 25) {
                throw 'Right-button red stroke did not use automatic correction or preserve its color.'
            }

            $rightCirclePoints = New-Object System.Collections.Generic.List[System.Windows.Point]
            foreach ($i in 0..58) {
                $angle = 0.18 + ((2.0 * [Math]::PI - 0.38) * $i / 58.0)
                $jitter = 4.0 * [Math]::Sin(5.0 * $angle)
                $rightCirclePoints.Add((New-Object System.Windows.Point((1080.0 + (165.0 + $jitter) * [Math]::Cos($angle)), (420.0 + (160.0 + $jitter) * [Math]::Sin($angle)))))
            }
            $script:RightStroke = New-StylusStroke -Points $rightCirclePoints -Attributes (New-DrawingAttributes -Color $script:RedColor -FitToCurve $true)
            $script:IsSnapping = $true
            try { $ink.Strokes.Add($script:RightStroke) }
            finally { $script:IsSnapping = $false }
            Finish-RightStroke -Point $rightCirclePoints[$rightCirclePoints.Count - 1]
            if ($ink.Strokes.Count -ne 2 -or $ink.Strokes[1].DrawingAttributes.Color -ne $script:RedColor -or $ink.Strokes[1].StylusPoints.Count -ne 97) {
                throw 'Right-button red circle did not use automatic correction or preserve its color.'
            }
            $script:IsSnapping = $true
            try { $ink.Strokes.Clear() }
            finally { $script:IsSnapping = $false }
            (Get-CurrentPage).UndoStack.Clear()
            (Get-CurrentPage).RedoStack.Clear()

            $blackRectangle = New-ManualShapeStroke -Kind Rectangle -Start (New-Object System.Windows.Point(160, 180)) -End (New-Object System.Windows.Point(680, 500)) -Color ([System.Windows.Media.Colors]::Black)
            $redCircle = New-ManualShapeStroke -Kind Circle -Start (New-Object System.Windows.Point(920, 180)) -End (New-Object System.Windows.Point(1320, 580)) -Color $script:RedColor
            $linePoints = New-Object System.Collections.Generic.List[System.Windows.Point]
            $linePoints.Add((New-Object System.Windows.Point(240, 720)))
            $linePoints.Add((New-Object System.Windows.Point(1280, 720)))
            $redLine = New-StylusStroke -Points $linePoints -Attributes (New-DrawingAttributes -Color $script:RedColor -FitToCurve $false)
            $script:IsSnapping = $true
            try {
                $ink.Strokes.Add($blackRectangle)
                $ink.Strokes.Add($redCircle)
                $ink.Strokes.Add($redLine)
            }
            finally { $script:IsSnapping = $false }
            Add-NewPage

            $secondPage = New-ManualShapeStroke -Kind Circle -Start (New-Object System.Windows.Point(520, 220)) -End (New-Object System.Windows.Point(1080, 780)) -Color ([System.Windows.Media.Colors]::Black)
            $script:IsSnapping = $true
            try { $ink.Strokes.Add($secondPage) }
            finally { $script:IsSnapping = $false }
            Add-NewPage

            $thirdPage = New-ManualShapeStroke -Kind Rectangle -Start (New-Object System.Windows.Point(360, 260)) -End (New-Object System.Windows.Point(1240, 650)) -Color ([System.Windows.Media.Colors]::Black)
            $script:IsSnapping = $true
            try { $ink.Strokes.Add($thirdPage) }
            finally { $script:IsSnapping = $false }

            Switch-ToPage -Index 1
            if ($ink.Strokes.Count -ne 1) { throw 'Page switching did not preserve page 2.' }
            Remove-CurrentPage -SkipConfirmation
            if ($script:Pages.Count -ne 2 -or $script:CurrentPageIndex -ne 1 -or $ink.Strokes.Count -ne 1) { throw 'Deleting the middle page failed.' }

            Add-UndoSnapshot -Snapshot (Get-StrokesSnapshot)
            $extraLinePoints = New-Object System.Collections.Generic.List[System.Windows.Point]
            $extraLinePoints.Add((New-Object System.Windows.Point(320, 760)))
            $extraLinePoints.Add((New-Object System.Windows.Point(1260, 760)))
            $extraLine = New-StylusStroke -Points $extraLinePoints -Attributes (New-DrawingAttributes -Color ([System.Windows.Media.Colors]::Black) -FitToCurve $false)
            $ink.Strokes.Add($extraLine)
            Invoke-Undo
            if ($ink.Strokes.Count -ne 1) { throw 'Undo failed.' }
            Invoke-Redo
            if ($ink.Strokes.Count -ne 2) { throw 'Redo failed.' }
            $noteBox.Text = 'ui-self-test note'
            Complete-Sketch
        }
        catch {
            $script:AllowClose = $true
            $window.Close()
            throw
        }
    })
}

try {
    $null = $window.ShowDialog()
    if ($script:Completed) {
        foreach ($path in $script:SavedPaths) {
            if (-not (Test-Path -LiteralPath $path)) {
                throw "Sketch export is missing: $path"
            }
        }
        $resultStatus = if ($UiSelfTest) { 'ui_self_test' } else { 'completed' }
        Write-SketchResult ([pscustomobject]@{
            status = $resultStatus
            path = $script:SavedPaths[0]
            paths = @($script:SavedPaths)
            width = $script:ExportWidth
            height = $script:ExportHeight
            note = $script:Note
        })
    }
    else {
        Remove-SavedSketchFiles
        Write-SketchResult ([pscustomobject]@{ status = 'cancelled' })
    }
}
catch {
    Remove-SavedSketchFiles
    Write-SketchResult ([pscustomobject]@{ status = 'error'; message = $_.Exception.Message })
    exit 1
}
