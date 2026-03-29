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
)


rem Process text in DLL files...
echo Processing text in DLL files...
rem del "%~dp0Data\new_binary.tsv"
del "%~dp0..\%GP%\Managed\Assembly-CSharp.dll.bk"
powershell -ExecutionPolicy Bypass -File "%~dp0Core\Convert-16LEText.ps1" SET2 "%~dp0..\%GP%\Managed\Assembly-CSharp.dll" "%~dp0Data\dll_zh.tsv" [a-zA-Z]

rem Completion message
echo Processing completed.
pause
