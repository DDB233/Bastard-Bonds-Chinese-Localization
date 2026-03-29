# =================================================================
# Binary Translator (High Speed Edition - Cumulative Replace)
# =================================================================
param(
    [Parameter(Mandatory=$true)][string]$tsv,
    [Parameter(Mandatory=$true)][string]$FPath,
    [switch]$newf
)

# 1. Environment variable protection
$env:LIB = ""
$env:CL = ""

# 2. C# source code definition
$source = @"
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

public class BinaryTranslator {
    public class TranslationData {
        public string english;
        public string japanese;
    }

    public static List<string> ProcessFile(string filePath, Dictionary<string, List<TranslationData>> translations, bool outputNew) {
        byte[] bytes = File.ReadAllBytes(filePath);
        string fileName = Path.GetFileName(filePath);
        List<string> newTexts = new List<string>();
        bool isModified = false;
        int foundStringsCount = 0;

        using (MemoryStream output = new MemoryStream()) {
            int pos = 0;
            while (pos < bytes.Length) {
                if (bytes[pos] == 0x00) {
                    output.WriteByte(0x00);
                    pos++;
                    continue;
                }

                int posA = pos;
                byte b1 = bytes[pos];
                int stringLength = 0;
                int headerSize = 0;

                if (b1 < 0x80) {
                    stringLength = b1;
                    headerSize = 1;
                } else {
                    if (pos + 1 >= bytes.Length) { output.WriteByte(bytes[pos]); pos++; continue; }
                    byte b2 = bytes[pos + 1];
                    stringLength = (b2 * 128) + (b1 - 128);
                    headerSize = 2;
                }

                int contentOffset = pos + headerSize;
                if (contentOffset + stringLength > bytes.Length) {
                    output.WriteByte(bytes[pos]);
                    pos++;
                    continue;
                }

                // Character string validation
                bool isString = true;
                bool hasAlphabet = false;
                for (int i = 0; i < stringLength; i++) {
                    byte b = bytes[contentOffset + i];
                    if (b < 32 && b != 9 && b != 10 && b != 13) {
                        isString = false;
                        break;
                    }
                    if ((b >= 65 && b <= 90) || (b >= 97 && b <= 122)) {
                        hasAlphabet = true;
                    }
                }

                if (!isString || !hasAlphabet) {
                    output.WriteByte(bytes[pos]);
                    pos = posA + 1;
                    continue;
                }

                foundStringsCount++;
                byte[] originalBytes = new byte[stringLength];
                Array.Copy(bytes, contentOffset, originalBytes, 0, stringLength);
                
                string rawText = Encoding.UTF8.GetString(originalBytes);
                string visualText = rawText
                    .Replace("\r\n", "{CRLF}").Replace("\r", "{CR}").Replace("\n", "{LF}")
                    .Replace("\t", "{TAB}").Replace("\"", "\u201D");

                string key = fileName + "_" + foundStringsCount;

                if (translations.ContainsKey(key)) {
                    // --- Cumulative Replace execution ---
                    string currentText = visualText;
                    foreach (var entry in translations[key]) {
                        currentText = currentText.Replace(entry.english, entry.japanese);
                    }
                    
                    // Convert tags back to binary
                    string finalString = currentText
                        .Replace("{CRLF}", "\r\n").Replace("{CR}", "\r").Replace("{LF}", "\n")
                        .Replace("{TAB}", "\t").Replace("\u201D", "\"");

                    byte[] newBytes = Encoding.UTF8.GetBytes(finalString);
                    
                    // New possible header
                    if (newBytes.Length < 128) {
                        output.WriteByte((byte)newBytes.Length);
                    } else {
                        output.WriteByte((byte)((newBytes.Length % 128) + 128));
                        output.WriteByte((byte)(newBytes.Length / 128));
                    }
                    output.Write(newBytes, 0, newBytes.Length);
                    isModified = true;
                } else {
                    if (outputNew) {
                        newTexts.Add(fileName + "\t" + foundStringsCount + "\t" + visualText);
                    }
                    output.Write(bytes, pos, headerSize + stringLength);
                }
                pos += (headerSize + stringLength);
            }

            if (isModified) {
                File.WriteAllBytes(filePath, output.ToArray());
            }
        }
        return newTexts;
    }
}
"@

# 3. Add-Type (reference assembly)
try {
    $assemblies = @("System", "System.Core")
    Add-Type -TypeDefinition $source -Language CSharp -ReferencedAssemblies $assemblies
} catch {
    Write-Host "C# Compilation Failed" -ForegroundColor Red
    exit
}

# 4. TSV reading (create dictionary by key, holding all translation rows)
$transDict = New-Object "System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[BinaryTranslator+TranslationData]]"

if (Test-Path $tsv) {
    $lines = [System.IO.File]::ReadAllLines($tsv, [System.Text.Encoding]::UTF8)
    foreach ($line in $lines) {
        $cols = $line.Split("`t")
        if ($cols.Count -ge 5 -and $cols[1] -match '^\d+$') {
            $key = "$($cols[0])_$($cols[1])"
            
            if (-not $transDict.ContainsKey($key)) {
                $transDict[$key] = New-Object "System.Collections.Generic.List[BinaryTranslator+TranslationData]"
            }
            
            $data = New-Object "BinaryTranslator+TranslationData"
            $data.english = $cols[3]
            $data.japanese = $cols[4]
            $transDict[$key].Add($data)
        }
    }
}

# 5. Execution
$targetFiles = Get-ChildItem -Path $FPath -Recurse -File
$allNewTexts = New-Object System.Collections.Generic.List[string]

foreach ($f in $targetFiles) {
    Write-Host "Processing: $($f.Name)"
    $res = [BinaryTranslator]::ProcessFile($f.FullName, $transDict, [bool]$newf)
    if ($res) { $allNewTexts.AddRange($res) }
}

# 6. New output
if ($newf -and $allNewTexts.Count -gt 0) {
    $outPath = Join-Path $PSScriptRoot "new_binary.tsv"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::AppendAllLines($outPath, $allNewTexts, $utf8NoBom)
    Write-Host "New texts saved to: $outPath" -ForegroundColor Green
}