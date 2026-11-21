@echo off
chcp 65001 >nul
cd /d "%~dp0\.."
echo Установка зависимостей...
call npm install
if errorlevel 1 goto error
echo Сборка Windows EXE...
call npm run dist:win
if errorlevel 1 goto error
echo.
echo Готово! EXE-файлы находятся в папке release.
pause
exit /b 0
:error
echo.
echo Сборка не удалась. Убедитесь, что установлен Node.js 20+ и есть интернет.
pause
exit /b 1
