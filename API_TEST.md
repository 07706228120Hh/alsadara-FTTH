# اختبار API - Sadara Platform

## 1. Health Check
```powershell
Invoke-RestMethod -Uri "http://localhost:5000/health" -Method GET
```

## 2. تسجيل الدخول بحساب Admin
```powershell
$loginBody = @{
    phoneNumber = "9647700000001"
    password = "Admin@123!"
} | ConvertTo-Json

$loginResponse = Invoke-RestMethod -Uri "http://localhost:5000/api/auth/login" -Method POST -Body $loginBody -ContentType "application/json"
$token = $loginResponse.data.token
Write-Host "Token: $token"
```

## 3. الحصول على الصلاحيات
```powershell
$headers = @{ Authorization = "Bearer $token" }
Invoke-RestMethod -Uri "http://localhost:5000/api/permissions" -Method GET -Headers $headers
```

## 4. الحصول على الخدمات
```powershell
Invoke-RestMethod -Uri "http://localhost:5000/api/servicerequests/services" -Method GET
```

## 5. SuperAdmin Dashboard
```powershell
$headers = @{ Authorization = "Bearer $token" }
Invoke-RestMethod -Uri "http://localhost:5000/api/superadmin/dashboard" -Method GET -Headers $headers
```

## 6. إنشاء طلب خدمة
```powershell
$requestBody = @{
    serviceId = 1
    operationTypeId = 2
    citizenId = "CITIZEN_GUID_HERE"
    address = "بغداد - الكرادة"
    city = "Baghdad"
    area = "Karrada"
    contactPhone = "9647701234567"
    priority = 3
} | ConvertTo-Json

$headers = @{ Authorization = "Bearer $token" }
Invoke-RestMethod -Uri "http://localhost:5000/api/servicerequests" -Method POST -Body $requestBody -ContentType "application/json" -Headers $headers
```

## بيانات الدخول الأولية

### Super Admin
- **الهاتف:** 9647700000001
- **كلمة المرور:** Admin@123!

### Test Merchant
- **الهاتف:** +9647809876543
- **كلمة المرور:** Merchant@123
