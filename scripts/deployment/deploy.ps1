# سكربت نشر API على الخادم VPS
$ErrorActionPreference = "Continue"

Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "       Sadara API Deployment           " -ForegroundColor Yellow
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""

# المسارات
$sourcePath = "C:\SadaraPlatform\publish\api"
$serverIP = "72.61.183.61"
$remotePath = "\\$serverIP\c$\inetpub\wwwroot\sadara-api"
$username = "administrator"
$password = "Admin@123!"

Write-Host "Source: $sourcePath" -ForegroundColor White
Write-Host "Server: $serverIP" -ForegroundColor White
Write-Host "Target: $remotePath" -ForegroundColor White
Write-Host ""

# Create credentials
$secPassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username, $secPassword)

# Connect to server
Write-Host "Connecting to server..." -ForegroundColor Yellow

try {
    # Create PSDrive for connection
    New-PSDrive -Name "VPSDrive" -PSProvider FileSystem -Root $remotePath -Credential $credential -ErrorAction Stop | Out-Null
    Write-Host "Connected successfully!" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "Copying files..." -ForegroundColor Yellow
    
    # Count files
    $files = Get-ChildItem -Path $sourcePath -Recurse -File
    $totalFiles = $files.Count
    Write-Host "Total files: $totalFiles" -ForegroundColor White
    
    # Copy files
    Copy-Item -Path "$sourcePath\*" -Destination "VPSDrive:\" -Recurse -Force -ErrorAction Continue
    
    Write-Host "Files copied successfully!" -ForegroundColor Green
    
    # Remove PSDrive
    Remove-PSDrive -Name "VPSDrive" -Force
    
    Write-Host ""
    Write-Host "Restarting IIS..." -ForegroundColor Yellow
    
    # Try to restart IIS via PsExec if exists
    if (Test-Path "C:\Windows\System32\psexec.exe") {
        $result = & psexec.exe \\$serverIP -u $username -p $password iisreset
        Write-Host $result
    } else {
        Write-Host "Warning: You need to restart IIS manually on the server" -ForegroundColor Yellow
        Write-Host "Execute: iisreset" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Green
    Write-Host "       Deployment Completed!          " -ForegroundColor Green
    Write-Host "=======================================" -ForegroundColor Green
    
} catch {
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Alternative Instructions:" -ForegroundColor Yellow
    Write-Host "1. Open File Explorer" -ForegroundColor White
    Write-Host "2. Type in address bar: \\72.61.183.61" -ForegroundColor White
    Write-Host "3. Enter username: administrator and password: Admin@123!" -ForegroundColor White
    Write-Host "4. Copy contents from: C:\SadaraPlatform\publish\api" -ForegroundColor White
    Write-Host "5. Paste to: C:\inetpub\wwwroot\sadara-api" -ForegroundColor White
    Write-Host "6. On the server execute: iisreset" -ForegroundColor White
}

Write-Host ""
Write-Host "Test API: http://72.61.183.61/api/superadmin/login" -ForegroundColor Cyan
Write-Host ""
