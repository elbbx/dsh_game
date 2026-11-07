@echo off
cd /d "%~dp0.."
python scripts\qa_cycle.py --root .
if errorlevel 1 (
    echo Validation failed. Review finished\reports.
    exit /b 1
)
echo Check complete. SKIP means NOT tested.
