@echo off
rem Re-creates the stl\robbie_*.stl print files from base.scad.
rem Each part is exported at print LOD, turned for the bed (print_layout=true).

setlocal
set OPENSCAD="C:\Program Files\OpenSCAD (Nightly)\openscad.com"
set OPTS=--backend=manifold -D LOD=2.0 -D print_layout=true

cd /d "%~dp0"

call :export 1 base
call :export 2 collar
call :export 3 guide
call :export 4 pinion
call :export 6 home_switch_plug
call :export 7 lower_sled
call :export 8 upper_sled
call :export 9 sled_top
call :export 10 sled_biscuit

echo Done.
exit /b 0

:export
echo Exporting part %1 to stl\robbie_%2.stl
%OPENSCAD% %OPTS% -D part=%1 -o stl\robbie_%2.stl base.scad
if errorlevel 1 echo   FAILED: part %1 (%2)
exit /b 0
