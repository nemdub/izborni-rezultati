@echo off
chcp 65001 >nul
powershell -ExecutionPolicy Bypass -File "%~dp0izborni_rezultati.ps1"
pause
