-- Drop FK constraint and shadow column CitizenId1
ALTER TABLE "ServiceRequests" DROP CONSTRAINT IF EXISTS "FK_ServiceRequests_Citizens_CitizenId1";
ALTER TABLE "ServiceRequests" DROP COLUMN IF EXISTS "CitizenId1";
-- Verify
SELECT column_name FROM information_schema.columns WHERE table_name = 'ServiceRequests' AND column_name LIKE 'Citizen%';
