@echo off

rmdir /s /q "%~dp0Backup"
mkdir "%~dp0Backup"
copy "%~dp0..\BB_Data\Managed\Assembly-CSharp.dll" "%~dp0Backup\"

xcopy "%~dp0..\Core" "%~dp0Backup\Core\" /S /E /I /Y
xcopy "%~dp0..\Dialogue" "%~dp0Backup\Dialogue\" /S /E /I /Y
xcopy "%~dp0..\Maps" "%~dp0Backup\Maps\" /S /E /I /Y
