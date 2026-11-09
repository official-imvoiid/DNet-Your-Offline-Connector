@echo off
rem Builds DNet for Android and Windows, once. The finished apps land in
rem dist\ and nothing else does:
rem
rem   dist\DNet-Android.apk        install on Android 10 or later
rem   dist\DNet-Windows\dnet.exe   run on Windows 10 or 11 (keep the folder)
rem
rem Needs Flutter, Rust, the Android SDK and VS Build Tools (see README.md).
rem Release APKs are signed with app\android\key.properties when it exists.
setlocal
set "ROOT=%~dp0"

if exist "%ROOT%dist" rmdir /s /q "%ROOT%dist"
if exist "%ROOT%dist" (
  echo Could not empty dist\. Close DNet if it is running from there.
  exit /b 1
)

pushd "%ROOT%app" || exit /b 1
call flutter build apk --release || goto failed
call flutter build windows --release || goto failed
popd

echo.
echo Done. The apps are in %ROOT%dist
dir /b "%ROOT%dist"
exit /b 0

:failed
popd
echo.
echo The build failed; see the messages above.
exit /b 1
