# ============================================================
# Build Complete Script for Alsadara v1.2.8
# ============================================================

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$startTime = Get-Date
$version = "1.2.8"

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "    Build Complete - Alsadara v$version" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[0/9] Checking environment..." -ForegroundColor Magenta
Write-Host ""

$flutterCheck = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCheck) {
    Write-Host "ERROR: Flutter not found" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host "  OK: Flutter found" -ForegroundColor Green

$innoPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
$innoAvailable = Test-Path $innoPath
if ($innoAvailable) {
    Write-Host "  OK: Inno Setup found" -ForegroundColor Green
} else {
    Write-Host "  Warning: Inno Setup not found" -ForegroundColor Yellow
}

$projectPath = "d:\flutter\app\ramz1 top\filter_page"
if (-not (Test-Path $projectPath)) {
    Write-Host "ERROR: Project path not found" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Set-Location $projectPath
Write-Host "  OK: Project path correct" -ForegroundColor Green
Write-Host ""

Write-Host "[1/9] Stopping old instances..." -ForegroundColor Yellow
$alsadaraProcess = Get-Process -Name "alsadara" -ErrorAction SilentlyContinue
if ($alsadaraProcess) {
    Stop-Process -Name "alsadara" -Force -ErrorAction SilentlyContinue
    Write-Host "  OK: Stopped old instance" -ForegroundColor Green
    Start-Sleep -Seconds 2
} else {
    Write-Host "  Info: No running instance" -ForegroundColor Gray
}
Write-Host ""

Write-Host "[2/9] Cleaning project..." -ForegroundColor Yellow
try {
    flutter clean
    if ($LASTEXITCODE -ne 0) { throw "Clean failed" }
    Write-Host "  OK: Project cleaned" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host ""

Write-Host "[3/9] Getting dependencies..." -ForegroundColor Yellow
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "Pub get failed" }
    Write-Host "  OK: Dependencies downloaded" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host ""

Write-Host "[4/9] Building application (Windows Release)..." -ForegroundColor Yellow
Write-Host "  This may take a few minutes..." -ForegroundColor Gray
try {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "Build failed" }
    Write-Host "  OK: Application built" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host ""

Write-Host "[5/9] Creating distribution folders..." -ForegroundColor Yellow
try {
    if (Test-Path "Distribution_v$version") {
        Write-Host "  Removing old folder..." -ForegroundColor Gray
        Remove-Item "Distribution_v$version" -Recurse -Force
    }
    New-Item -Path "Distribution_v$version\Portable" -ItemType Directory -Force | Out-Null
    New-Item -Path "Distribution_v$version\Installer" -ItemType Directory -Force | Out-Null
    Write-Host "  OK: Folders created" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host ""

Write-Host "[6/9] Copying portable files..." -ForegroundColor Yellow
try {
    $sourcePath = "build\windows\x64\runner\Release\*"
    $destPath = "Distribution_v$version\Portable\"
    
    if (-not (Test-Path "build\windows\x64\runner\Release")) {
        throw "Build folder not found"
    }
    
    Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
    
    if (-not (Test-Path "Distribution_v$version\Portable\alsadara.exe")) {
        throw "Executable not found after copy"
    }
    
    Write-Host "  OK: Files copied" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}
Write-Host ""

Write-Host "[7/9] Creating installer..." -ForegroundColor Yellow

if ($innoAvailable) {
    try {
        Write-Host "  Running Inno Setup Compiler..." -ForegroundColor Gray
        $issFile = "alsadara_installer_v$version.iss"
        
        if (-not (Test-Path $issFile)) {
            throw "Inno Setup script not found: $issFile"
        }
        
        & $innoPath $issFile
        
        if ($LASTEXITCODE -eq 0) {
            if (Test-Path "Distribution_v$version\Installer\Alsadara_v${version}_Setup.exe") {
                Write-Host "  OK: Installer created" -ForegroundColor Green
            } else {
                throw "Installer not found after build"
            }
        } else {
            throw "Inno Setup failed with exit code: $LASTEXITCODE"
        }
    } catch {
        Write-Host "  Warning: $_" -ForegroundColor Yellow
        Write-Host "  Continuing with portable version only" -ForegroundColor Gray
    }
} else {
    Write-Host "  Inno Setup not installed - skipping installer creation" -ForegroundColor Yellow
    Write-Host "  Download from: https://jrsoftware.org/isdl.php" -ForegroundColor Gray
}
Write-Host ""

Write-Host "[8/9] Creating archive..." -ForegroundColor Yellow
try {
    $zipFile = "Alsadara_v${version}_Complete.zip"
    if (Test-Path $zipFile) {
        Remove-Item $zipFile -Force
    }
    
    Compress-Archive -Path "Distribution_v$version" -DestinationPath $zipFile -Force
    
    if (Test-Path $zipFile) {
        $zipSize = [math]::Round((Get-Item $zipFile).Length / 1MB, 2)
        Write-Host "  OK: Archive created (Size: $zipSize MB)" -ForegroundColor Green
    } else {
        throw "Archive creation failed"
    }
} catch {
    Write-Host "  Warning: $_" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "[9/9] Verifying results..." -ForegroundColor Yellow
Write-Host ""

$allSuccess = $true

$endTime = Get-Date
$duration = $endTime - $startTime
$minutes = [math]::Floor($duration.TotalMinutes)
$seconds = $duration.Seconds

Write-Host "================================================================" -ForegroundColor Green
Write-Host "              Build Complete!" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

Write-Host "Results:" -ForegroundColor Cyan
Write-Host ""

if (Test-Path "Distribution_v$version\Portable\alsadara.exe") {
    $portableSize = [math]::Round((Get-ChildItem "Distribution_v$version\Portable" -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    Write-Host "  OK Portable Version:" -ForegroundColor Green
    Write-Host "     Path: Distribution_v$version\Portable\" -ForegroundColor White
    Write-Host "     Size: $portableSize MB" -ForegroundColor White
} else {
    Write-Host "  ERROR: Portable version not found" -ForegroundColor Red
    $allSuccess = $false
}

Write-Host ""

if (Test-Path "Distribution_v$version\Installer\Alsadara_v${version}_Setup.exe") {
    $setupSize = [math]::Round((Get-Item "Distribution_v$version\Installer\Alsadara_v${version}_Setup.exe").Length / 1MB, 2)
    Write-Host "  OK Setup Installer:" -ForegroundColor Green
    Write-Host "     Path: Distribution_v$version\Installer\Alsadara_v${version}_Setup.exe" -ForegroundColor White
    Write-Host "     Size: $setupSize MB" -ForegroundColor White
} else {
    Write-Host "  Warning: Setup installer not found" -ForegroundColor Yellow
    Write-Host "     Info: Can be created later after installing Inno Setup" -ForegroundColor Gray
}

Write-Host ""

if (Test-Path "Alsadara_v${version}_Complete.zip") {
    $zipSize = [math]::Round((Get-Item "Alsadara_v${version}_Complete.zip").Length / 1MB, 2)
    Write-Host "  OK Compressed Archive:" -ForegroundColor Green
    Write-Host "     Path: Alsadara_v${version}_Complete.zip" -ForegroundColor White
    Write-Host "     Size: $zipSize MB" -ForegroundColor White
} else {
    Write-Host "  Warning: Compressed archive not found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Time taken: $minutes minutes and $seconds seconds" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

if ($allSuccess -or (Test-Path "Distribution_v$version\Portable\alsadara.exe")) {
    Write-Host "Application is ready for distribution!" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  [1] Open distribution folder" -ForegroundColor White
    Write-Host "  [2] Run application to test" -ForegroundColor White
    Write-Host "  [3] Exit" -ForegroundColor White
    Write-Host ""
    
    $choice = Read-Host "Choose (1-3)"
    
    switch ($choice) {
        "1" {
            if (Test-Path "Distribution_v$version") {
                explorer "Distribution_v$version"
                Write-Host "OK: Distribution folder opened" -ForegroundColor Green
            }
        }
        "2" {
            if (Test-Path "Distribution_v$version\Portable\alsadara.exe") {
                Write-Host "Starting application..." -ForegroundColor Cyan
                Start-Process "Distribution_v$version\Portable\alsadara.exe"
                Write-Host "OK: Application started" -ForegroundColor Green
            } else {
                Write-Host "ERROR: Application not found" -ForegroundColor Red
            }
        }
        "3" {
            Write-Host "Goodbye!" -ForegroundColor Cyan
        }
        default {
            Write-Host "OK: Done" -ForegroundColor Green
        }
    }
} else {
    Write-Host "Some errors occurred during build" -ForegroundColor Yellow
    Write-Host "Please review the messages above" -ForegroundColor Gray
    Read-Host "Press Enter to exit"
}

Write-Host ""
