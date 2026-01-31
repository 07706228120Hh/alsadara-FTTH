# Deploy API using PSRemoting
$serverIP = "72.61.183.61"
$username = "administrator"
$password = "Admin@123!"
$sourcePath = "C:\SadaraPlatform\publish\api"
$targetPath = "C:\inetpub\wwwroot\sadara-api"

Write-Host "=== Sadara API Deployment via PSRemoting ===" -ForegroundColor Cyan
Write-Host "Server: $serverIP" -ForegroundColor Yellow
Write-Host "Source: $sourcePath" -ForegroundColor Yellow
Write-Host "Target: $targetPath" -ForegroundColor Yellow
Write-Host ""

# Create credential
$secPassword = ConvertTo-SecureString $password -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential($username, $secPassword)

try {
    Write-Host "Testing PSRemoting connection..." -ForegroundColor Yellow
    
    # Test if PSRemoting is available
    $session = New-PSSession -ComputerName $serverIP -Credential $credential -ErrorAction Stop
    
    Write-Host "✓ Connected successfully!" -ForegroundColor Green
    Write-Host ""
    
    # Create target directory if not exists
    Write-Host "Preparing target directory..." -ForegroundColor Yellow
    Invoke-Command -Session $session -ScriptBlock {
        param($path)
        if (-not (Test-Path $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Host "Created directory: $path"
        } else {
            Write-Host "Directory exists: $path"
        }
    } -ArgumentList $targetPath
    
    # Stop IIS to release file locks
    Write-Host "Stopping IIS..." -ForegroundColor Yellow
    Invoke-Command -Session $session -ScriptBlock {
        iisreset /stop | Out-Null
        Write-Host "IIS stopped"
    }
    
    Start-Sleep -Seconds 2
    
    # Copy files
    Write-Host "Copying files..." -ForegroundColor Yellow
    $files = Get-ChildItem -Path $sourcePath -Recurse -File
    $totalFiles = $files.Count
    $current = 0
    
    foreach ($file in $files) {
        $current++
        $relativePath = $file.FullName.Substring($sourcePath.Length + 1)
        $targetFile = Join-Path $targetPath $relativePath
        $targetDir = Split-Path $targetFile -Parent
        
        # Create directory on remote
        Invoke-Command -Session $session -ScriptBlock {
            param($dir)
            if (-not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        } -ArgumentList $targetDir
        
        # Copy file content
        $content = [System.IO.File]::ReadAllBytes($file.FullName)
        Invoke-Command -Session $session -ScriptBlock {
            param($path, $bytes)
            [System.IO.File]::WriteAllBytes($path, $bytes)
        } -ArgumentList $targetFile, $content
        
        if ($current % 10 -eq 0 -or $current -eq $totalFiles) {
            Write-Host "  Copied $current/$totalFiles files..." -ForegroundColor Gray
        }
    }
    
    Write-Host "✓ Files copied successfully!" -ForegroundColor Green
    Write-Host ""
    
    # Start IIS
    Write-Host "Starting IIS..." -ForegroundColor Yellow
    Invoke-Command -Session $session -ScriptBlock {
        iisreset /start | Out-Null
        Write-Host "IIS started"
    }
    
    Write-Host ""
    Write-Host "=== Deployment Completed Successfully ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "API URL: http://$serverIP/api" -ForegroundColor Cyan
    Write-Host ""
    
    # Close session
    Remove-PSSession -Session $session
    
} catch {
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    
    if ($_.Exception.Message -like "*WinRM*" -or $_.Exception.Message -like "*PSRemoting*") {
        Write-Host "PSRemoting is not enabled on the server." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "To enable PSRemoting on the server, run:" -ForegroundColor Cyan
        Write-Host "  Enable-PSRemoting -Force" -ForegroundColor White
        Write-Host ""
    }
    
    Write-Host "Alternative: Manual Deployment" -ForegroundColor Yellow
    Write-Host "1. Connect via Remote Desktop to: $serverIP" -ForegroundColor White
    Write-Host "2. Copy from local: $sourcePath" -ForegroundColor White
    Write-Host "3. Paste to server: $targetPath" -ForegroundColor White
    Write-Host "4. Run on server: iisreset" -ForegroundColor White
    Write-Host ""
    
    if ($session) {
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    }
}

Write-Host "Press any key to continue..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
