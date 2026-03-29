# Convert-16LEText.ps1
# PowerShell port of VB.NET code for UTF-16LE string operations in EXE/DLL files.

#==================================================================================
# Help Output (using here-document to avoid string parsing errors)
#==================================================================================
function HELP_OUT() {
    @"
Error stopped.
====================================================================================
This software rewrites 16LE type English text written inside EXE/DLL files to Japanese/Chinese text.
※ Cannot rewrite beyond the original text length.
※ If the rewrite text is shorter, half-width spaces will be added to the end.

    Arguments: [SET/GET/SET2/GET2] [Target file path (EXE/DLL)] [Translation file path (required for SET/SET2)] Or [Duplicate exclusion mode:ON (for GET/GET2 only)] [Regular expression (required for GET2)]

    Translation file: A text file described in the format of original`ttranslation.

    <When executing GET>
    　　Detected text will be output to target file path + `.txt`.
    　　Text with less than 2 consecutive alphabetic characters is intentionally not output.
    　　Text containing control code characters is intentionally not output.
    　　When duplicate exclusion mode argument is set to "ON", duplicate text will not be output.
    　　　　※ However, processing is very slow.
    　　　　※ If not specified or anything other than "ON", duplicates will also be output.

    <When executing SET>
    　　Text with less than 2 consecutive alphabetic characters on the original side is intentionally not processed.
    　　Text containing control code characters on the original side is intentionally not processed.
    　　If detected text matches the original side in the translation file,
    　　and the translation text is below the original byte count,
    　　the rewrite will be executed.
    　　If the byte count is exceeded, the translation file +`.error.txt` will output
    　　the target text in the state of [Byte count]Text.

    　　If SET processing completes normally,
    　　the original file will be backed up with .bk appended to the end.
    　　If .bk already exists, it will be backed up as (number).bk.

    <When executing GET2: String judgment restrictions are removed.>
    　　Detected text will be output to target file path + `.txt`.
    　　Text containing control code characters is intentionally not output.
    　　Duplicate exclusion mode specification must always be specified (ON or OFF).
    　　Regular expression to extract must always be specified.
    　　　　To extract only text containing alphabets, specify '[a-zA-Z]'.

    <When executing SET2: String judgment restrictions are removed.>
    　　Regular expression to extract must always be specified.
    　　　　To extract only text containing alphabets, specify '[a-zA-Z]'.
    　　Text containing control code characters on the original side is intentionally not processed.
    　　If detected text matches the original side in the translation file,
    　　and the translation text is below the original byte count,
    　　the rewrite will be executed.
    　　If the byte count is exceeded, the translation file +`.error.txt` will output
    　　the target text in the state of [Byte count]Text.

    　　If SET processing completes normally,
    　　the original file will be backed up with .bk appended to the end.
    　　If .bk already exists, it will be backed up as (number).bk.
====================================================================================
"@ | Write-Host
    exit 1
}

#==================================================================================
# Binary file reading (handles file length type conversion errors)
#==================================================================================
function ByteRead([string]$fullName) {
    $fs = New-Object System.IO.FileStream($fullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
    [int64]$fileLength = $fs.Length
    $ByR = New-Object byte[]($fileLength)
    $fs.Read($ByR, 0, $fileLength)
    $fs.Close()
    return $ByR
}

#==================================================================================
# Control character escape processing
#==================================================================================
function KAIGYOU([string]$TxD, [int]$mode) {
    if ($mode -eq 0) {
        return $TxD.Replace("`r`n", "{CRLF}").Replace("`n", "{LF}").Replace("`t", "\t")
    } else {
        return $TxD.Replace("{CRLF}", "`r`n").Replace("{LF}", "`n").Replace("\t", "`t")
    }
}

#==================================================================================
# Backup processing
#==================================================================================
function BackupFile([string]$fullName, [string]$tempName) {
    $nu = 1
    if (Test-Path "$fullName.bk") {
        do {
            $nu++
        } while (Test-Path "$fullName($nu).bk")
        Move-Item $fullName -Destination "$fullName($nu).bk" -Force
    } else {
        Move-Item $fullName -Destination "$fullName.bk" -Force
    }
    Move-Item $tempName -Destination $fullName -Force
}

#==================================================================================
# Translation file reading and map creation (TSV parsing)
#==================================================================================
function Load-TranslationMap([string]$translationFilePath) {

    $translationMap = @{}
    $lines = [System.IO.File]::ReadAllLines(
        $translationFilePath,
        [System.Text.Encoding]::GetEncoding("utf-8")
    )

    foreach ($line in $lines) {

        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $parts = $line -split "`t"

        if ($parts.Length -lt 2) { continue }

        # Remove double quotes from original text (1st column)
        # Handle both ASCII quotes and Unicode curly quotes
        $originalText = $parts[0].Trim() -replace '["\u201C\u201D]', ''
        $translated = $parts[1].Trim()

        $key   = KAIGYOU $originalText 0
        $value = KAIGYOU $translated 0

        if (-not $translationMap.ContainsKey($key)) {
            $translationMap[$key] = $value
        }
    }

    # # Debug: Output translationMap to log file
    # $debugLogPath = Join-Path $PSScriptRoot "debug_translation_map.log"
    # $logWriter = New-Object System.IO.StreamWriter($debugLogPath, $false, [System.Text.Encoding]::GetEncoding("utf-8"))
    # $logWriter.WriteLine("========== Translation Map Debug Log ==========")
    # $logWriter.WriteLine("Timestamp: " + (Get-Date).ToString())
    # $logWriter.WriteLine("Translation file: $translationFilePath")
    # $logWriter.WriteLine("Total entries: " + $translationMap.Count)
    # $logWriter.WriteLine("")
    # $logWriter.WriteLine("---------- Translation Map Contents ----------")
    # foreach ($entry in $translationMap.GetEnumerator()) {
    #     $logWriter.WriteLine("Key: [$($entry.Key)]")
    #     $logWriter.WriteLine("Value: [$($entry.Value)]")
    #     $logWriter.WriteLine("---")
    # }
    # $logWriter.WriteLine("========== End of Translation Map ==========")
    # $logWriter.Close()
    # Write-Host "Debug log saved to: $debugLogPath"

    return $translationMap
}


