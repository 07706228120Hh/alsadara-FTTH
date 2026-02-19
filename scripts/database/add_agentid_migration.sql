-- Migration: Add AgentId to ServiceRequests
-- Date: 2026-02-15

-- Add AgentId column
ALTER TABLE "ServiceRequests" ADD COLUMN IF NOT EXISTS "AgentId" uuid NULL;

-- Create index
CREATE INDEX IF NOT EXISTS "IX_ServiceRequests_AgentId" ON "ServiceRequests" ("AgentId");

-- Add FK constraint
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'FK_ServiceRequests_Agents_AgentId') THEN
    ALTER TABLE "ServiceRequests" ADD CONSTRAINT "FK_ServiceRequests_Agents_AgentId"
      FOREIGN KEY ("AgentId") REFERENCES "Agents"("Id") ON DELETE SET NULL;
  END IF;
END
$$;

-- Verify
SELECT column_name, data_type, is_nullable FROM information_schema.columns
  WHERE table_name = 'ServiceRequests' AND column_name = 'AgentId';
