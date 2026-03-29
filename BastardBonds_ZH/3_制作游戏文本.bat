@echo off
setlocal enabledelayedexpansion
set GP=BB_Data
set AP=sharedassets0.assets

echo Processing translation files...
powershell -ExecutionPolicy Bypass -File "%~dp0Core\SPDL.ps1" -InputFile "%~dp0TSV\dll_zh.tsv" -OutputFile "%~dp0Data\dll_zh.tsv"
powershell -ExecutionPolicy Bypass -File "%~dp0Core\SPDL.ps1" -InputFile "%~dp0TSV\binary_zh.tsv" -OutputFile "%~dp0Data\binary_zh.tsv"

echo Processing completed
pause
