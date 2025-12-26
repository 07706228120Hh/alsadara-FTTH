@echo off
chcp 65001 >nul
cls

echo ============================================
echo   انشاء برنامج التثبيت - Alsadara v1.2.6
echo ============================================
echo.

cd /d "d:\flutter\app\ramz1 top\filter_page"

REM التحقق من وجود Inno Setup
if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
    goto BUILD_INSTALLER
)

echo Inno Setup غير مثبت
echo.
echo يرجى تحميل وتثبيت Inno Setup من الرابط:
echo https://jrsoftware.org/isdl.php
echo.
echo بعد التثبيت، شغل هذا الملف مرة اخرى
echo.
echo هل تريد فتح صفحة التحميل الآن؟ (Y/N)
choice /c YN /n /m ""

if %ERRORLEVEL% EQU 1 (
    start https://jrsoftware.org/isdl.php
    echo.
    echo تم فتح صفحة التحميل
    echo بعد التثبيت شغل هذا الملف مرة اخرى
)

echo.
pause
exit

:BUILD_INSTALLER
echo جاري بناء برنامج التثبيت...
echo.

"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" "alsadara_installer_v1.2.6.iss"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ============================================
    echo تم انشاء برنامج التثبيت بنجاح!
    echo ============================================
    echo.
    echo الملف: Distribution_v1.2.6\Installer\Alsadara_v1.2.6_Setup.exe
    echo.
    
    REM فتح المجلد
    if exist "Distribution_v1.2.6\Installer\Alsadara_v1.2.6_Setup.exe" (
        explorer /select,"Distribution_v1.2.6\Installer\Alsadara_v1.2.6_Setup.exe"
    ) else (
        echo تحذير: الملف غير موجود في المكان المتوقع
        explorer "Distribution_v1.2.6\Installer"
    )
) else (
    echo.
    echo فشل في انشاء برنامج التثبيت
    echo.
)

echo.
pause
