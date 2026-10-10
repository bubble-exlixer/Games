@echo off
cd /d "%~dp0"
rem First run: turn your Godot download into DeadShift.exe. Godot loads DeadShift.pck automatically when it sits next to an exe with the same name.
if not exist DeadShift.exe (
  for %%f in (Godot_v4.4*_win64.exe) do copy /y "%%f" DeadShift.exe >nul
)
if exist DeadShift.exe (
  start "" DeadShift.exe
  exit /b
)
echo Put Godot_v4.4.1-stable_win64.exe (from godotengine.org) in this folder, then run this again.
pause
