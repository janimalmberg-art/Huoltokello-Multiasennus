@echo off
rem ==============================================================
rem  Huoltokello Multiasennus - Kaynnistin
rem  Avaa graafisen asennusvelhon (tai ajaa -Silent / -SelfTest).
rem ==============================================================
setlocal
cd /d "%~dp0"
if not exist "Asenna-Huoltokello-Multa.ps1" (
  echo Virhe: Asenna-Huoltokello-Multa.ps1 ei loydy tasta kansiosta.
  echo Pura koko Huoltokello-Multiasennus-kansio kokonaisuudessaan.
  pause
  exit /b 1
)
if not exist "app.zip" (
  echo Virhe: app.zip ei loydy tasta kansiosta - paketti on epataisollinen.
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "Asenna-Huoltokello-Multa.ps1" %*
if errorlevel 1 (
  echo.
  echo Asennusvelho paattyi virheeseen tai asennus keskeytyi.
  pause
)
endlocal