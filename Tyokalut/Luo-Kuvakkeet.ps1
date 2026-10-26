# ============================================================
# HUOLTOKELLO - Tyopoytakuvakkeiden (clipart) luonti
#
# Piirtaa .ico-kuvakkeet suoraan GDI+lla (ei ulkoisia tyokaluja):
#   assets\huoltokello.ico        = toimistotietokone + kello
#   assets\huoltokello-ohjeet.ico = lamppu (hehkulamppu)
#
# Tulos: monikokoiset ikonit (16, 24, 32, 48, 64, 128, 256 px,
# 32-bittinen alfa). Aja uudelleen, jos haluat muuttaa kuvia.
#
# Kaytto:
#   powershell -ExecutionPolicy Bypass -File Tyokalut\Luo-Kuvakkeet.ps1
# Valinnaisesti: -OutDir "kansio" ja -PreviewDir "kansio" (PNG-esikatselu)
# ============================================================
param(
    [string]$OutDir,
    [string]$PreviewDir
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot '..\assets' }
$OutDir = [IO.Path]::GetFullPath((Join-Path $OutDir '.'))
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# ---------- Apurit ----------

function New-Color([int]$r, [int]$gg, [int]$bb, [int]$aa = 255) {
    return [System.Drawing.Color]::FromArgb($aa, $r, $gg, $bb)
}

function New-RoundRectPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function New-RoundPen([System.Drawing.Color]$color, [single]$width) {
    $pen = New-Object System.Drawing.Pen($color, $width)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    return $pen
}

# ---------- Kuva 1: Huoltokello = toimistotietokone + kello ----------

