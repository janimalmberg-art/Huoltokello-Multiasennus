@echo off
cd /d "C:\Users\PC\Desktop\Huoltokello-Multiasennus"
(echo.) | powershell -NoProfile -ExecutionPolicy Bypass -File Julkaise-GitHub.ps1 -Viesti "v2.8.1: sovellus 2.8.0 - uusi ulkoasu (sivupalkki), suoritustason mittari ja Excel-kokoontai; app.zip ja talousosa 1.1.0 mukana" > Julkaise-281.log 2>&1
