@echo off
rem Plays the copy of the game in this folder.
set "GODOT=%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe(1)\Godot_v4.7.2-stable_win64.exe"
rem The 3D models must be imported once before the game can load them.
if not exist "%~dp0.godot\imported\Knight.glb-*.scn" start "" /wait "%GODOT%" --headless --path "%~dp0." --editor --import --quit
start "" "%GODOT%" --path "%~dp0."
