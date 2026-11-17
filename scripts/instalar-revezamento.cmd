@echo off
rem Clique duplo para aplicar o esquema "1 host revezando" (porta unica 47989 +
rem identidade/pareamento compartilhados). Pede um UAC.
title sunshine-dual - aplicar 1-host revezando
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply-revezamento.ps1"
