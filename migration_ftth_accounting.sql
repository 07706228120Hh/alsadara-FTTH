-- Migration: FTTH Accounting Integration
-- Date: 2025-01-01

-- Users table: FTTH credentials
ALTER TABLE "Users" ADD COLUMN IF NOT EXISTS "FtthUsername" TEXT;
ALTER TABLE "Users" ADD COLUMN IF NOT EXISTS "FtthPasswordEncrypted" TEXT;

-- SubscriptionLogs table: Accounting integration fields
ALTER TABLE "SubscriptionLogs" ADD COLUMN IF NOT EXISTS "CollectionType" TEXT;
ALTER TABLE "SubscriptionLogs" ADD COLUMN IF NOT EXISTS "FtthTransactionId" TEXT;
ALTER TABLE "SubscriptionLogs" ADD COLUMN IF NOT EXISTS "ServiceRequestId" UUID;
ALTER TABLE "SubscriptionLogs" ADD COLUMN IF NOT EXISTS "LinkedAgentId" UUID;
ALTER TABLE "SubscriptionLogs" ADD COLUMN IF NOT EXISTS "JournalEntryId" UUID;
ALTER TABLE "SubscriptionLogs" ADD COLUMN IF NOT EXISTS "IsReconciled" BOOLEAN DEFAULT false;
ALTER TABLE "SubscriptionLogs" ADD COLUMN IF NOT EXISTS "ReconciliationNotes" TEXT;

SELECT 'FTTH Accounting Migration Applied Successfully' as result;
