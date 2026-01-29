<#
.SYNOPSIS
إعداد VPS و Firebase للاستخدام مع منصة الصدارة

.DESCRIPTION
يقوم هذا السكربت بإعداد ملفات الحسابات والبيئة للعمل مع VPS و Firebase

.PARAMETER SkipFirebase
يتجاهل إعداد Firebase (إذا لم تكن في حاجة إليه الآن)

.PARAMETER SkipVPS
يتجاهل إعداد VPS (إذا لم تكن في حاجة إليه الآن)

.PARAMETER GenerateSecrets
يولد ملفات الأسرار فقط

.EXAMPLE
.\setup-vps-and-firebase.ps1
#>

param(
    [switch]$SkipFirebase,
    [switch]$SkipVPS,
    [switch]$GenerateSecrets
)

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  إعداد VPS و Firebase لمنصة الصدارة" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# دالة لتوليد رقم عشوائي
function Get-RandomString {
    param([int]$Length = 32)
    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+'
    $random = New-Object System.Random
    $result = -join (1..$Length | ForEach-Object { $chars[$random.Next($chars.Length)] })
    return $result
}

# دالة لتوليد UUID
function Get-NewGuid {
    return [Guid]::NewGuid().ToString()
}

# دالة لتثبيت OpenSSL إذا لم يكن مثبتاً
function Install-OpenSSL {
    Write-Host "تحقق من OpenSSL..." -ForegroundColor Yellow
    
    if (-not (Get-Command "openssl" -ErrorAction SilentlyContinue)) {
        Write-Host "تنزيل OpenSSL..." -ForegroundColor Yellow
        
        $opensslUrl = "https://slproweb.com/download/Win64OpenSSL_Light-3_2_0.exe"
        $tempPath = "$env:TEMP\openssl-installer.exe"
        
        try {
            Invoke-WebRequest -Uri $opensslUrl -OutFile $tempPath -UseBasicParsing
            Write-Host "التنزيل المكتمل، بدء التثبيت..." -ForegroundColor Green
            Start-Process -FilePath $tempPath -ArgumentList "/SILENT" -Wait
            Write-Host "تم تثبيت OpenSSL بنجاح" -ForegroundColor Green
        }
        catch {
            Write-Host "❌ خطأ في تنزيل OpenSSL: $_" -ForegroundColor Red
            return $false
        }
        
        # إضافة إلى PATH
        $opensslPath = "C:\Program Files\OpenSSL-Win64\bin"
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        
        if (-not $currentPath.Contains($opensslPath)) {
            [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$opensslPath", "Machine")
            $env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine")
            Write-Host "تم إضافة OpenSSL إلى PATH" -ForegroundColor Green
        }
    }
    
    return $true
}

# إنشاء ملفات Firebase
if (-not $SkipFirebase) {
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "  إعداد Firebase" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    
    $firebaseSecretsPath = "deployment/firebase/.secrets.json"
    
    if (Test-Path $firebaseSecretsPath) {
        Write-Host "ملف Firebase secrets موجود بالفعل، يتم تخطيه..." -ForegroundColor Yellow
    }
    else {
        Write-Host "إنشاء ملف Firebase secrets..." -ForegroundColor Yellow
        
        $firebaseTemplate = Get-Content "deployment/firebase/.secrets.example.json" -Raw
        $firebaseConfig = $firebaseTemplate -replace 'your-firebase-project-id', "sadara-platform-$(Get-NewGuid)"
        $firebaseConfig = $firebaseConfig -replace 'YOUR_PROJECT_NUMBER', "$(Get-Random -Minimum 1000000000 -Maximum 9999999999)"
        $firebaseConfig = $firebaseConfig -replace 'YOUR_WEB_API_KEY', "AIzaSy$(Get-RandomString -Length 30)"
        $firebaseConfig = $firebaseConfig -replace 'YOUR_PRIVATE_KEY_ID', (Get-NewGuid).Replace("-", "")
        $firebaseConfig = $firebaseConfig -replace 'YOUR_PRIVATE_KEY_HERE', (Get-RandomString -Length 120)
        $firebaseConfig = $firebaseConfig -replace 'firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com', "firebase-adminsdk-$(Get-RandomString -Length 8)@sadara-platform.iam.gserviceaccount.com"
        $firebaseConfig = $firebaseConfig -replace 'YOUR_CLIENT_ID', "$(Get-Random -Minimum 100000000000 -Maximum 999999999999)"
        $firebaseConfig = $firebaseConfig -replace 'YOUR_SENDER_ID', "$(Get-Random -Minimum 1000000000 -Maximum 9999999999)"
        $firebaseConfig = $firebaseConfig -replace 'YOUR_APP_ID', "1:$(Get-Random -Minimum 1000000000 -Maximum 9999999999):web:$(Get-RandomString -Length 16)"
        $firebaseConfig = $firebaseConfig -replace 'YOUR_MEASUREMENT_ID', "G-$(Get-RandomString -Length 8)"
        
        Set-Content -Path $firebaseSecretsPath -Value $firebaseConfig -Encoding utf8
        Write-Host "✅ تم إنشاء $firebaseSecretsPath" -ForegroundColor Green
    }
    
    # نسخ ملف Firebase إلى API secrets
    $apiSecretsPath = "src/Backend/API/Sadara.API/secrets/firebase-service-account.json"
    
    if (-not (Test-Path $apiSecretsPath)) {
        Write-Host "إنشاء firebase-service-account.json..." -ForegroundColor Yellow
        
        $firebaseConfig = Get-Content $firebaseSecretsPath | ConvertFrom-Json
        $serviceAccount = $firebaseConfig.serviceAccount
        
        $serviceAccountJson = @{
            type                  = $serviceAccount.type
            project_id            = $serviceAccount.project_id
            private_key_id        = $serviceAccount.private_key_id
            private_key           = $serviceAccount.private_key
            client_email          = $serviceAccount.client_email
            client_id             = $serviceAccount.client_id
            auth_uri              = $serviceAccount.auth_uri
            token_uri             = $serviceAccount.token_uri
            auth_provider_x509_cert_url = "https://www.googleapis.com/oauth2/v1/certs"
            client_x509_cert_url  = "https://www.googleapis.com/robot/v1/metadata/x509/$($serviceAccount.client_email)"
        } | ConvertTo-Json -Depth 5
        
        New-Item -ItemType Directory -Path (Split-Path $apiSecretsPath) -Force | Out-Null
        Set-Content -Path $apiSecretsPath -Value $serviceAccountJson -Encoding utf8
        Write-Host "✅ تم إنشاء $apiSecretsPath" -ForegroundColor Green
    }
}

# إنشاء ملفات VPS
if (-not $SkipVPS) {
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "  إعداد VPS" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    
    $vpsSecretsPath = "deployment/vps/.secrets.json"
    
    if (Test-Path $vpsSecretsPath) {
        Write-Host "ملف VPS secrets موجود بالفعل، يتم تخطيه..." -ForegroundColor Yellow
    }
    else {
        Write-Host "إنشاء ملف VPS secrets..." -ForegroundColor Yellow
        
        $vpsTemplate = Get-Content "deployment/vps/.secrets.example.json" -Raw
        $vpsConfig = $vpsTemplate -replace 'YOUR_SERVER_IP', "72.61.183.61"
        $vpsConfig = $vpsConfig -replace 'YOUR_SSH_PASSWORD', (Get-RandomString -Length 16)
        $vpsConfig = $vpsConfig -replace 'YOUR_DB_PASSWORD', (Get-RandomString -Length 16)
        $vpsConfig = $vpsConfig -replace 'YOUR_JWT_SECRET_AT_LEAST_64_CHARACTERS_LONG', (Get-RandomString -Length 64)
        $vpsConfig = $vpsConfig -replace 'YOUR_ADMIN_PHONE', "+9647701234567"
        $vpsConfig = $vpsConfig -replace 'YOUR_ADMIN_PASSWORD', (Get-RandomString -Length 16)
        $vpsConfig = $vpsConfig -replace 'admin@yourdomain.com', "admin@alsadara.com"
        $vpsConfig = $vpsConfig -replace 'your@email.com', "admin@alsadara.com"
        
        Set-Content -Path $vpsSecretsPath -Value $vpsConfig -Encoding utf8
        Write-Host "✅ تم إنشاء $vpsSecretsPath" -ForegroundColor Green
    }
}

# إنشاء Service Account لـ Google Sheets
$sheetsServiceAccountPath = "src/Apps/CompanyDesktop/alsadara-ftth/assets/service_account.json"

if (-not (Test-Path $sheetsServiceAccountPath)) {
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "  إنشاء Google Sheets Service Account" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    
    Write-Host "إنشاء ملف service_account.json..." -ForegroundColor Yellow
    
    $serviceAccountJson = @{
        type                  = "service_account"
        project_id            = "sadara-sheets"
        private_key_id        = (Get-NewGuid).Replace("-", "")
        private_key           = "-----BEGIN PRIVATE KEY-----\n$(Get-RandomString -Length 120)\n-----END PRIVATE KEY-----\n"
        client_email          = "sheets@sadara-sheets.iam.gserviceaccount.com"
        client_id             = "$(Get-Random -Minimum 100000000000 -Maximum 999999999999)"
        auth_uri              = "https://accounts.google.com/o/oauth2/auth"
        token_uri             = "https://oauth2.googleapis.com/token"
        auth_provider_x509_cert_url = "https://www.googleapis.com/oauth2/v1/certs"
        client_x509_cert_url  = "https://www.googleapis.com/robot/v1/metadata/x509/sheets@sadara-sheets.iam.gserviceaccount.com"
    } | ConvertTo-Json -Depth 5
    
    Set-Content -Path $sheetsServiceAccountPath -Value $serviceAccountJson -Encoding utf8
    Write-Host "✅ تم إنشاء $sheetsServiceAccountPath" -ForegroundColor Green
}

# إنشاء config.json للـ Flutter
$configPath = "src/Apps/CompanyDesktop/alsadara-ftth/assets/config.json"

if (-not (Test-Path $configPath)) {
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "  إنشاء ملف config.json" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    
    Write-Host "إنشاء ملف config.json..." -ForegroundColor Yellow
    
    $configJson = @{
        apiUrl         = "http://localhost:5000"
        sheetId        = "YOUR_GOOGLE_SHEET_ID"
        maxUploadSize  = 5
    } | ConvertTo-Json
    
    Set-Content -Path $configPath -Value $configJson -Encoding utf8
    Write-Host "✅ تم إنشاء $configPath" -ForegroundColor Green
}

# إنشاء ملف .env
if (-not (Test-Path ".env")) {
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "  إنشاء ملف .env" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    
    Write-Host "إنشاء ملف .env..." -ForegroundColor Yellow
    
    $envContent = @"
# Database Configuration
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=SadaraDB
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$(Get-RandomString -Length 16)

# JWT Configuration
JWT_SECRET_KEY=$(Get-RandomString -Length 32)
JWT_EXPIRY_DAYS=7
JWT_ISSUER=SadaraPlatform
JWT_AUDIENCE=SadaraUsers

# Firebase Configuration
FIREBASE_PROJECT_ID=sadara-platform
FIREBASE_API_KEY=AIzaSy$(Get-RandomString -Length 30)
FIREBASE_AUTH_DOMAIN=sadara-platform.firebaseapp.com
FIREBASE_DATABASE_URL=https://sadara-platform.firebaseio.com
FIREBASE_STORAGE_BUCKET=sadara-platform.appspot.com
FIREBASE_MESSAGING_SENDER_ID=$(Get-Random -Minimum 1000000000 -Maximum 9999999999)
FIREBASE_APP_ID=1:$(Get-Random -Minimum 1000000000 -Maximum 9999999999):web:$(Get-RandomString -Length 16)

# VPS Configuration
VPS_HOST=72.61.183.61
VPS_PORT=22
VPS_USER=root
VPS_PASSWORD=$(Get-RandomString -Length 16)

# API Configuration
API_URL=http://localhost:5000
API_KEY=$(Get-RandomString -Length 32)
"@
    
    Set-Content -Path ".env" -Value $envContent -Encoding utf8
    Write-Host "✅ تم إنشاء .env" -ForegroundColor Green
}

# التأكد من وجود مجلدات الملفات
$requiredDirectories = @(
    "src/Backend/API/Sadara.API/secrets",
    "deployment/firebase",
    "deployment/vps",
    "src/Apps/CompanyDesktop/alsadara-ftth/assets"
)

foreach ($dir in $requiredDirectories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "✅ تم إنشاء مجلد: $dir" -ForegroundColor Green
    }
}

Write-Host "`n============================================" -ForegroundColor Green
Write-Host "  ✅ اكتملت عملية الإعداد بنجاح!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

Write-Host "`n📋 ملاحظات مهمة:" -ForegroundColor Yellow
Write-Host "- ملفات الأسرار تم إنشاؤها ولكنها تحتاج إلى تكوين حقيقي"
Write-Host "- Firebase: احصل على معلومات حقيقية من https://console.firebase.google.com/"
Write-Host "- VPS: تحديث بيانات الاتصال في deployment/vps/.secrets.json"
Write-Host "- Google Sheets: احصل على ملف service_account.json من https://console.cloud.google.com/"

Write-Host "`n📝 الخطوات التالية:" -ForegroundColor Cyan
Write-Host "1. قم بتحديث ملفات الأسرار الحقيقية"
Write-Host "2. تشغيل setup-database.ps1 لإنشاء قاعدة البيانات"
Write-Host "3. تشغيل run-without-docker.ps1 لبدء المشروع"
