@echo off
title Envol - diagnostic
echo Lancement d'Envol en mode diagnostic...
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Envol.ps1"
echo.
echo Code de sortie : %errorlevel%
pause
