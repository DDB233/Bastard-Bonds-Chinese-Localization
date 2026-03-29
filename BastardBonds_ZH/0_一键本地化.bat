@echo off
setlocal enabledelayedexpansion
set GP=BB_Data
set AP=sharedassets0.assets

rem Check if UnityEX.exe exists
IF NOT EXIST "%~dp0UnityEX\UnityEX.exe" (
    echo UnityEX.exe not found.
    pause
    exit /b
)


rem Check if backup exists, if not create backup, otherwise restore files from backup
IF NOT EXIST "%~dp0Backup" (
    rmdir /s /q "%~dp0Backup"
    mkdir "%~dp0Backup"
    copy "%~dp0..\BB_Data\Managed\Assembly-CSharp.dll" "%~dp0Backup\"

    xcopy "%~dp0..\Core" "%~dp0Backup\Core\" /S /E /I /Y
    xcopy "%~dp0..\Dialogue" "%~dp0Backup\Dialogue\" /S /E /I /Y
    xcopy "%~dp0..\Maps" "%~dp0Backup\Maps\" /S /E /I /Y
) ELSE (
    rem Restore files from backup to game directory
    copy "%~dp0Backup\Assembly-CSharp.dll" "%~dp0..\BB_Data\Managed\" 
    xcopy "%~dp0Backup\Core" "%~dp0..\Core\"  /S /E /I /Y
    xcopy "%~dp0Backup\Dialogue" "%~dp0..\Dialogue\" /S /E /I /Y
    xcopy "%~dp0Backup\Maps" "%~dp0..\Maps\" /S /E /I /Y
)


echo Starting localization process

powershell -ExecutionPolicy Bypass -File "%~dp0Core\fnt.ps1" -fnt "%~dp0Fonts\zh.fnt" -out "%~dp0Data\Unity_Assets_Files\sharedassets0\FONT_XBOX_PRE.font_raw" -size 0

rem Start copying and replacing files...
rem Copy Fonts\zh_0.dds to Fonts\FONT_XBOX.tex.dds
copy "%~dp0Fonts\zh_0.dds" "%~dp0Fonts\FONT_XBOX.tex.dds"

rem Replace Data\Unity_Assets_Files\sharedassets0\Textures\FONT_XBOX.tex.dds
copy "%~dp0Fonts\FONT_XBOX.tex.dds" "%~dp0Data\Unity_Assets_Files\sharedassets0\Textures\FONT_XBOX.tex.dds"

rem Delete temporary files...
del "%~dp0Fonts\FONT_XBOX.tex.dds"

echo Font files processed successfully.



echo Processing localization files...
powershell -ExecutionPolicy Bypass -File "%~dp0Core\SPDL.ps1" -InputFile "%~dp0TSV\dll_zh.tsv" -OutputFile "%~dp0Data\dll_zh.tsv"
powershell -ExecutionPolicy Bypass -File "%~dp0Core\SPDL.ps1" -InputFile "%~dp0TSV\binary_zh.tsv" -OutputFile "%~dp0Data\binary_zh.tsv"
echo Processing complete


rem Copy processed assets to game files
echo Writing DLL assets...
rmdir /s /q "%~dp0..\%GP%\Unity_Assets_Files"
xcopy "%~dp0Data\Unity_Assets_Files" "%~dp0..\%GP%\Unity_Assets_Files\" /S /E /I /Y

rem Use UnityEX to import asset files
"%~dp0UnityEX\UnityEX.exe" import "%~dp0..\%GP%\%AP%" -skip_error
"%~dp0UnityEX\UnityEX.exe" import "%~dp0..\%GP%\sharedassets4.assets" -skip_error
"%~dp0UnityEX\UnityEX.exe" import "%~dp0..\%GP%\sharedassets5.assets" -skip_error

rem Process text in DLL files...
echo Processing text in DLL files...
rem del "%~dp0Data\new_binary.tsv"
del "%~dp0..\%GP%\Managed\Assembly-CSharp.dll.bk"
powershell -ExecutionPolicy Bypass -File "%~dp0Core\Convert-16LEText.ps1" SET2 "%~dp0..\%GP%\Managed\Assembly-CSharp.dll" "%~dp0Data\dll_zh.tsv" [a-zA-Z]

rem Process text in binary files...
echo Processing text in binary files...
powershell -ExecutionPolicy Bypass -File "%~dp0Core\rebinary.ps1" -tsv "%~dp0Data\binary_zh.tsv" -FPath "%~dp0..\Maps"
powershell -ExecutionPolicy Bypass -File "%~dp0Core\rebinary.ps1" -tsv "%~dp0Data\binary_zh.tsv" -FPath "%~dp0..\Dialogue"
powershell -ExecutionPolicy Bypass -File "%~dp0Core\rebinary.ps1" -tsv "%~dp0Data\binary_zh.tsv" -FPath "%~dp0..\Core"

rem Display completion message
echo All processing completed successfully.
pause
