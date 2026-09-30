@echo off
REM run.bat -- تشغيل SAS Sidecar على 127.0.0.1:8100 (Windows)
REM
REM متطلّبات:
REM   1. Python 3.11+ في PATH
REM   2. pip install -r requirements.txt  (من مجلد service/)
REM   3. تعيين متغيّر البيئة SADARA_SAS_INTERNAL_SECRET قبل التشغيل:
REM         set SADARA_SAS_INTERNAL_SECRET=your-secret-here
REM
REM fail-closed: الخدمة ترفض كل الطلبات إن لم يُضبط SADARA_SAS_INTERNAL_SECRET.

setlocal

if "%SADARA_SAS_INTERNAL_SECRET%"=="" (
    echo [ERROR] SADARA_SAS_INTERNAL_SECRET is not set.
    echo         The sidecar will start but reject ALL requests ^(fail-closed^).
    echo         Set the variable before running in production.
)

cd /d "%~dp0"

python -m uvicorn app:app --host 127.0.0.1 --port 8100 --log-level info

endlocal