function New-HuoltokelloBitmap {
    $bmp = New-Object System.Drawing.Bitmap(256, 256, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode   = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $frame  = New-Color 47 65 86        # tumma siniharmaa
    $frame2 = New-Color 36 50 66
    $screen = New-Color 237 245 252     # vaalea naytto
    $white  = New-Color 255 255 255
    $hand   = New-Color 47 65 86
    $second = New-Color 231 76 60       # punainen sekuntiviisari
    $tick   = New-Color 127 166 196
    $green  = New-Color 39 174 96

    # Jalusta (kaula + pohja) nayton alle
    $g.FillPath((New-Object System.Drawing.SolidBrush($frame)), (New-RoundRectPath 112 176 32 26 6))
    $g.FillPath((New-Object System.Drawing.SolidBrush($frame)), (New-RoundRectPath 74 200 108 18 9))

    # Nayton kehys ja itse naytto
    $monPath = New-RoundRectPath 18 24 220 164 20
    $g.FillPath((New-Object System.Drawing.SolidBrush($frame)), $monPath)
    $g.DrawPath((New-Object System.Drawing.Pen($frame2, 4)), $monPath)
    $g.FillPath((New-Object System.Drawing.SolidBrush($screen)), (New-RoundRectPath 34 40 188 132 10))

    # Kello naytolla (kello 10:10 -asento)
    $cx = 128; $cy = 106; $r = 46
    $g.FillEllipse((New-Object System.Drawing.SolidBrush($white)), $cx - $r, $cy - $r, $r * 2, $r * 2)
    $g.DrawEllipse((New-Object System.Drawing.Pen($hand, 7)), $cx - $r, $cy - $r, $r * 2, $r * 2)

    $tickPen = New-RoundPen $tick 6
    $g.DrawLine($tickPen, $cx, $cy - $r + 6,  $cx, $cy - $r + 16)   # 12
    $g.DrawLine($tickPen, $cx + $r - 6,  $cy, $cx + $r - 16, $cy)   # 3
    $g.DrawLine($tickPen, $cx, $cy + $r - 6,  $cx, $cy + $r - 16)   # 6
    $g.DrawLine($tickPen, $cx - $r + 6,  $cy, $cx - $r + 16, $cy)   # 9

    $g.DrawLine((New-RoundPen $hand 10), $cx, $cy, 106, 90)          # tuntiviisari
    $g.DrawLine((New-RoundPen $hand 8),  $cx, $cy, 152, 82)          # minuuttiviisari
    $g.DrawLine((New-RoundPen $second 4), $cx, $cy, 142, 132)        # sekuntiviisari
    $g.FillEllipse((New-Object System.Drawing.SolidBrush($hand)),   $cx - 7, $cy - 7, 14, 14)
    $g.FillEllipse((New-Object System.Drawing.SolidBrush($second)), $cx - 3, $cy - 3, 6, 6)

    # Vihrea valmius-merkki (huolto tehty) monitorin kulmassa
    $g.FillEllipse((New-Object System.Drawing.SolidBrush($green)), 172, 30, 56, 56)
    $g.DrawEllipse((New-Object System.Drawing.Pen($white, 6)), 172, 30, 56, 56)
    $chk = New-RoundPen $white 10
    $g.DrawLine($chk, 186, 60, 196, 70)
    $g.DrawLine($chk, 196, 70, 214, 46)

    $g.Dispose()
    return $bmp
}

# ---------- Kuva 2: Huoltokello-Ohjeet = lamppu ----------

function New-OhjeetBitmap {
    $bmp = New-Object System.Drawing.Bitmap(256, 256, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode   = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $bulbFill = New-Color 255 215 94    # lamppu
    $bulbEdge = New-Color 232 160 19
    $ray      = New-Color 245 166 35    # hehke
    $gray1    = New-Color 154 168 177
    $gray2    = New-Color 135 149 160
    $gray3    = New-Color 116 130 141
    $gray4    = New-Color 100 113 123
    $qColor   = New-Color 138 90 0      # kysymysmerkki

    $cx = 128; $cy = 108

    # Hehkesateet lamppun ylapuoliskolla
    $rayPen = New-RoundPen $ray 10
    foreach ($deg in @(-160, -135, -110, -90, -70, -45, -20)) {
        $a = $deg * [Math]::PI / 180.0
        $x1 = [single]($cx + [Math]::Cos($a) * 76)
        $y1 = [single]($cy + [Math]::Sin($a) * 76)
        $x2 = [single]($cx + [Math]::Cos($a) * 98)
        $y2 = [single]($cy + [Math]::Sin($a) * 98)
        $g.DrawLine($rayPen, $x1, $y1, $x2, $y2)
    }

    # Lamppun lasi + kiilto
    $r = 60
    $g.FillEllipse((New-Object System.Drawing.SolidBrush($bulbFill)), $cx - $r, $cy - $r, $r * 2, $r * 2)
    $g.DrawEllipse((New-Object System.Drawing.Pen($bulbEdge, 6)), $cx - $r, $cy - $r, $r * 2, $r * 2)
    $g.FillEllipse((New-Object System.Drawing.SolidBrush((New-Color 255 255 255 120))), $cx - 44, $cy - 44, 26, 26)

    # Kysymysmerkki (ohje) lasin sisalla
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment     = [System.Drawing.StringAlignment]::Center
    $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $font = New-Object System.Drawing.Font('Segoe UI', 74, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $g.DrawString('?', $font, (New-Object System.Drawing.SolidBrush($qColor)), (New-Object System.Drawing.RectangleF(($cx - 40), ($cy - 48), 80, 96)), $fmt)
    $font.Dispose()

    # Kaula ja kierreosa + tiputus
    $neck = @(
        (New-Object System.Drawing.PointF(110, 162)),
        (New-Object System.Drawing.PointF(146, 162)),
        (New-Object System.Drawing.PointF(150, 188)),
        (New-Object System.Drawing.PointF(106, 188))
    )
    $g.FillPolygon((New-Object System.Drawing.SolidBrush($gray1)), $neck)
    $g.FillPath((New-Object System.Drawing.SolidBrush($gray1)), (New-RoundRectPath 100 190 56 13 5))
    $g.FillPath((New-Object System.Drawing.SolidBrush($gray2)), (New-RoundRectPath 103 205 50 13 5))
    $g.FillPath((New-Object System.Drawing.SolidBrush($gray3)), (New-RoundRectPath 106 220 44 13 5))
    $g.FillPath((New-Object System.Drawing.SolidBrush($gray4)), (New-RoundRectPath 114 235 28 10 4))

    $g.Dispose()
    return $bmp
}

# ---------- ICO-tiedoston kirjoitus (BMP-DIB-runko, 32-bit alfa) ----------

function ConvertTo-IcoFile {
    param([System.Drawing.Bitmap]$Source, [string]$Path)

    $sizes = 16, 24, 32, 48, 64, 128, 256
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)

    $bw.Write([uint16]0)              # reserved
    $bw.Write([uint16]1)              # tyyppi 1 = kuvake
    $bw.Write([uint16]$sizes.Count)   # kuvien maara

    $offset  = 6 + 16 * $sizes.Count
    $entries = @()
    $images  = @()

    foreach ($s in $sizes) {
        $bmp = New-Object System.Drawing.Bitmap($s, $s, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $srcRect = New-Object System.Drawing.Rectangle(0, 0, $Source.Width, $Source.Height)
        $dstRect = New-Object System.Drawing.Rectangle(0, 0, $s, $s)
        $g.DrawImage($Source, $dstRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose()

        $rect = New-Object System.Drawing.Rectangle(0, 0, $s, $s)
        $bd = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $stride = $bd.Stride
        $raw = New-Object byte[] ($stride * $s)
        [Runtime.InteropServices.Marshal]::Copy($bd.Scan0, $raw, 0, $raw.Length)
        $bmp.UnlockBits($bd)
        $bmp.Dispose()

        # XOR-data alhaalta ylospain (BGRA)
        $xor = New-Object byte[] ($s * $s * 4)
        for ($y = 0; $y -lt $s; $y++) {
            [Array]::Copy($raw, (($s - 1 - $y) * $stride), $xor, ($y * $s * 4), ($s * 4))
        }

        # AND-maski (32-bittisen alfa kanavan kanssa nollamaski), rivit 4 tavun rajoissa
        $maskStride = ([int][Math]::Ceiling($s / 32.0)) * 4
        $mask = New-Object byte[] ($maskStride * $s)

        $len = 40 + $xor.Length + $mask.Length

        $entries += ,@(
            [byte]($(if ($s -eq 256) { 0 } else { $s })),
            [byte]($(if ($s -eq 256) { 0 } else { $s })),
            [uint16]1, [uint16]32, [uint32]$len, [uint32]$offset
        )

        $imgMs = New-Object System.IO.MemoryStream
        $iw = New-Object System.IO.BinaryWriter($imgMs)
        $iw.Write([uint32]40)                     # BITMAPINFOHEADER: biSize
        $iw.Write([int32]$s)                      # biWidth
        $iw.Write([int32]($s * 2))                # biHeight (XOR + maski)
        $iw.Write([uint16]1)                      # biPlanes
        $iw.Write([uint16]32)                     # biBitCount
        $iw.Write([uint32]0)                      # biCompression = BI_RGB
        $iw.Write([uint32]($xor.Length + $mask.Length))
        $iw.Write([int32]0); $iw.Write([int32]0)
        $iw.Write([uint32]0); $iw.Write([uint32]0)
        $iw.Write($xor); $iw.Write($mask)
        $iw.Flush()
        $images += ,($imgMs.ToArray())
        $iw.Dispose(); $imgMs.Dispose()

        $offset += $len
    }

    foreach ($e in $entries) {
        $bw.Write([byte]$e[0]); $bw.Write([byte]$e[1])
        $bw.Write([byte]0);     $bw.Write([byte]0)
        $bw.Write([uint16]$e[2]); $bw.Write([uint16]$e[3])
        $bw.Write([uint32]$e[4]); $bw.Write([uint32]$e[5])
    }
    foreach ($img in $images) { $bw.Write($img) }
    $bw.Flush()
    [IO.File]::WriteAllBytes($Path, $ms.ToArray())
    $bw.Dispose(); $ms.Dispose()
}

# ---------- Luonti ----------

$results = @()

foreach ($job in @(
    @('huoltokello.ico',        'New-HuoltokelloBitmap'),
    @('huoltokello-ohjeet.ico', 'New-OhjeetBitmap')
)) {
    $name = $job[0]
    $path = Join-Path $OutDir $name
    $bmp = & $job[1]
    ConvertTo-IcoFile -Source $bmp -Path $path
    if ($PreviewDir) {
        New-Item -ItemType Directory -Force -Path $PreviewDir | Out-Null
        $bmp.Save((Join-Path $PreviewDir ($name -replace '\.ico$', '.png')), [System.Drawing.Imaging.ImageFormat]::Png)
    }
    $bmp.Dispose()

    # Varmistus: kuvake latautuu sekali 256 px etta 16 px kokoisena
    $iBig   = New-Object System.Drawing.Icon($path, 256, 256)
    $iSmall = New-Object System.Drawing.Icon($path, 16, 16)
    $results += ("OK: {0} ({1} tavua, ladattu {2}x{2} ja {3}x{3})" -f $path, (Get-Item $path).Length, $iBig.Width, $iSmall.Width)
    $iBig.Dispose(); $iSmall.Dispose()
}

$results | ForEach-Object { Write-Host $_ }
Write-Host "Valmis: kuvakkeet tallennettu kansioon $OutDir"