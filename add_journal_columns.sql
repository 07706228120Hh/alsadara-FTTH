ALTER TABLE "TechnicianTransactions" ADD COLUMN IF NOT EXISTS "JournalEntryId" uuid NULL;
ALTER TABLE "AgentTransactions" ADD COLUMN IF NOT EXISTS "JournalEntryId" uuid NULL;
