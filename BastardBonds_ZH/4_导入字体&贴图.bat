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


rem Import font assets to game files
echo Writing DLL fonts...
rmdir /s /q "%~dp0..\%GP%\Unity_Assets_Files"
xcopy "%~dp0Data\Unity_Assets_Files" "%~dp0..\%GP%\Unity_Assets_Files\" /S /E /I /Y

rem 使用UnityEX导入资源文件
"%~dp0UnityEX\UnityEX.exe" import "%~dp0..\%GP%\%AP%" -skip_error
"%~dp0UnityEX\UnityEX.exe" import "%~dp0..\%GP%\sharedassets4.assets" -skip_error
"%~dp0UnityEX\UnityEX.exe" import "%~dp0..\%GP%\sharedassets5.assets" -skip_error

rem Completion message
echo Processing completed.
pause
