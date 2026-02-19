-- Make CitizenId nullable in ServiceRequests
ALTER TABLE "ServiceRequests" ALTER COLUMN "CitizenId" DROP NOT NULL;

-- Drop the existing FK constraint that references Users
ALTER TABLE "ServiceRequests" DROP CONSTRAINT IF EXISTS "FK_ServiceRequests_Users_CitizenId";

-- Re-add it with ON DELETE SET NULL
ALTER TABLE "ServiceRequests" ADD CONSTRAINT "FK_ServiceRequests_Users_CitizenId" 
    FOREIGN KEY ("CitizenId") REFERENCES "Users"("Id") ON DELETE SET NULL;

-- Verify
SELECT column_name, is_nullable FROM information_schema.columns 
WHERE table_name = 'ServiceRequests' AND column_name = 'CitizenId';
