@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Apply patch/<component>/*.patch to managed_components/<component>

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "ROOT_DIR=%%~fI"
set "MANAGED_DIR=%ROOT_DIR%\managed_components"

if not exist "%MANAGED_DIR%" (
    echo [ERROR] managed_components not found: "%MANAGED_DIR%"
    exit /b 1
)

where git >nul 2>nul
if errorlevel 1 (
    echo [ERROR] git command not found in PATH.
    exit /b 1
)

set "FOUND_PATCH=0"
set "FAIL_COUNT=0"
set "APPLY_COUNT=0"
set "SKIP_COUNT=0"

for /R "%SCRIPT_DIR%" %%P in (*.patch) do (
    set "FOUND_PATCH=1"
    set "PATCH_FILE=%%~fP"
    set "PATCH_PARENT=%%~dpP"

    rem Get component folder name from patch parent dir
    for %%C in ("!PATCH_PARENT:~0,-1!") do set "COMPONENT=%%~nxC"
    if /I "!COMPONENT!"=="patch" (
        echo [WARN] Skip root-level patch file: "!PATCH_FILE!"
        set /a SKIP_COUNT+=1
        goto :continue_loop
    )

    set "TARGET_DIR=%MANAGED_DIR%\!COMPONENT!"
    if not exist "!TARGET_DIR!" (
        echo [WARN] Component dir not found, skip: "!COMPONENT!"
        set /a SKIP_COUNT+=1
        goto :continue_loop
    )

    echo [INFO] Applying "!PATCH_FILE!" to "!TARGET_DIR!"
    pushd "!TARGET_DIR!" >nul

    git apply --reverse --check "!PATCH_FILE!" >nul 2>nul
    if !errorlevel! EQU 0 (
        echo [INFO] Already applied: "!PATCH_FILE!"
        set /a SKIP_COUNT+=1
    ) else (
        git apply --check "!PATCH_FILE!" >nul 2>nul
        if !errorlevel! NEQ 0 (
            echo [ERROR] Cannot apply patch cleanly: "!PATCH_FILE!"
            set /a FAIL_COUNT+=1
        ) else (
            git apply "!PATCH_FILE!"
            if !errorlevel! NEQ 0 (
                echo [ERROR] Failed to apply patch: "!PATCH_FILE!"
                set /a FAIL_COUNT+=1
            ) else (
                echo [OK] Applied: "!PATCH_FILE!"
                set /a APPLY_COUNT+=1
            )
        )
    )

    popd >nul
    :continue_loop
)

if "%FOUND_PATCH%"=="0" (
    echo [INFO] No patch files found under "%SCRIPT_DIR%".
    exit /b 0
)

echo.
echo ===== Patch Summary =====
echo Applied: %APPLY_COUNT%
echo Skipped: %SKIP_COUNT%
echo Failed : %FAIL_COUNT%

if not "%FAIL_COUNT%"=="0" (
    exit /b 2
)

exit /b 0
