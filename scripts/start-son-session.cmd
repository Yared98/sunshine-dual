@echo off
rem Double-click to bring up the SwitchGamer streaming session after a reboot.
rem Logs SwitchGamer in over the RDP loopback; Apollo-2 then starts from its
rem Startup launcher. Keep the Remote Desktop window visible (do not minimize).
title sunshine-dual - subir sessao do filho
powershell -ExecutionPolicy Bypass -File "%~dp0session-up.ps1"
echo.
echo Sessao pronta. O filho pode conectar o Artemis em: 192.168.1.3:48989
echo (Mantenha a janela do Remote Desktop aberta, sem minimizar.)
pause
