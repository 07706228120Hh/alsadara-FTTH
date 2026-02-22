-- Check Users columns
SELECT column_name FROM information_schema.columns WHERE table_name='Users' AND column_name IN ('TechTotalCharges','TechTotalPayments','FtthPasswordEncrypted','FtthUsername','BankAccountNumber','BankName','ContractType','EmergencyContactName','EmergencyContactPhone','HireDate','HrNotes','RegisteredDeviceFingerprint') ORDER BY 1;
-- Check TechnicianTransactions columns
SELECT column_name FROM information_schema.columns WHERE table_name='TechnicianTransactions' AND column_name IN ('JournalEntryId','ReceivedBy') ORDER BY 1;
-- Check SubscriptionLogs columns
SELECT column_name FROM information_schema.columns WHERE table_name='SubscriptionLogs' AND column_name IN ('CollectionType','FtthTransactionId','IsReconciled','JournalEntryId','LinkedAgentId','LinkedTechnicianId','ReconciliationNotes','ServiceRequestId','PaidMonths','RenewalCycleMonths') ORDER BY 1;
-- Check AgentTransactions columns
SELECT column_name FROM information_schema.columns WHERE table_name='AgentTransactions' AND column_name='JournalEntryId';
-- Check WorkCenters columns
SELECT column_name FROM information_schema.columns WHERE table_name='WorkCenters' AND column_name='Description';
