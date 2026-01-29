<#
.SYNOPSIS
Runs Sadara Platform without Docker (requires local installations).

.DESCRIPTION
This script helps you run the project without Docker by checking dependencies and running the API.

.PARAMETER Environment
Development or Production (default: Development)

.PARAMETER NoDatabase
Skip database setup (for quick testing)

.EXAMPLE
.\run-without-docker.ps1 -Environment Development -NoDatabase $true
#>

param(
    [ValidateSet("Development", "Production")]
    [string]$Environment = "Development",

    [bool]$NoDatabase = $false
)

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Sadara Platform - Run Without Docker" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# Check prerequisites
Write-Host "`nChecking prerequisites..." -ForegroundColor Yellow

$requiredTools = @(
    @{Name = "dotnet"; Check = { Get-Command "dotnet" -ErrorAction SilentlyContinue } },
    @{Name = "flutter"; Check = { Get-Command "flutter" -ErrorAction SilentlyContinue } }
)

if (-not $NoDatabase) {
    $requiredTools += @{Name = "psql"; Check = { Get-Command "psql" -ErrorAction SilentlyContinue } }
}

foreach ($tool in $requiredTools) {
    if (-not (& $tool.Check)) {
        Write-Host "❌ Error: $($tool.Name) is not installed or not in PATH" -ForegroundColor Red
        return
    }
}

# Load environment variables
Write-Host "`nLoading environment variables..." -ForegroundColor Cyan

if (-not (Test-Path ".\.env")) {
    Write-Host "Copying .env.example to .env..." -ForegroundColor Yellow
    Copy-Item ".env.example" ".env"
}

$envVars = Get-Content ".\.env" | Where-Object { $_ -match '=' -and -not $_ -match '^#' }

foreach ($var in $envVars) {
    $name, $value = $var -split '=', 2
    $name = $name.Trim()
    $value = $value.Trim().Trim('"').Trim("'")
    [Environment]::SetEnvironmentVariable($name, $value)
}

# Database setup if needed
if (-not $NoDatabase) {
    Write-Host "`nChecking PostgreSQL..." -ForegroundColor Cyan

    try {
        $dbHost = $env:POSTGRES_HOST
        $dbPort = $env:POSTGRES_PORT
        $dbName = $env:POSTGRES_DB
        $dbUser = $env:POSTGRES_USER
        $dbPassword = $env:POSTGRES_PASSWORD

        $env:PGPASSWORD = $dbPassword
        $testResult = & "psql" -h $dbHost -p $dbPort -U $dbUser -c "\l" -o $null 2>&1

        Write-Host "✓ PostgreSQL connection successful" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Error connecting to PostgreSQL:" -ForegroundColor Red
        Write-Host $_
        Write-Host "`nPlease make sure PostgreSQL is installed and running:" -ForegroundColor Yellow
        Write-Host "- Download from: https://www.postgresql.org/download/"
        Write-Host "- Default installation includes psql"
        Write-Host "- Start PostgreSQL service from Windows Services"
        return
    }
    finally {
        [Environment]::SetEnvironmentVariable("PGPASSWORD", "")
    }
}

# Run API
Write-Host "`nStarting API..." -ForegroundColor Cyan

$apiPath = "src\Backend\API\Sadara.API"
Set-Location $apiPath

if (-not (Test-Path "bin")) {
    Write-Host "Restoring NuGet packages..." -ForegroundColor Yellow
    dotnet restore
}

# Run in new window so script continues
Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "dotnet run --urls ""http://localhost:5000""", "-k"

Write-Host "API is starting on http://localhost:5000" -ForegroundColor Green

# Wait for API to start
Write-Host "`nWaiting for API to start..." -ForegroundColor Yellow

$maxWait = 60
$elapsed = 0

while ($elapsed -lt $maxWait) {
    try {
        $health = Invoke-RestMethod "http://localhost:5000/health" -ErrorAction SilentlyContinue
        if ($health -ne $null) {
            Write-Host "✓ API is healthy" -ForegroundColor Green
            break
        }
    }
    catch {}
    
    Start-Sleep -Seconds 2
    $elapsed += 2
    Write-Host "." -NoNewline
}

if ($elapsed -ge $maxWait) {
    Write-Host "`n⚠️  Warning: API health check failed" -ForegroundColor Yellow
}

# Run Flutter
Write-Host "`n`n============================================" -ForegroundColor Cyan
Write-Host "  Starting Flutter Desktop Application" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

Set-Location "src\Apps\CompanyDesktop\alsadara-ftth"

if (-not (Test-Path ".dart_tool")) {
    Write-Host "`nGetting Flutter dependencies..." -ForegroundColor Yellow
    flutter pub get
}

Write-Host "`nStarting Flutter app on Windows..." -ForegroundColor Green

Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "flutter run -d windows", "-k"

Write-Host "`n============================================" -ForegroundColor Green
Write-Host "  ✓ Sadara Platform is starting!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

Write-Host "`n📱 Flutter Desktop App: Will open in new window"
Write-Host "🌐 API: http://localhost:5000"
Write-Host "📊 Swagger UI: http://localhost:5000/swagger"
Write-Host "`n🔐 Default credentials (development):"
Write-Host "   Email: admin@sadara.com"
Write-Host "   Phone: +9647801234567"
Write-Host "   Password: Admin@123"

# Return to original directory
Set-Location $PSScriptRoot
