@echo off
chcp 65001 >nul
echo.
echo  最新のデータを取りに行っています。10秒ほどお待ちください...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1"
if errorlevel 1 (
  echo.
  echo  データを取得できませんでした。インターネット接続を確認してください。
  echo  （前回のデータがあれば、それを表示します）
  pause
)
start "" "%~dp0index.html"
