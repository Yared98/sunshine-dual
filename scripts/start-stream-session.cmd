@echo off
rem Double-click to bring up the streaming-user session after a reboot.
rem Logs the streaming user in over the RDP loopback; its Apollo instance then
rem starts from the Startup launcher. Keep the Remote Desktop window visible
rem (do not minimize).
title sunshine-dual - subir sessao de streaming
powershell -ExecutionPolicy Bypass -File "%~dp0session-up.ps1"
echo.
echo Sessao pronta. Conecte o Moonlight no IP deste PC (porta padrao do Apollo).
echo (Mantenha a janela do Remote Desktop aberta, sem minimizar.)
pause
