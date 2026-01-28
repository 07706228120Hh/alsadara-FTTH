# Firebase Test Data Generator
# Creates demo accounts for testing

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

# Super Admin Credentials
$superAdminUsername = "admin"
$superAdminPassword = "admin123"
$superAdminPasswordHash = Get-SHA256Hash -text $superAdminPassword

# Test Tenant Credentials
$tenantCode = "DEMO001"
$tenantName = "Demo Company"

# Test User Credentials
$tenantUserUsername = "user1"
$tenantUserPassword = "user123"
$tenantUserPasswordHash = Get-SHA256Hash -text $tenantUserPassword

# Display Summary
Write-Host "CREDENTIALS SUMMARY:" -ForegroundColor Yellow
Write-Host ""
Write-Host "Super Admin Login:" -ForegroundColor Magenta
Write-Host "  Username: $superAdminUsername" -ForegroundColor White
Write-Host "  Password: $superAdminPassword" -ForegroundColor Green
Write-Host ""
Write-Host "Tenant Login:" -ForegroundColor Magenta
Write-Host "  Tenant Code: $tenantCode" -ForegroundColor White
Write-Host "  Username: $tenantUserUsername" -ForegroundColor White
Write-Host "  Password: $tenantUserPassword" -ForegroundColor Green
Write-Host ""

# Super Admin JSON
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Step 1: Create Super Admin" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Collection: super_admins" -ForegroundColor Green
Write-Host ""

$superAdminData = @{
    username = $superAdminUsername
    passwordHash = $superAdminPasswordHash
    name = "System Administrator"
    email = "admin@alsadara.com"
    phone = "966500000000"
} | ConvertTo-Json -Depth 10

Write-Host $superAdminData -ForegroundColor White
Write-Host ""
Write-Host "Note: Add 'createdAt' field as Timestamp (Server timestamp)" -ForegroundColor Yellow
Write-Host ""

# Tenant JSON
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Step 2: Create Tenant (Company)" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Collection: tenants" -ForegroundColor Green
Write-Host ""

$tenantData = @{
    name = $tenantName
    code = $tenantCode
    email = "info@demo.com"
    phone = "966511111111"
    address = "Riyadh, Saudi Arabia"
    logo = ""
    isActive = $true
    suspensionReason = $null
    subscriptionPlan = "yearly"
    maxUsers = 50
} | ConvertTo-Json -Depth 10

Write-Host $tenantData -ForegroundColor White
Write-Host ""
Write-Host "Note: Add these Timestamp fields:" -ForegroundColor Yellow
Write-Host "  - subscriptionStart: Timestamp (Now)" -ForegroundColor Yellow
Write-Host "  - subscriptionEnd: Timestamp (1 year from now)" -ForegroundColor Yellow
Write-Host "  - createdAt: Timestamp (Server timestamp)" -ForegroundColor Yellow
Write-Host "  - createdBy: String (super admin ID)" -ForegroundColor Yellow
Write-Host ""

# Tenant User JSON
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Step 3: Create Tenant User" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Subcollection: tenants/{tenant_id}/users" -ForegroundColor Green
Write-Host ""

$permissions = @{
    first_system = @{
        attendance = $true
        agent = $true
        tasks = $true
        zones = $true
        ai_search = $true
    }
    second_system = @{
        users = $true
        subscriptions = $true
        tasks = $true
        zones = $true
        accounts = $true
        account_records = $true
        export = $true
        agents = $true
        whatsapp = $true
        wallet_balance = $true
        expiring_soon = $true
        quick_search = $true
        technicians = $true
        transactions = $true
        notifications = $true
        audit_logs = $true
        whatsapp_link = $true
        whatsapp_settings = $true
        plans = $true
        whatsapp_business = $true
        whatsapp_bulk_sender = $true
        whatsapp_conversations = $true
        local_storage = $true
        import_storage = $true
    }
}

$tenantUserData = @{
    username = $tenantUserUsername
    passwordHash = $tenantUserPasswordHash
    name = "Mohammed Ahmed"
    email = "user1@demo.com"
    phone = "966522222222"
    role = "admin"
    isActive = $true
    permissions = $permissions
    lastLogin = $null
} | ConvertTo-Json -Depth 10

Write-Host $tenantUserData -ForegroundColor White
Write-Host ""
Write-Host "Note: Add 'createdAt' field as Timestamp (Server timestamp)" -ForegroundColor Yellow
Write-Host ""

# Save to files
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Saving to files..." -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Cyan

$superAdminData | Out-File -FilePath "firebase_data_1_superadmin.json" -Encoding UTF8
$tenantData | Out-File -FilePath "firebase_data_2_tenant.json" -Encoding UTF8
$tenantUserData | Out-File -FilePath "firebase_data_3_user.json" -Encoding UTF8

Write-Host "Files created:" -ForegroundColor Green
Write-Host "  - firebase_data_1_superadmin.json" -ForegroundColor White
Write-Host "  - firebase_data_2_tenant.json" -ForegroundColor White
Write-Host "  - firebase_data_3_user.json" -ForegroundColor White
Write-Host ""

# Open Firebase Console
Write-Host "Opening Firebase Console..." -ForegroundColor Yellow
Start-Process "https://console.firebase.google.com/project/ramz-alsadara2025/firestore"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "TEST CREDENTIALS:" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Super Admin:" -ForegroundColor Magenta
Write-Host "  Username: $superAdminUsername | Password: $superAdminPassword" -ForegroundColor White
Write-Host ""
Write-Host "Tenant User:" -ForegroundColor Magenta
Write-Host "  Code: $tenantCode | Username: $tenantUserUsername | Password: $tenantUserPassword" -ForegroundColor White
Write-Host ""
Write-Host "Done! Add the data to Firebase Firestore." -ForegroundColor Green
