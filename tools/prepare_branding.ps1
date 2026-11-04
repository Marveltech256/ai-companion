param([string]$SourceImage = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
function ProjectPath([string]$relative) {
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $relative))
    if (-not $resolved.StartsWith($projectRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Asset path must stay inside the project.' }
    return $resolved
}
$original = ProjectPath 'assets/branding/logo-original.png'
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($original)) | Out-Null
if ($SourceImage) {
    $inputPath = (Resolve-Path -LiteralPath $SourceImage).Path
    if ($inputPath -ne $original) { Copy-Item -LiteralPath $inputPath -Destination $original }
}
$source = [System.Drawing.Bitmap]::new($original)
try {
    # Find the supplied mark's bounds; keep the original source byte-for-byte.
    $left = $source.Width; $top = $source.Height; $right = -1; $bottom = -1
    for ($y=0; $y -lt $source.Height; $y++) {
        for ($x=0; $x -lt $source.Width; $x++) {
            $pixel = $source.GetPixel($x,$y)
            if ($pixel.A -gt 0 -and ($pixel.R -lt 250 -or $pixel.G -lt 250 -or $pixel.B -lt 250)) {
                $left=[Math]::Min($left,$x); $right=[Math]::Max($right,$x)
                $top=[Math]::Min($top,$y); $bottom=[Math]::Max($bottom,$y)
            }
        }
    }
    if ($right -lt $left) { throw 'The source contains no visible mark.' }
    $left=[Math]::Max(0,$left-2); $top=[Math]::Max(0,$top-2)
    $right=[Math]::Min($source.Width-1,$right+2); $bottom=[Math]::Min($source.Height-1,$bottom+2)
    $bounds=[System.Drawing.Rectangle]::new($left,$top,$right-$left+1,$bottom-$top+1)
    function ExportIcon([string]$relative,[int]$size,[double]$coverage=0.70,[bool]$transparent=$false) {
        $destination=ProjectPath $relative
        [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($destination)) | Out-Null
        $format=if($transparent){[System.Drawing.Imaging.PixelFormat]::Format32bppArgb}else{[System.Drawing.Imaging.PixelFormat]::Format24bppRgb}
        $bitmap=[System.Drawing.Bitmap]::new($size,$size,$format)
        $graphics=[System.Drawing.Graphics]::FromImage($bitmap)
        try {
            if($transparent){$graphics.Clear([System.Drawing.Color]::Transparent)}else{$graphics.Clear([System.Drawing.Color]::White)}
            $graphics.InterpolationMode=[System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode=[System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $scale=$size*$coverage/[Math]::Max($bounds.Width,$bounds.Height)
            $width=[int][Math]::Round($bounds.Width*$scale); $height=[int][Math]::Round($bounds.Height*$scale)
            $target=[System.Drawing.Rectangle]::new([int](($size-$width)/2),[int](($size-$height)/2),$width,$height)
            $graphics.DrawImage($source,$target,$bounds,[System.Drawing.GraphicsUnit]::Pixel)
            $bitmap.Save($destination,[System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $graphics.Dispose(); $bitmap.Dispose() }
    }
    ExportIcon 'assets/branding/logo-mark.png' 256 0.84
    ExportIcon 'assets/branding/app-icon.png' 1024
    ExportIcon 'web/favicon.png' 48 0.86
    foreach($size in @(192,512)) {
        ExportIcon "web/icons/Icon-$size.png" $size
        ExportIcon "web/icons/Icon-maskable-$size.png" $size 0.60
    }
    foreach($density in @(@('mdpi',48),@('hdpi',72),@('xhdpi',96),@('xxhdpi',144),@('xxxhdpi',192))) {
        ExportIcon "android/app/src/main/res/mipmap-$($density[0])/ic_launcher.png" ([int]$density[1])
    }
    # Adaptive foreground bounds fit the central 66/108-dp safe circle.
    ExportIcon 'android/app/src/main/res/drawable/ic_launcher_foreground.png' 432 0.45 $true
    $catalog = [System.IO.File]::ReadAllText((ProjectPath 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json')) | ConvertFrom-Json
    foreach($entry in $catalog.images) {
        if($entry.filename) {
            $points=[double]::Parse(($entry.size -split 'x')[0],[System.Globalization.CultureInfo]::InvariantCulture)
            $scale=[double]::Parse(($entry.scale -replace 'x',''),[System.Globalization.CultureInfo]::InvariantCulture)
            ExportIcon "ios/Runner/Assets.xcassets/AppIcon.appiconset/$($entry.filename)" ([int][Math]::Round($points*$scale))
        }
    }
    [pscustomobject]@{Source=$original;Width=$source.Width;Height=$source.Height;MarkBounds=$bounds.ToString();SHA256=(Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash} | Format-List
} finally { $source.Dispose() }
