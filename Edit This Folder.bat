@echo off
rem Opens the copy of the game in this folder in the Godot editor.
start "" "%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe(1)\Godot_v4.7.2-stable_win64.exe" --editor --path "%~dp0."
