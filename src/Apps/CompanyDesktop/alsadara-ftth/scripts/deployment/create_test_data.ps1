# Create Test Data for Firebase Multi-Tenant System
# Super Admin + Test Company + Test User

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   Firebase Test Data Generator             " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# SHA-256 Hash Function
function Get-SHA256Hash {
    param([string]$text)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $hashBytes = $sha256.ComputeHash($bytes)
    $hash = [System.BitConverter]::ToString($hashBytes) -replace '-', ''
    return $hash.ToLower()
}

# ===== Super Admin =====
Write-Host "1. Super Admin (System Administrator)" -ForegroundColor Yellow
Write-Host "--------------------------------------" -ForegroundColor Gray

$superAdminUsername = "admin"
$superAdminPassword = "admin123"
$superAdminPasswordHash = Get-SHA256Hash -text $superAdminPassword

Write-Host "   Username: " -NoNewline -ForegroundColor White
Write-Host $superAdminUsername -ForegroundColor Green
Write-Host "   Password: " -NoNewline -ForegroundColor White
Write-Host $superAdminPassword -ForegroundColor Green
Write-Host ""

$superAdminJson = @"
{
  "username": "$superAdminUsername",
  "passwordHash": "$superAdminPasswordHash",
  "name": "مدير النظام",
  "email": "admin@alsadara.com",
  "phone": "966500000000",
  "createdAt": [اختر Timestamp - Server timestamp]
}
"@

# ===== شركة تجريبية =====
Write-Host "2️⃣ شركة تجريبية (Tenant)" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

$tenantCode = "DEMO001"
$tenantName = "شركة التجربة"

Write-Host "   كود الشركة: " -NoNewline -ForegroundColor White
Write-Host $tenantCode -ForegroundColor Green
Write-Host "   اسم الشركة: " -NoNewline -ForegroundColor White
Write-Host $tenantName -ForegroundColor Green
Write-Host ""

# حساب تاريخ الاشتراك (سنة من الآن)
$subscriptionStart = [DateTime]::Now
$subscriptionEnd = $subscriptionStart.AddYears(1)
$subscriptionStartFormatted = $subscriptionStart.ToString("yyyy-MM-dd")
$subscriptionEndFormatted = $subscriptionEnd.ToString("yyyy-MM-dd")

$tenantJson = @"
{
  "name": "$tenantName",
  "code": "$tenantCode",
  "email": "info@demo.com",
  "phone": "966511111111",
  "address": "الرياض، المملكة العربية السعودية",
  "logo": "",
  "isActive": true,
  "suspensionReason": null,
  "subscriptionStart": [اختر Timestamp - $subscriptionStartFormatted],
  "subscriptionEnd": [اختر Timestamp - $subscriptionEndFormatted],
  "subscriptionPlan": "yearly",
  "maxUsers": 50,
  "createdAt": [اختر Timestamp - Server timestamp],
  "createdBy": "super_admin_id"
}
"@

# ===== مستخدم تجريبي =====
Write-Host "3️⃣ مستخدم تجريبي (Tenant User)" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

$tenantUserUsername = "user1"
$tenantUserPassword = "user123"
$tenantUserPasswordHash = Get-SHA256Hash -text $tenantUserPassword

Write-Host "   اسم المستخدم: " -NoNewline -ForegroundColor White
Write-Host $tenantUserUsername -ForegroundColor Green
Write-Host "   كلمة المرور: " -NoNewline -ForegroundColor White
Write-Host $tenantUserPassword -ForegroundColor Green
Write-Host ""

$tenantUserJson = @"
{
  "username": "$tenantUserUsername",
  "passwordHash": "$tenantUserPasswordHash",
  "name": "محمد أحمد",
  "email": "user1@demo.com",
  "phone": "966522222222",
  "role": "admin",
  "isActive": true,
  "permissions": {
    "first_system": {
      "attendance": true,
      "agent": true,
      "tasks": true,
      "zones": true,
      "ai_search": true
    },
    "second_system": {
      "users": true,
      "subscriptions": true,
      "tasks": true,
      "zones": true,
      "accounts": true,
      "account_records": true,
      "export": true,
      "agents": true,
      "whatsapp": true,
      "wallet_balance": true,
      "expiring_soon": true,
      "quick_search": true,
      "technicians": true,
      "transactions": true,
      "notifications": true,
      "audit_logs": true,
      "whatsapp_link": true,
      "whatsapp_settings": true,
      "plans": true,
      "whatsapp_business": true,
      "whatsapp_bulk_sender": true,
      "whatsapp_conversations": true,
      "local_storage": true,
      "import_storage": true
    }
  },
  "createdAt": [اختر Timestamp - Server timestamp],
  "lastLogin": null
}
"@

