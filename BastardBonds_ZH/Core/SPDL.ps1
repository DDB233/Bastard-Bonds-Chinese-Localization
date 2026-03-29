param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile,

    [Parameter(Mandatory=$true)]
    [string]$OutputFile,

    [int]$Clm = 0
)

$OutputFile = $OutputFile.Trim('"')
$InputFile = $InputFile.Trim('"')

if (-not (Test-Path $InputFile)) {
    Write-Error "Input file not found: $InputFile"
    exit 1
}

$dir = Split-Path -Path $OutputFile -Parent
if ($dir -and -not (Test-Path -Path $dir -PathType Container)) {
    New-Item -Path $dir -ItemType Directory | Out-Null
}

try {
    $data = [System.IO.File]::ReadAllText($InputFile, [System.Text.Encoding]::UTF8)

    # Use character codes to avoid encoding issues
    # U+3002 = Ideographic Full Stop (。)
    # U+FF0C = Ideographic Comma (，)
    # U+FF01 = Fullwidth Exclamation Mark (！)
    # U+FF1F = Fullwidth Question Mark (？)
    
    $period = [char]0x3002
    $comma = [char]0xFF0C
    $exclamation = [char]0xFF01
    $question = [char]0xFF1F

    if ($Clm -gt 0) {
        $index = $Clm - 1
        
        $result = $data -split "`r?`n" | ForEach-Object {
            $cols = $_ -split "`t"
            if ($cols.Count -gt $index) {
                $text = $cols[$index]
                $text = $text.Replace("$period", "$period ")
                $text = $text.Replace("$comma", "$comma ")
                $text = $text.Replace("$exclamation", "$exclamation ")
                $text = $text.Replace("$question", "$question ")
                $text = $text.Replace(" $period", "$period")
                $text = $text.Replace(" $comma", "$comma")
                $text = $text.Replace(" $exclamation", "$exclamation")
                $text = $text.Replace(" $question", "$question")
                $text
            }
        }
        
        $result | Out-File -FilePath $OutputFile -Encoding utf8 -Force
        Write-Host "Extracted column $Clm and saved."
    }
    else {
        $convertedData = $data.Replace("$period", "$period ")
        $convertedData = $convertedData.Replace("$comma", "$comma ")
        $convertedData = $convertedData.Replace("$exclamation", "$exclamation ")
        $convertedData = $convertedData.Replace("$question", "$question ")
        $convertedData = $convertedData.Replace(" $period", "$period")
        $convertedData = $convertedData.Replace(" $comma", "$comma")
        $convertedData = $convertedData.Replace(" $exclamation", "$exclamation")
        $convertedData = $convertedData.Replace(" $question", "$question")
        [System.IO.File]::WriteAllText($OutputFile, $convertedData, [System.Text.Encoding]::UTF8)
        Write-Host "All data processed and saved."
    }

    Write-Host "--- Done ---"
    Write-Host "Saved to: $OutputFile"
}
catch {
    Write-Error "Processing failed. Error: $($_.Exception.Message)"
    exit 1
}