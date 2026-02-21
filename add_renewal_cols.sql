ALTER TABLE "SubscriptionLogs" ADD COLUMN IF NOT EXISTS "RenewalCycleMonths" integer;
ALTER TABLE "SubscriptionLogs" ADD COLUMN IF NOT EXISTS "PaidMonths" integer NOT NULL DEFAULT 0;
ALTER TABLE "SubscriptionLogs" ADD COLUMN IF NOT EXISTS "NextRenewalDate" timestamp with time zone;
