@echo off
set /p SIZE_VAL="Please enter font size (0-5)px: "

rem Input validation (if not 0-5, set to 0)
if "%SIZE_VAL%"=="" set SIZE_VAL=0
if %SIZE_VAL% LSS 0 (set SIZE_VAL=0)
if %SIZE_VAL% GTR 5 (set SIZE_VAL=0)

echo Size set to: %SIZE_VAL%
echo Starting font file creation


powershell -ExecutionPolicy Bypass -File "%~dp0Core\fnt.ps1" -fnt "%~dp0Fonts\zh.fnt" -out "%~dp0Data\Unity_Assets_Files\sharedassets0\FONT_XBOX_PRE.font_raw" -size %SIZE_VAL%


rem 开始复制和替换字体文件...
rem 复制 Fonts\zh_0.dds 到 Fonts\FONT_XBOX.tex.dds
copy "%~dp0Fonts\zh_0.dds" "%~dp0Fonts\FONT_XBOX.tex.dds"

rem 替换 Data\Unity_Assets_Files\sharedassets0\Textures\FONT_XBOX.tex.dds
copy "%~dp0Fonts\FONT_XBOX.tex.dds" "%~dp0Data\Unity_Assets_Files\sharedassets0\Textures\FONT_XBOX.tex.dds"

rem 清理临时文件...
del "%~dp0Fonts\FONT_XBOX.tex.dds"

echo Font file creation completed!


pause