# ===== عرض الملخص =====
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   📋 ملخص البيانات التجريبية              " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "🔑 Super Admin:" -ForegroundColor Magenta
Write-Host "   Username: $superAdminUsername | Password: $superAdminPassword" -ForegroundColor White
Write-Host ""

Write-Host "🏢 Tenant (شركة):" -ForegroundColor Magenta
Write-Host "   Code: $tenantCode | Name: $tenantName" -ForegroundColor White
Write-Host ""

Write-Host "👤 Tenant User (مستخدم الشركة):" -ForegroundColor Magenta
Write-Host "   Username: $tenantUserUsername | Password: $tenantUserPassword" -ForegroundColor White
Write-Host ""

# ===== تعليمات الإضافة =====
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   📝 خطوات الإضافة في Firebase             " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "الخطوة 1: إنشاء Super Admin" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "1. افتح Firebase Console" -ForegroundColor White
Write-Host "2. Firestore Database > Start Collection" -ForegroundColor White
Write-Host "3. Collection ID: " -NoNewline -ForegroundColor White
Write-Host "super_admins" -ForegroundColor Green
Write-Host "4. Document ID: " -NoNewline -ForegroundColor White
Write-Host "[Auto ID]" -ForegroundColor Green
Write-Host "5. انسخ JSON أدناه:" -ForegroundColor White
Write-Host ""
Write-Host $superAdminJson -ForegroundColor Cyan
Write-Host ""

Write-Host "الخطوة 2: إنشاء Tenant (شركة)" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "1. Firestore Database > Start Collection" -ForegroundColor White
Write-Host "2. Collection ID: " -NoNewline -ForegroundColor White
Write-Host "tenants" -ForegroundColor Green
Write-Host "3. Document ID: " -NoNewline -ForegroundColor White
Write-Host "[Auto ID أو احفظه لاستخدامه لاحقاً]" -ForegroundColor Green
Write-Host "4. انسخ JSON أدناه:" -ForegroundColor White
Write-Host ""
Write-Host $tenantJson -ForegroundColor Cyan
Write-Host ""

Write-Host "الخطوة 3: إنشاء Tenant User (مستخدم الشركة)" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "1. Firestore Database > tenants > [Document ID من الخطوة 2]" -ForegroundColor White
Write-Host "2. Start Subcollection" -ForegroundColor White
Write-Host "3. Collection ID: " -NoNewline -ForegroundColor White
Write-Host "users" -ForegroundColor Green
Write-Host "4. Document ID: " -NoNewline -ForegroundColor White
Write-Host "[Auto ID]" -ForegroundColor Green
Write-Host "5. انسخ JSON أدناه:" -ForegroundColor White
Write-Host ""
Write-Host $tenantUserJson -ForegroundColor Cyan
Write-Host ""

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   🧪 اختبار تسجيل الدخول                  " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "✅ بعد إضافة البيانات، يمكنك تسجيل الدخول:" -ForegroundColor Green
Write-Host ""
Write-Host "   🔹 كمدير نظام (Super Admin):" -ForegroundColor Yellow
Write-Host "      Username: $superAdminUsername" -ForegroundColor White
Write-Host "      Password: $superAdminPassword" -ForegroundColor White
Write-Host ""
Write-Host "   🔹 كمستخدم شركة (Tenant User):" -ForegroundColor Yellow
Write-Host "      Tenant Code: $tenantCode" -ForegroundColor White
Write-Host "      Username: $tenantUserUsername" -ForegroundColor White
Write-Host "      Password: $tenantUserPassword" -ForegroundColor White
Write-Host ""

# حفظ في ملفات
Write-Host "💾 حفظ البيانات في ملفات..." -ForegroundColor Yellow
$superAdminJson | Out-File -FilePath "1_superadmin_data.json" -Encoding UTF8
$tenantJson | Out-File -FilePath "2_tenant_data.json" -Encoding UTF8
$tenantUserJson | Out-File -FilePath "3_tenant_user_data.json" -Encoding UTF8
Write-Host "✅ تم حفظ البيانات في ملفات JSON" -ForegroundColor Green
Write-Host ""

Write-Host "🌐 فتح Firebase Console..." -ForegroundColor Yellow
Start-Process "https://console.firebase.google.com/project/ramz-alsadara2025/firestore"

Write-Host ""
Write-Host "✨ انتهى! استمتع باستخدام نظام Multi-Tenant ✨" -ForegroundColor Cyan
Write-Host ""
