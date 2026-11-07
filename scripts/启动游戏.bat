@echo off
cd /d "%~dp0.."
where godot >nul 2>nul
if %errorlevel%==0 (
    godot --path game
    exit /b %errorlevel%
)
where godot4 >nul 2>nul
if %errorlevel%==0 (
    godot4 --path game
    exit /b %errorlevel%
)
echo Godot not found in PATH. Open game\project.godot using Godot 4.7.2 editor.
exit /b 1
