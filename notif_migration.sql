ALTER TABLE "Notifications" ADD COLUMN IF NOT EXISTS "CompanyId" uuid NULL;
ALTER TABLE "Notifications" ADD COLUMN IF NOT EXISTS "ReferenceId" uuid NULL;
ALTER TABLE "Notifications" ADD COLUMN IF NOT EXISTS "ReferenceType" text NULL;
