@echo off
rem Clique duplo para ligar o monitor virtual (headless_mode) no Apollo de console
rem principal. Pede um UAC. So edita a config e reinicia o servico.
title sunshine-dual - ligar monitor virtual
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ligar-monitor-virtual.ps1"
