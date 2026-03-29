@echo off
setlocal enabledelayedexpansion
set GP=BB_Data
set AP=sharedassets0.assets

rem Check if UnityEX.exe tool exists
IF NOT EXIST "%~dp0UnityEX\UnityEX.exe" (
    echo Error: UnityEX.exe not found.
    pause
    exit /b
)


rem Check if backup exists, if not create backup, otherwise restore backup files
IF NOT EXIST "%~dp0Backup" (
    rmdir /s /q "%~dp0Backup"
    mkdir "%~dp0Backup"
    copy "%~dp0..\BB_Data\Managed\Assembly-CSharp.dll" "%~dp0Backup\"

    xcopy "%~dp0..\Core" "%~dp0Backup\Core\" /S /E /I /Y
    xcopy "%~dp0..\Dialogue" "%~dp0Backup\Dialogue\" /S /E /I /Y
    xcopy "%~dp0..\Maps" "%~dp0Backup\Maps\" /S /E /I /Y
) ELSE (
    rem Restore files from backup to game directory
    xcopy "%~dp0Backup\Core" "%~dp0..\Core\"  /S /E /I /Y
    xcopy "%~dp0Backup\Dialogue" "%~dp0..\Dialogue\" /S /E /I /Y
    xcopy "%~dp0Backup\Maps" "%~dp0..\Maps\" /S /E /I /Y
)


rem Translate text in binary files
echo Translating binary text...
powershell -ExecutionPolicy Bypass -File "%~dp0Core\rebinary.ps1" -tsv "%~dp0Data\binary_zh.tsv" -FPath "%~dp0..\Maps"
powershell -ExecutionPolicy Bypass -File "%~dp0Core\rebinary.ps1" -tsv "%~dp0Data\binary_zh.tsv" -FPath "%~dp0..\Dialogue"
powershell -ExecutionPolicy Bypass -File "%~dp0Core\rebinary.ps1" -tsv "%~dp0Data\binary_zh.tsv" -FPath "%~dp0..\Core"

rem Completion message
echo Processing completed.
pause
