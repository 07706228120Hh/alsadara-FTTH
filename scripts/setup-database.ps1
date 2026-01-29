<#
.SYNOPSIS
Sets up the Sadara Platform database and environment.

.DESCRIPTION
This script:
1. Creates the PostgreSQL database
2. Runs the EF Core migrations
3. Seeds the initial data
4. Tests the connection

.PARAMETER Environment
Development (default) or Production

.PARAMETER Clean
Drop existing database and reinitialize

.EXAMPLE
.\setup-database.ps1 -Environment Development -Clean $true
#>

param(
    [ValidateSet("Development", "Production")]
    [string]$Environment = "Development",

    [bool]$Clean = $false
)

# Load environment variables
Write-Host "Loading environment variables from .env..." -ForegroundColor Cyan

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

# Extract connection string
$dbHost = $env:POSTGRES_HOST
$dbPort = $env:POSTGRES_PORT
$dbName = $env:POSTGRES_DB
$dbUser = $env:POSTGRES_USER
$dbPassword = $env:POSTGRES_PASSWORD

# Verify PostgreSQL is running
Write-Host "`nChecking PostgreSQL connection to $dbHost`:$dbPort..." -ForegroundColor Cyan

try {
    $pgResult = & "C:\Program Files\PostgreSQL\*\bin\psql.exe" -h $dbHost -p $dbPort -U $dbUser -c "\l" -o $null 2>&1
    Write-Host "✓ PostgreSQL connection successful" -ForegroundColor Green
}
catch {
    Write-Host "❌ Failed to connect to PostgreSQL: $_" -ForegroundColor Red
    Write-Host "`nPlease ensure:"
    Write-Host "- PostgreSQL service is running"
    Write-Host "- Password in .env is correct"
    Write-Host "- TCP/IP connections are enabled"
    return
}

# Change directory to API project
$apiPath = "src\Backend\API\Sadara.API"
Write-Host "`nChanging to API directory: $apiPath" -ForegroundColor Cyan
Set-Location $apiPath

# Restore NuGet packages
if (-not (Test-Path "bin")) {
    Write-Host "`nRestoring NuGet packages..." -ForegroundColor Cyan
    dotnet restore
}

# Check for existing database
$dbExists = $true
try {
    $checkResult = dotnet ef dbcontext info --context SadaraDbContext -v 2>&1
}
catch {
    $dbExists = $false
}

if ($Clean -or -not $dbExists) {
    Write-Host "`nCreating database from scratch..." -ForegroundColor Cyan
    dotnet ef database drop -f -c SadaraDbContext
    dotnet ef database update -c SadaraDbContext
}
else {
    Write-Host "`nApplying migrations..." -ForegroundColor Cyan
    dotnet ef database update -c SadaraDbContext
}

# Test the API connection
Write-Host "`nTesting API connection..." -ForegroundColor Cyan

try {
    $apiUrl = if ($Environment -eq "Development") { $env:API_BASE_URL } else { $env:API_BASE_URL_PROD }
    
    $healthResponse = Invoke-RestMethod "$apiUrl/health" -ErrorAction Stop
    if ($healthResponse -like '*healthy*') {
        Write-Host "✓ API is running and healthy" -ForegroundColor Green
    }
    else {
        Write-Host "⚠️  API response: $healthResponse" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "❌ Failed to connect to API: $_" -ForegroundColor Red
    Write-Host "`nStarting API locally for testing..." -ForegroundColor Cyan
    
    $apiJob = Start-Job -ScriptBlock {
        param($path)
        Set-Location $path
        dotnet run --urls "http://localhost:5000"
    } -ArgumentList $PWD.Path

    Start-Sleep -Seconds 5
    
    try {
        $healthResponse = Invoke-RestMethod "http://localhost:5000/health" -ErrorAction Stop
        Write-Host "✓ API started successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to start API: $_" -ForegroundColor Red
        Remove-Job $apiJob -Force
        return
    }
    
    Remove-Job $apiJob -Force
}

# Seed test data if in development
if ($Environment -eq "Development") {
    Write-Host "`nSeeding test data..." -ForegroundColor Cyan
    
    try {
        $seedResponse = Invoke-RestMethod "http://localhost:5000/api/seed-test-data" -ErrorAction Stop
        Write-Host "✓ Test data seeded successfully" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️  Could not seed test data: $_" -ForegroundColor Yellow
    }
}

Write-Host "`n✅ Database setup completed!" -ForegroundColor Green
Write-Host "`n🔐 Super Admin login:"
Write-Host "   Email: admin@sadara.com"
Write-Host "   Phone: +9647801234567"
Write-Host "   Password: Admin@123"
Write-Host "`n⚠️  Please change the default password in production!" -ForegroundColor Yellow
