@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem cleanup-demo-artifacts.cmd  (Windows CMD)
rem Usage:
rem   cleanup-demo-artifacts.cmd <folder>                (interactive)
rem   cleanup-demo-artifacts.cmd -n <folder>             (dry run)
rem   cleanup-demo-artifacts.cmd -y <folder>             (no prompt)
rem   cleanup-demo-artifacts.cmd --with-docker <folder>

set "DRY_RUN=0"
set "ASSUME_YES=0"
set "WITH_DOCKER=0"
set "TARGET_DIR=."

:parse_args
if "%~1"=="" goto after_args

if /I "%~1"=="-n"            set "DRY_RUN=1" & shift & goto parse_args
if /I "%~1"=="-y"            set "ASSUME_YES=1" & shift & goto parse_args
if /I "%~1"=="--with-docker" set "WITH_DOCKER=1" & shift & goto parse_args
echo("%~1" | findstr /b "-" >nul
if not errorlevel 1 (
  echo Usage: %~nx0 [-n] [-y] [--with-docker] [target-folder]
  exit /b 2
)
set "TARGET_DIR=%~1"
shift
goto parse_args
:after_args

if not exist "%TARGET_DIR%\pom.xml" (
  echo ^(x^) This doesn't look like the project root ^(missing pom.xml^).
  exit /b 1
)

set "TMPDIR=%TEMP%\cleanup_demo_artifacts"
if not exist "%TMPDIR%" mkdir "%TMPDIR%" >nul 2>nul
set "PATTERNS=%TMPDIR%\patterns.txt"
set "TOREMOVE=%TMPDIR%\to_remove.txt"
del /q "%TOREMOVE%" >nul 2>nul

rem ------------------------------------------------------------------
rem Patterns: "name,optional-path-fragment"
rem NOTE: CMD primarily matches by filename; fragments are advisory.
rem ------------------------------------------------------------------
set "PATTERNS=%TEMP%\patterns.txt"

> "%PATTERNS%" (
  echo DemoComponent.java,..\src\main\java\*\platformsample\*
  echo CustomContentModelIT.java,..\src\*\java\*\platformsample\*
  echo DemoComponentIT.java,..\src\*\java\*\platformsample\*
  echo HelloWorldWebScriptIT.java,..\src\*\java\*\platformsample\*

  echo Demo.java,..\src\main\java\*\platformsample\*
  echo DemoComponent.java,..\src\main\java\*\platformsample\*
  echo HelloWorldWebScript.java,..\src\main\java\*\platformsample\*

  echo helloworld.get.desc.xml,..\src\main\resources\alfresco\extension\templates\webscripts\alfresco\tutorials\*
  echo helloworld.get.html.ftl,..\src\main\resources\alfresco\extension\templates\webscripts\alfresco\tutorials\*
  echo helloworld.get.js,..\src\main\resources\alfresco\extension\templates\webscripts\alfresco\tutorials\*

  echo content-model.properties,..\src\main\resources\alfresco\module\*\messages\*
  echo workflow-messages.properties,..\src\main\resources\alfresco\module\*\messages\*
  echo content-model.xml,..\src\main\resources\alfresco\module\*\model\*
  echo workflow-model.xml,..\src\main\resources\alfresco\module\*\model\*
  echo bootstrap-context.xml,..\src\main\resources\alfresco\module\*\context\*
  echo service-context.xml,..\src\main\resources\alfresco\module\*\context\*
  echo webscript-context.xml,..\src\main\resources\alfresco\module\*\context\*
  echo sample-process.bpmn20.xml,..\src\main\resources\alfresco\module\*\workflow\*

  echo test.html,..\src\main\resources\META-INF\resources\*

  echo HelloWorldWebScriptControllerTest.java,..\src\test\java\*\platformsample\*

  echo *-share.properties,..\src\main\resources\alfresco\web-extension\messages\*
  echo *-example-widgets.xml,..\src\main\resources\alfresco\web-extension\site-data\extensions\*
  echo *-slingshot-application-context.xml,..\src\main\resources\alfresco\web-extension\*

  echo simple-page.get.desc.xml,..\src\main\resources\alfresco\web-extension\site-webscripts\com\example\pages\*
  echo simple-page.get.html.ftl,..\src\main\resources\alfresco\web-extension\site-webscripts\com\example\pages\*
  echo simple-page.get.js,..\src\main\resources\alfresco\web-extension\site-webscripts\com\example\pages\*
  echo README.md,..\src\main\resources\alfresco\web-extension\site-webscripts\org\alfresco\*

  echo TemplateWidget.css,..\src\main\resources\META-INF\resources\*\js\tutorials\widgets\css\*
  echo TemplateWidget.properties,..\src\main\resources\META-INF\resources\*\js\tutorials\widgets\i18n\*
  echo TemplateWidget.html,..\src\main\resources\META-INF\resources\*\js\tutorials\widgets\templates\*
  echo TemplateWidget.js,..\src\main\resources\META-INF\resources\*\js\tutorials\widgets\*
)

rem Build removal list (match by filename; filter later if you want)
for /f "usebackq tokens=1,2 delims=," %%A in ("%PATTERNS%") do (
  set "NAME=%%A"
  set "PATTERN=%%B"
  for /R "%TARGET_DIR%" %%F in (%%A) do (
    call :ADD_UNIQUE "%%~fF"
  )
  echo Processing file !NAME! in path !PATTERN!
)

 
rem Optional: add docker items and strip pom.xml modules
if "%WITH_DOCKER%"=="1" (
  if exist "%TARGET_DIR%\run.sh"    call :ADD_UNIQUE "%TARGET_DIR%\run.sh"
  if exist "%TARGET_DIR%\run.bat"   call :ADD_UNIQUE "%TARGET_DIR%\run.bat"
  if exist "%TARGET_DIR%\README.md" call :ADD_UNIQUE "%TARGET_DIR%\README.md"
  if exist "%TARGET_DIR%\docker" call :ADD_UNIQUE "%TARGET_DIR%\docker"
  rem search ONLY immediate subfolders under TARGET_DIR (no recursion)
  for /d %%D in ("%TARGET_DIR%\*-platform-docker") do (
    if exist "%%~fD" call :ADD_UNIQUE "%%~fD"
  )
  for /d %%D in ("%TARGET_DIR%\*-share-docker") do (
    if exist "%%~fD" call :ADD_UNIQUE "%%~fD"
  )
)


call :PRINT_LIST
if "%DRY_RUN%"=="1" (
  echo Dry-run mode: no changes made.
  goto AFTER_DELETE
)

if not "%ASSUME_YES%"=="1" (
  set /p CONFIRM=Proceed with deletion? [y/N] 
  if /I not "!CONFIRM!"=="y" (
    echo Aborted.
    exit /b 1
  )
)

rem Delete files/dirs
for /f "usebackq delims=" %%P in ("%TOREMOVE%") do (
  if exist "%%~fP\NUL" (
    rmdir /s /q "%%~fP" 2>nul
  ) else (
    del /f /q "%%~fP" 2>nul
  )
)

:AFTER_DELETE
echo Updating XML configs...

rem -- If requested, strip docker modules from pom.xml --
if "%WITH_DOCKER%"=="1" (
  call :STRIP_DOCKER_MODULES_IN_POM
)

rem -- Always remove the three context imports from every module-context.xml --
for /f "delims=" %%M in ('dir /b /s module-context.xml 2^>nul ^| findstr /i "\\src\\main\\resources\\alfresco\\module\\"') do (
  call :FILTER_FILE_LINES "%%~fM" "/context/bootstrap-context.xml" "/context/service-context.xml" "/context/webscript-context.xml"
  echo   cleaned: %%~fM
)

rem -- Ensure minimal share-config-custom.xml ONLY for Share modules --
for /f "delims=" %%R in ('dir /b /s /ad ^| findstr /i "\\src\\main\\resources$"') do (
  if exist "%%~fR\alfresco\web-extension" (
    set "TARGET=%%~fR\share-config-custom.xml"
    if exist "!TARGET!" (
      findstr /i "<alfresco-config" "!TARGET!" >nul 2>nul
      if not errorlevel 1 (
        echo   keep   : !TARGET! (already contains ^<alfresco-config^>)
      ) else (
        > "!TARGET!" echo ^<?xml version="1.0" encoding="UTF-8"?^>
        >>"!TARGET!" echo ^<alfresco-config/^>
        echo   wrote  : !TARGET!
      )
    ) else (
      > "!TARGET!" echo ^<?xml version="1.0" encoding="UTF-8"?^>
      >>"!TARGET!" echo ^<alfresco-config/^>
      echo   wrote  : !TARGET!
    )
  )
)

echo Cleaning up empty directories...
for /l %%I in (1,1,3) do (
  for /f "delims=" %%D in ('dir /b /s /ad 2^>nul ^| sort /R') do (
    rd "%%~fD" 2>nul
  )
)

echo ------------------------------------------------------------
echo Done.
exit /b 0

rem ====== helpers ===============================================

:ADD_UNIQUE
set "P=%~1"
if not exist "%TOREMOVE%" ( > "%TOREMOVE%" type nul )
findstr /x /c:"%P%" "%TOREMOVE%" >nul 2>nul
if errorlevel 1 (
  echo %P%>>"%TOREMOVE%"
)
exit /b

:PRINT_LIST
echo ------------------------------------------------------------
if not exist "%TOREMOVE%" (
  echo No matching demo/tutorial files found. Nothing to do.
  exit /b 0
)
for /f "usebackq tokens=2 delims=:" %%C in ('find /v /c "" ^< "%TOREMOVE%"') do set "COUNT=%%C"
echo The following will be REMOVED (%COUNT%):
for /f "usebackq delims=" %%L in ("%TOREMOVE%") do echo   %%L
echo ------------------------------------------------------------
exit /b

:STRIP_DOCKER_MODULES_IN_POM
if not exist "$TARGET_DIR\pom.xml" exit /b
set "POMTMP=%TMPDIR%\pom_filtered.tmp"
findstr /v /r /c:"<module>[ ]*docker[ ]*</module>" ^
              /c:"<module>[ ]*.*-platform-docker[ ]*</module>" ^
              /c:"<module>[ ]*.*-share-docker[ ]*</module>" ^
              /c:"<module>[ ]*.*-docker[ ]*</module>" ^
        "pom.xml" > "%POMTMP%" 2>nul
if exist "%POMTMP%" move /y "%POMTMP%" "pom.xml" >nul
exit /b

:FILTER_FILE_LINES
rem %1=file, %2..%=substrings to exclude (literal contains)
set "FILE=%~1"
set "TMP=%TMPDIR%\filter.tmp"
if not exist "%FILE%" exit /b
set "CMD=findstr /v /l"
:FF_LOOP
shift
if "%~1"=="" goto FF_GO
set "CMD=!CMD! /c:%~1"
goto FF_LOOP
:FF_GO
%CMD% "%FILE%" > "%TMP%" 2>nul
if exist "%TMP%" move /y "%TMP%" "%FILE%" >nul
exit /b