param (
    [Parameter(Mandatory=$true)]
    [string]$fnt,
    [int]$size = 0,
    [string]$out = ""
)

# Output file name determination
$targetPath = if ([string]::IsNullOrWhiteSpace($out)) { "$fnt.bin" } else { $out }

# Constant settings
# $Y_OFFSET_CONST = 48  # Y-axis offset for Japanese (not needed for Chinese fonts)
$Y_OFFSET_CONST = 0    # For Chinese fonts: no offset
$IMG_W = 2048
$IMG_H = 1024

# 1. Fixed header (32 bytes)
$fixedHeader = [byte[]](
    0x00,0x00,0x00,0x00, 0x00,0x00,0x80,0x3F, 
    0xCD,0xCC,0xCC,0x3D, 0x00,0x00,0x00,0x00, 
    0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00, 
    0x00,0x00,0x00,0x00, 0x02,0x00,0x00,0x00
)

# 2. Footer (44 bytes)
$footer = [byte[]](
    0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00, 
    0x00,0x00,0x00,0x00, 0xCD,0xCC,0xCC,0x3D, 
    0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00, 
    0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00, 
    0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00, 
    0x00,0x00,0x00,0x00
)

# Output buffer
$outputBytes = New-Object System.Collections.Generic.List[byte]

# Extract only char lines
$lines = Get-Content $fnt | Where-Object { $_ -match "^char\s+id=" }
$dataCount = $lines.Count

# --- Write start ---

# A. Header section
$outputBytes.AddRange($fixedHeader)
$outputBytes.AddRange([BitConverter]::GetBytes([int]$dataCount)) # Data count (4byte)

# B. Data section (44 bytes per character)
foreach ($line in $lines) {
    if ($line -match "id=(?<id>\d+)\s+x=(?<x>\d+)\s+y=(?<y>\d+)\s+width=(?<w>\d+)\s+height=(?<h>\d+)\s+xoffset=(?<xoff>-?\d+)\s+yoffset=(?<yoff>-?\d+)\s+xadvance=(?<xadv>-?\d+)") {
        
        $charId = [int]$Matches['id']
        $w_px   = [int]$Matches['w']
        $h_px   = [int]$Matches['h']
        $xoff   = [int]$Matches['xoff']
        $yoff   = [int]$Matches['yoff']

        # --- 1-7 unchanged ---
        $outputBytes.AddRange([BitConverter]::GetBytes($charId))
        $outputBytes.AddRange([BitConverter]::GetBytes([single]([int]$Matches['x'] / $IMG_W)))
        $v_offset = if ($charId -ge 163) { $Y_OFFSET_CONST } else { 0 }
        $v_val = ($IMG_H - ([int]$Matches['y'] + $h_px + $v_offset)) / $IMG_H
        $outputBytes.AddRange([BitConverter]::GetBytes([single]$v_val))
        $outputBytes.AddRange([BitConverter]::GetBytes([single]($w_px / $IMG_W)))
        $outputBytes.AddRange([BitConverter]::GetBytes([single]($h_px / $IMG_H)))
        $outputBytes.AddRange([BitConverter]::GetBytes([single]$xoff))
        $outputBytes.AddRange([BitConverter]::GetBytes([single]-$yoff))
        
        # 8. Display width: if width is zero, don't add size
        $addSizeX = if ($w_px -eq 0) { 0 } else { $size }
        $displayW = [single]($w_px + $xoff + $addSizeX)
        $outputBytes.AddRange([BitConverter]::GetBytes($displayW))
        
        # 9. Display height: Y direction add directly
        $displayH = [single](-$h_px - $size)
        $outputBytes.AddRange([BitConverter]::GetBytes($displayH)) 
        
        # 10. xadvance: if width is zero, don't add size
        $xadv_val = [single]([int]$Matches['xadv'] + $addSizeX)
        $outputBytes.AddRange([BitConverter]::GetBytes($xadv_val))
        
        # 11. Unknown: fixed 0
        $outputBytes.AddRange([BitConverter]::GetBytes([single]0.0))                 
    }
}


# C. Footer section
$outputBytes.AddRange($footer)

# File output
[IO.File]::WriteAllBytes($targetPath, $outputBytes.ToArray())
Write-Host "Conversion completed: (Data count: $dataCount, Total size: $($outputBytes.Count) bytes)"