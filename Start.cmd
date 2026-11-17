@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-Cursor.ps1"
if errorlevel 1 pause
