@echo off
rem Builds the DUnitX suite for Win32 and Win64 and runs both, one after the
rem other. These are the platforms the library is tested on - nothing else is.
rem
rem Delphi 12 Athens (Studio 23.0). Set BDS to use another installation.
rem Each Tests.exe runs from its own output directory: the test data paths are
rem relative to the working directory, not to the executable.
rem
rem Exit code 0 only when both platforms built and passed.

setlocal
if "%BDS%"=="" set "BDS=C:\Program Files (x86)\Embarcadero\Studio\23.0"
cd /d "%~dp0dunitx"

set FAILED=
call :platform Win32 dcc32 || set FAILED=%FAILED% Win32
call :platform Win64 dcc64 || set FAILED=%FAILED% Win64

echo.
if "%FAILED%"=="" (
  echo Win32 and Win64 passed.
  exit /b 0
)
echo FAILED:%FAILED%
exit /b 1

:platform
echo.
echo ==== %1 ====
if not exist "%1\Debug" mkdir "%1\Debug"
rem a stale Tests.exe must not pass for a failed build
if exist "%1\Debug\Tests.exe" del "%1\Debug\Tests.exe"
"%BDS%\bin\%2.exe" -B -Q --no-config -DCI ^
  "-U%BDS%\lib\%1\release;%BDS%\source\DUnitX;..\source" ^
  "-I%BDS%\lib\%1\release" ^
  "-NU%1\Debug" "-E%1\Debug" ^
  "-NSSystem;System.Win;Winapi;Data;Xml;Vcl" ^
  Tests.dpr
if not exist "%1\Debug\Tests.exe" (
  echo %1: the build failed
  exit /b 1
)
pushd "%1\Debug"
.\Tests.exe --exitbehavior:Continue
set RESULT=%ERRORLEVEL%
popd
exit /b %RESULT%