#==================================================================================
# SET_TEXT: Replace strings in binary based on translation file (with filter)
#==================================================================================
function SET_TEXT([string]$fullName, [Hashtable]$translationMap) {
    $errorLogPath = $cmds[3] + ".error.txt"
    $Logwriter = New-Object System.IO.StreamWriter($errorLogPath, $true, [System.Text.Encoding]::GetEncoding("utf-8"))

    $utf16LE = [System.Text.Encoding]::Unicode
    $bytDt   = ByteRead $fullName
    $tempName = $fullName + ".temp"

    [int64]$s  = 0
    [int64]$os = 0
    [int]$shorichu     = 0
    [int]$reigai       = 0
    [int]$mojisu       = 0
    [int]$kaita        = 0
    [int]$nibaitodatta = 0
    [int]$st           = 0

    $Logwriter.WriteLine("**********" + (Get-Date).ToString())

    $dest = New-Object System.IO.FileStream(
        $tempName,
        [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::Write
    )

    while ($s -lt $bytDt.Length - 2) {

        $os = $s
        $kaita = 0
        $nibaitodatta = 0

        if ($shorichu -eq 0) {

            if ($bytDt[$s] -eq 0) {
                while ($bytDt[$s] -eq 0 -and $s -lt $bytDt.Length - 2) {
                    $dest.WriteByte([byte]$bytDt[$s])
                    $s++
                }
                $shorichu = 1
            } else {
                $dest.WriteByte([byte]$bytDt[$s])
                $s++
            }

        } else {

            if ($bytDt[$s] -lt 128) {
                $mojisu = $bytDt[$s]
                $s++
            }
            elseif ($bytDt[$s] -lt 158) {
                $mojisu = ($bytDt[$s] - 128) * 256 + $bytDt[$s+1]
                $s += 2
                $nibaitodatta = 1
            }
            else {
                $s++
                $shorichu = 0
            }

            if ($s + $mojisu -gt $bytDt.Length) { $shorichu = 0 }

            if ($shorichu -eq 1) {
                if ($bytDt[$s + $mojisu - 1] -ne 0 -and $bytDt[$s + $mojisu - 1] -ne 1) { $shorichu = 0 }
                if ($bytDt[$s] -eq 0) { $shorichu = 0 }
            }

            if ($mojisu -lt 2) {
                $shorichu = 0
                $reigai = 1
                $s--
            }

            if ($shorichu -eq 1) {

                $TempBy = New-Object byte[]($mojisu - 1)
                [Array]::Copy($bytDt, $s, $TempBy, 0, $mojisu - 1)

                for ([int]$z = 0; $z -lt $TempBy.Length - 1; $z++) {
                    if ($TempBy[$z+1] -eq 0 -and
                        $TempBy[$z]   -ne 9 -and
                        $TempBy[$z]   -ne 10 -and
                        $TempBy[$z]   -ne 11 -and
                        $TempBy[$z]   -ne 12 -and
                        $TempBy[$z]   -ne 13 -and
                        $TempBy[$z]   -lt 32) {
                        $shorichu = 0
                        break
                    }
                }

                if ($shorichu -eq 1) {

                    $TxD = $utf16LE.GetString($TempBy)

                    $rx     = New-Object System.Text.RegularExpressions.Regex("[a-zA-Z][a-zA-Z]")
                    $result = $rx.IsMatch($TxD)

                    if ($result -eq $true) {

                        # Perform line break replacement (KAIGYOU) first, then Trim
                        $TxD_Escaped         = KAIGYOU $TxD 0
                        $TxD_Trimmed_Escaped = $TxD_Escaped.Trim().Replace('"', "")

                        $slotBytes = $mojisu - 1
                        $origBytes = $TempBy.Length

                        if ($translationMap.ContainsKey($TxD_Trimmed_Escaped)) {

                            $NewTx_Escaped = $translationMap[$TxD_Trimmed_Escaped]
                            $NewTx         = KAIGYOU $NewTx_Escaped 1
                            $JPByte        = $utf16LE.GetBytes($NewTx)
                            $transBytes    = $JPByte.Length

                            if ($slotBytes % 2 -ne 0) {
                                $Logwriter.WriteLine("Odd byte slot, cannot rewrite======================")
                                $Logwriter.WriteLine("[$slotBytes]$TxD")
                            }
                            elseif ($transBytes -gt $slotBytes) {
                                $Logwriter.WriteLine("Translation byte count Over======================")
                                $Logwriter.WriteLine("[$origBytes]$TxD")
                                $Logwriter.WriteLine("[$transBytes]$NewTx")
                            }
                            else {
                                $needed = $slotBytes - $transBytes
                                if ($needed -gt 0) {
                                    $pad = New-Object byte[]($needed)
                                    for ($i = 0; $i -lt $needed; $i += 2) {
                                        $pad[$i] = 32
                                        if ($i + 1 -lt $needed) { $pad[$i+1] = 0 }
                                    }
                                    $JPByte = $JPByte + $pad
                                }

                                Write-Host $NewTx

                                if ($nibaitodatta -eq 1) {
                                    $dest.WriteByte([byte]$bytDt[$os])
                                    $dest.WriteByte([byte]$bytDt[$os + 1])
                                } else {
                                    $dest.WriteByte([byte]$bytDt[$os])
                                }

                                $dest.Write($JPByte, 0, $JPByte.Length)
                                $dest.WriteByte([byte]$bytDt[$s + $mojisu - 1])
                                $kaita = 1
                            }
                        }
                    }

                    if ($kaita -eq 1) {
                        $s += $mojisu
                        $st = 1
                        continue
                    }

                    $s++
                    $st = 1
                }
            }

            if ($kaita -eq 0) {
                for ([int64]$y = $os; $y -le $s; $y++) {
                    $dest.WriteByte([byte]$bytDt[$y])
                }
            }

            $s++
            if ($st -eq 1 -and $shorichu -eq 0 -and $reigai -eq 0) { $st = 0 }
            $reigai = 0
        }
    }

    for ([int64]$y = $s; $y -lt $bytDt.Length; $y++) {
        $dest.WriteByte([byte]$bytDt[$y])
    }

    $dest.Close()
    $Logwriter.Close()
    BackupFile $fullName $tempName
}

#==================================================================================
# SET2_TEXT: Replace strings in binary based on translation file (with regex filter)
#==================================================================================
function SET2_TEXT([string]$fullName, [Hashtable]$translationMap, [string]$seikihyougen) {

    $errorLogPath = $cmds[3] + ".error.txt"
    $Logwriter = New-Object System.IO.StreamWriter($errorLogPath, $true, [System.Text.Encoding]::GetEncoding("utf-8"))

    $utf16LE = [System.Text.Encoding]::Unicode
    $bytDt   = ByteRead $fullName
    $tempName = $fullName + ".temp"

    [int64]$s  = 0
    [int64]$os = 0
    [int]$shorichu     = 0
    [int]$reigai       = 0
    [int]$mojisu       = 0
    [int]$kaita        = 0
    [int]$nibaitodatta = 0
    [int]$st           = 0

    $Logwriter.WriteLine("**********" + (Get-Date).ToString())

    $dest = New-Object System.IO.FileStream(
        $tempName,
        [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::Write
    )

    while ($s -lt $bytDt.Length - 2) {

        $os = $s
        $kaita = 0
        $nibaitodatta = 0

        if ($shorichu -eq 0) {

            if ($bytDt[$s] -eq 0) {
                while ($bytDt[$s] -eq 0 -and $s -lt $bytDt.Length - 2) {
                    try { $dest.WriteByte([byte]$bytDt[$s]) } catch {}
                    $s++
                }
                $shorichu = 1
            } else {
                try { $dest.WriteByte([byte]$bytDt[$s]) } catch {}
                $s++
            }

        } else {

            if ($bytDt[$s] -lt 128) {
                $mojisu = $bytDt[$s]
                $s++
            }
            elseif ($bytDt[$s] -lt 158) {
                $mojisu = ($bytDt[$s] - 128) * 256 + $bytDt[$s+1]
                $s += 2
                $nibaitodatta = 1
            }
            else {
                $s++
                $shorichu = 0
            }

            if ($s + $mojisu -gt $bytDt.Length) { $shorichu = 0 }

            if ($shorichu -eq 1) {
                if ($bytDt[$s + $mojisu - 1] -ne 0 -and $bytDt[$s + $mojisu - 1] -ne 1) { $shorichu = 0 }
                if ($bytDt[$s] -eq 0) { $shorichu = 0 }
            }

            if ($mojisu -lt 2) {
                $shorichu = 0
                $reigai = 1
                $s--
            }

            if ($shorichu -eq 1) {

                $TempBy = New-Object byte[]($mojisu - 1)
                [Array]::Copy($bytDt, $s, $TempBy, 0, $mojisu - 1)

                for ([int]$z = 0; $z -lt $TempBy.Length - 1; $z++) {
                    if ($TempBy[$z+1] -eq 0 -and
                        $TempBy[$z]   -ne 9 -and
                        $TempBy[$z]   -ne 10 -and
                        $TempBy[$z]   -ne 11 -and
                        $TempBy[$z]   -ne 12 -and
                        $TempBy[$z]   -ne 13 -and
                        $TempBy[$z]   -lt 32) {
                        $shorichu = 0
                        break
                    }
                }

                if ($shorichu -eq 1) {

                    $TxD    = $utf16LE.GetString($TempBy)
                    $result = [System.Text.RegularExpressions.Regex]::IsMatch($TxD, $seikihyougen)

                    if ($result -eq $true) {

                        # Perform line break replacement (KAIGYOU) first, then Trim
                        $TxD_Escaped         = KAIGYOU $TxD 0
                        $TxD_Trimmed_Escaped = $TxD_Escaped.Trim().Replace('"', "")

                        $slotBytes = $mojisu - 1
                        $origBytes = $TempBy.Length

                        if ($translationMap.ContainsKey($TxD_Trimmed_Escaped)) {

                            $NewTx_Escaped = $translationMap[$TxD_Trimmed_Escaped]
                            $NewTx         = KAIGYOU $NewTx_Escaped 1
                            $JPByte        = $utf16LE.GetBytes($NewTx)
                            $transBytes    = $JPByte.Length

                            if ($slotBytes % 2 -ne 0) {
                                $Logwriter.WriteLine("Odd byte slot, cannot rewrite======================")
                                $Logwriter.WriteLine("[$slotBytes]$TxD")
                            }
                            elseif ($transBytes -gt $slotBytes) {
                                $Logwriter.WriteLine("Translation byte count Over======================")
                                $Logwriter.WriteLine("[$origBytes]$TxD")
                                $Logwriter.WriteLine("[$transBytes]$NewTx")
                            }
                            else {
                                $needed = $slotBytes - $transBytes
                                if ($needed -gt 0) {
                                    $pad = New-Object byte[]($needed)
                                    for ($i = 0; $i -lt $needed; $i += 2) {
                                        $pad[$i] = 160
                                        if ($i + 1 -lt $needed) { $pad[$i+1] = 0 }
                                    }
                                    $JPByte = $JPByte + $pad
                                }

                                Write-Host $NewTx

                                if ($nibaitodatta -eq 1) {
                                    $dest.WriteByte([byte]$bytDt[$os])
                                    $dest.WriteByte([byte]$bytDt[$os + 1])
                                } else {
                                    $dest.WriteByte([byte]$bytDt[$os])
                                }

                                $dest.Write($JPByte, 0, $JPByte.Length)
                                try { $dest.WriteByte([byte]$bytDt[$s + $mojisu - 1]) } catch {}

                                $kaita = 1
                            }
                        }
                    }

                    if ($kaita -eq 1) {
                        $s += $mojisu
                        $st = 1
                        continue
                    }
                }
            }

            if ($kaita -eq 0) {
                for ([int64]$y = $os; $y -le $s; $y++) {
                    try { $dest.WriteByte([byte]$bytDt[$y]) } catch {}
                }
            }

            $s++
            if ($st -eq 1 -and $shorichu -eq 0 -and $reigai -eq 0) { $st = 0 }
            $reigai = 0
        }
    }

    for ([int64]$y = $s; $y -lt $bytDt.Length; $y++) {
        try { $dest.WriteByte([byte]$bytDt[$y]) } catch {}
    }

    $dest.Close()
    $Logwriter.Close()
    BackupFile $fullName $tempName
}

#==================================================================================
# GET_TEXT: Extract strings from binary (with filter)
#==================================================================================
function GET_TEXT([string]$fullName, [int]$FLGRE) {
    $outputLogPath = $cmds[2] + ".txt"
    $Logwriter = New-Object System.IO.StreamWriter($outputLogPath, $true, [System.Text.Encoding]::GetEncoding("utf-8"))
    
    $utf16LE = [System.Text.Encoding]::Unicode
    $bytDt = ByteRead $fullName
    $OUT = "`r`n"
    
    [int64]$s = 0
    [int]$shorichu = 0
    [int]$reigai = 0
    [int]$st = 0
    [int]$mojisu = 0
    [int]$kaita = 0
    
    while ($s -lt $bytDt.Length - 2) {
        $kaita = 0
        
        if ($shorichu -eq 0) {
            if ($bytDt[$s] -eq 0) {
                while ($bytDt[$s] -eq 0 -and $s -lt $bytDt.Length - 2) {
                    $s++
                }
                $shorichu = 1
            } else {
                $s++
            }
        } else {
            if ($bytDt[$s] -lt 128) {
                $mojisu = $bytDt[$s]
                $s++
            } elseif ($bytDt[$s] -lt 158) {
                $mojisu = ($bytDt[$s] - 128) * 256 + $bytDt[$s+1]
                $s += 2
            } else {
                $s++
                $shorichu = 0
            }
            
            if ($s + $mojisu -gt $bytDt.Length) { $shorichu = 0 }
            
            if ($shorichu -eq 1) {
                if ($bytDt[$s + $mojisu - 1] -ne 0 -and $bytDt[$s + $mojisu - 1] -ne 1) {
                    $shorichu = 0
                }
                if ($bytDt[$s] -eq 0) { $shorichu = 0 }
            }
            
            if ($mojisu -lt 2) {
                $shorichu = 0
                $reigai = 1
                $s--
            }

            if ($shorichu -eq 1) {
                $TempBy = New-Object byte[]($mojisu - 1)
                [Array]::Copy($bytDt, $s, $TempBy, 0, $mojisu - 1)
                
                for ([int]$z = 0; $z -lt $TempBy.Length - 1; $z++) {
                    if ($TempBy[$z+1] -eq 0 -and $TempBy[$z] -ne 9 -and $TempBy[$z] -ne 10 -and $TempBy[$z] -ne 11 -and $TempBy[$z] -ne 12 -and $TempBy[$z] -ne 13 -and $TempBy[$z] -lt 32) {
                        $shorichu = 0
                        break
                    }
                }
                
                if ($shorichu -eq 1) {
                    $TxD = $utf16LE.GetString($TempBy)
                    
                    $rx = New-Object System.Text.RegularExpressions.Regex("[a-zA-Z][a-zA-Z]")
                    $result = $rx.IsMatch($TxD)
                    $TxD_Escaped = KAIGYOU $TxD 0
                    
                    if ($result -eq $true) {
                        if ($FLGRE -eq 1) {
                            if ($OUT.IndexOf("`r`n" + $TxD_Escaped + "`r`n") -eq -1) {
                                Write-Host $TxD_Escaped
                                $Logwriter.WriteLine($TxD_Escaped)
                                $OUT = $OUT + $TxD_Escaped + "`r`n"
                            }
                        } else {
                            Write-Host $TxD_Escaped
                            $Logwriter.WriteLine($TxD_Escaped)
                        }
                        $kaita = 1
                    }
                    
                    # Always advance by mojisu
                    $s += $mojisu
                    $st = 1
                    continue
                }
            }
            
            if ($st -eq 1 -and $shorichu -eq 0 -and $reigai -eq 0) { $st = 0 }
            $reigai = 0
            $s++
        }
    }
    
    $Logwriter.Close()
}

#==================================================================================
# GET2_TEXT: Extract strings from binary (with regex filter)
#==================================================================================
function GET2_TEXT([string]$fullName, [int]$FLGRE, [string]$seikihyougen) {
    $outputLogPath = $cmds[2] + ".txt"
    $Logwriter = New-Object System.IO.StreamWriter($outputLogPath, $true, [System.Text.Encoding]::GetEncoding("utf-8"))
    
    $utf16LE = [System.Text.Encoding]::Unicode
    $bytDt = ByteRead $fullName
    $OUT = "`r`n"
    
    [int64]$s = 0
    [int]$shorichu = 0
    [int]$reigai = 0
    [int]$st = 0
    [int]$mojisu = 0
    [int]$kaita = 0
    
    while ($s -lt $bytDt.Length - 2) {
        $kaita = 0
        
        if ($shorichu -eq 0) {
            if ($bytDt[$s] -eq 0) {
                while ($bytDt[$s] -eq 0 -and $s -lt $bytDt.Length - 2) {
                    $s++
                }
                $shorichu = 1
            } else {
                $s++
            }
        } else {
            if ($bytDt[$s] -lt 128) {
                $mojisu = $bytDt[$s]
                $s++
            } elseif ($bytDt[$s] -lt 158) {
                $mojisu = ($bytDt[$s] - 128) * 256 + $bytDt[$s+1]
                $s += 2
            } else {
                $s++
                $shorichu = 0
            }
            
            if ($s + $mojisu -gt $bytDt.Length) { $shorichu = 0 }
            
            if ($shorichu -eq 1) {
                if ($bytDt[$s + $mojisu - 1] -ne 0 -and $bytDt[$s + $mojisu - 1] -ne 1) {
                    $shorichu = 0
                }
                if ($bytDt[$s] -eq 0) { $shorichu = 0 }
            }
            
            if ($mojisu -lt 2) {
                $shorichu = 0
                $reigai = 1
                $s--
            }

            if ($shorichu -eq 1) {
                $TempBy = New-Object byte[]($mojisu - 1)
                [Array]::Copy($bytDt, $s, $TempBy, 0, $mojisu - 1)
                
                for ([int]$z = 0; $z -lt $TempBy.Length - 1; $z++) {
                    if ($TempBy[$z+1] -eq 0 -and $TempBy[$z] -ne 9 -and $TempBy[$z] -ne 10 -and $TempBy[$z] -ne 11 -and $TempBy[$z] -ne 12 -and $TempBy[$z] -ne 13 -and $TempBy[$z] -lt 32) {
                        $shorichu = 0
                        break
                    }
                }
                
                if ($shorichu -eq 1) {
                    $TxD = $utf16LE.GetString($TempBy)
                    
                    $result = [System.Text.RegularExpressions.Regex]::IsMatch($TxD, $seikihyougen)
                    $TxD_Escaped = KAIGYOU $TxD 0 
                    
                    if ($result -eq $true) {
                        if ($FLGRE -eq 1) {
                            if ($OUT.IndexOf("`r`n" + $TxD_Escaped + "`r`n") -eq -1) {
                                Write-Host $TxD_Escaped
                                $Logwriter.WriteLine($TxD_Escaped)
                                $OUT = $OUT + $TxD_Escaped + "`r`n"
                            }
                        } else {
                            Write-Host $TxD_Escaped
                            $Logwriter.WriteLine($TxD_Escaped)
                        }
                        $kaita = 1
                    }
                    
                    # Always advance by mojisu
                    $s += $mojisu
                    $st = 1
                    continue

                }
            }
            
            if ($st -eq 1 -and $shorichu -eq 0 -and $reigai -eq 0) { $st = 0 }
            $reigai = 0
            $s++
        }
    }
    
    $Logwriter.Close()
}


#==================================================================================
# Main Processing
#==================================================================================

$cmds = $args
$cmds = @(".\Convert-16LEText.ps1") + $cmds 

if ($cmds.Length -lt 3) {
    HELP_OUT
}

$command = $cmds[1].ToLower()
$filePath = $cmds[2]

switch ($command) {
    "set" {
        if ($cmds.Length -lt 4) { HELP_OUT }
        $translationFilePath = $cmds[3]
        $translationMap = @{}
        if (Test-Path $translationFilePath) {
            $translationMap = Load-TranslationMap $translationFilePath
        }
        SET_TEXT $filePath $translationMap
    }
    "get" {
        $REFLG = 0
        if ($cmds.Length -gt 3) {
            if ($cmds[3].ToLower() -eq "on") {
                $REFLG = 1
            }
        }
        GET_TEXT $filePath $REFLG
    }
    "set2" {
        if ($cmds.Length -lt 5) { HELP_OUT }
        $translationFilePath = $cmds[3]
        $seikihyougen = $cmds[4]
        $translationMap = @{}
        if (Test-Path $translationFilePath) {
            $translationMap = Load-TranslationMap $translationFilePath
        }
        SET2_TEXT $filePath $translationMap $seikihyougen
    }
    "get2" {
        if ($cmds.Length -lt 5) { HELP_OUT }
        $REFLG = 0
        $seikihyougen = $cmds[4]
        if ($cmds[3].ToLower() -eq "on") {
            $REFLG = 1
        }
        GET2_TEXT $filePath $REFLG $seikihyougen
    }
    default {
        HELP_OUT
    }
}