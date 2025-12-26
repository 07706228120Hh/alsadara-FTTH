# سكريبت اختبار نظام Firebase Multi-Tenant
# الاستخدام: .\test_firebase_system.ps1

Write-Host ""
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "    اختبار نظام Firebase Multi-Tenant    " -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$projectPath = "d:\flutter\app\ramz1 top\old_project"
$passed = 0
$failed = 0
$total = 0

# دالة للاختبار
function Test-Item {
    param(
        [string]$Name,
        [scriptblock]$Test
    )
    
    $script:total++
    Write-Host "[$script:total] اختبار: $Name" -ForegroundColor Yellow -NoNewline
    
    try {
        $result = & $Test
        if ($result) {
            Write-Host " ✅" -ForegroundColor Green
            $script:passed++
            return $true
        } else {
            Write-Host " ❌" -ForegroundColor Red
            $script:failed++
            return $false
        }
    } catch {
        Write-Host " ❌ (خطأ: $_)" -ForegroundColor Red
        $script:failed++
        return $false
    }
}

Write-Host ""
Write-Host "فحص الملفات الأساسية..." -ForegroundColor Cyan
Write-Host ""

# اختبار 1: وجود pubspec.yaml
Test-Item "pubspec.yaml" {
    Test-Path "$projectPath\pubspec.yaml"
}

# اختبار 2: وجود حزمة crypto
Test-Item "crypto package في pubspec.yaml" {
    $content = Get-Content "$projectPath\pubspec.yaml" -Raw
    $content -match "crypto:"
}

# اختبار 3: خدمة المصادقة
Test-Item "firebase_auth_service.dart" {
    Test-Path "$projectPath\lib\services\firebase_auth_service.dart"
}

# اختبار 4: خدمة الشركات
Test-Item "organizations_service.dart" {
    Test-Path "$projectPath\lib\services\organizations_service.dart"
}

# اختبار 5: خدمة المهام
Test-Item "firestore_tasks_service.dart" {
    Test-Path "$projectPath\lib\services\firestore_tasks_service.dart"
}

# اختبار 6: خدمة الصلاحيات
Test-Item "firestore_permissions_service.dart" {
    Test-Path "$projectPath\lib\services\firestore_permissions_service.dart"
}

# اختبار 7: صفحة تسجيل الدخول
Test-Item "firebase_login_page_new.dart" {
    Test-Path "$projectPath\lib\pages\firebase_login_page_new.dart"
}

# اختبار 8: صفحة إدارة الشركات
Test-Item "organizations_management_page.dart" {
    Test-Path "$projectPath\lib\pages\admin\organizations_management_page.dart"
}

# اختبار 9: تحديث main.dart
Test-Item "استعادة الجلسة في main.dart" {
    $content = Get-Content "$projectPath\lib\main.dart" -Raw
    $content -match "FirebaseAuthService\.restoreSession"
}

# اختبار 10: تحديث صفحة تسجيل الدخول (username)
Test-Item "حقل username في صفحة تسجيل الدخول" {
    $content = Get-Content "$projectPath\lib\pages\firebase_login_page_new.dart" -Raw
    $content -match "_usernameController" -and $content -match "signInWithUsername"
}

Write-Host ""
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "    فحص الوثائق                         " -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# اختبار 11: دليل التحليل
Test-Item "FILTER_PAGE_AUTH_ANALYSIS.md" {
    Test-Path "$projectPath\FILTER_PAGE_AUTH_ANALYSIS.md"
}

# اختبار 12: دليل البدء السريع
Test-Item "QUICK_START_FIREBASE.md" {
    Test-Path "$projectPath\QUICK_START_FIREBASE.md"
}

Write-Host ""
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "    النتيجة النهائية                    " -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$percentage = [math]::Round(($passed / $total) * 100, 2)

Write-Host "إجمالي الاختبارات: $total" -ForegroundColor White
Write-Host "نجح: $passed" -ForegroundColor Green
Write-Host "فشل: $failed" -ForegroundColor Red
Write-Host "نسبة النجاح: $percentage%" -ForegroundColor $(if ($percentage -ge 80) { "Green" } elseif ($percentage -ge 50) { "Yellow" } else { "Red" })
Write-Host ""

if ($failed -eq 0) {
    Write-Host "رائع! جميع الاختبارات نجحت!" -ForegroundColor Green
    Write-Host ""
    Write-Host "الخطوات التالية:" -ForegroundColor Cyan
    Write-Host "1. تشغيل: .\create_superadmin.ps1" -ForegroundColor Yellow
    Write-Host "2. انشاء مستخدم Super Admin في Firebase Console" -ForegroundColor Yellow
    Write-Host "3. تشغيل التطبيق: flutter run -d windows" -ForegroundColor Yellow
    Write-Host "4. تسجيل الدخول باستخدام: superadmin / password" -ForegroundColor Yellow
    Write-Host ""
} elseif ($failed -le 2) {
    Write-Host "معظم الاختبارات نجحت، لكن هناك بعض المشاكل البسيطة" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "راجع الملفات التي فشلت وتأكد من وجودها" -ForegroundColor Yellow
    Write-Host ""
} else {
    Write-Host "هناك مشاكل كثيرة! راجع الملفات المفقودة" -ForegroundColor Red
    Write-Host ""
}

Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "    معلومات المشروع                     " -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

Write-Host "المسار: $projectPath" -ForegroundColor White
Write-Host "Firebase Project: ramz-alsadara2025" -ForegroundColor White
Write-Host "نظام المصادقة: Custom Firestore (username + password SHA-256)" -ForegroundColor White
Write-Host "Multi-Tenant: نعم (organizationId)" -ForegroundColor White
Write-Host ""

# فحص Flutteفحص Flutter..." -ForegroundColor Cyan
Write-Host ""

try {
    $flutterVersion = flutter --version 2>&1 | Select-String "Flutter" | Select-Object -First 1
    Write-Host "Flutter مثبت: $flutterVersion" -ForegroundColor Green
} catch {
    Write-Host "
    Write-Host "❌ Flutter غير مثبت أو غير موجود في PATH" -ForegroundColor Red
}

Write-Host ""
Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# عرض أوامر مفيدة
Write-Host "📝 أوامر مفيدة:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  # تشغيل التطبيق" -ForegroundColor Yellow
Write-Host "  cd '$projectPath'" -ForegroundColor White
Write-Host "  flutter pub get" -ForegroundColor White
Write-Host "  flutter run -d windows" -ForegroundColor White
Write-Host ""
Write-Host "  # تنظيف المشروع" -ForegroundColor Yellow
Write-Host "  flutter clean" -ForegroundColor White
Write-Host "  flutter pub get" -ForegroundColor White
Write-Host ""
Write-Host "  # فحص الأخطاء" -ForegroundColor Yellow
Write-Host "  flutter analyze" -ForegroundColor White
Write-Host ""

Write-Host ""
Write-Host "انتهى الاختبار!" -ForegroundColor Cyan
Write-Host ""
