-- ============================================================
-- Migration: تحسينات أمان نظام البصمة (6 تحسينات)
-- Date: 2026-03-25
-- ============================================================

-- 1. Device Approval — حقول موافقة المدير على الجهاز
ALTER TABLE "Users" ADD COLUMN IF NOT EXISTS "DeviceApprovalStatus" integer NOT NULL DEFAULT 0;
ALTER TABLE "Users" ADD COLUMN IF NOT EXISTS "PendingDeviceFingerprint" text;
ALTER TABLE "Users" ADD COLUMN IF NOT EXISTS "DeviceApprovedByUserId" uuid;
ALTER TABLE "Users" ADD COLUMN IF NOT EXISTS "DeviceApprovedAt" timestamp with time zone;

-- تحديث الموظفين الذين لديهم جهاز مسجل مسبقاً → Approved
UPDATE "Users" SET "DeviceApprovalStatus" = 2 WHERE "RegisteredDeviceFingerprint" IS NOT NULL;

-- 2. IP + VPN Detection
ALTER TABLE "AttendanceRecords" ADD COLUMN IF NOT EXISTS "IpAddress" text;
ALTER TABLE "AttendanceAuditLogs" ADD COLUMN IF NOT EXISTS "IsVpnSuspected" boolean NOT NULL DEFAULT false;

-- 3. Selfie Photos
ALTER TABLE "AttendanceRecords" ADD COLUMN IF NOT EXISTS "CheckInPhotoPath" text;
ALTER TABLE "AttendanceRecords" ADD COLUMN IF NOT EXISTS "CheckOutPhotoPath" text;

-- 4. إنشاء مجلد الصور (يتم يدوياً على السيرفر)
-- mkdir -p /var/www/sadara-api/attendance-photos
