SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'SubscriptionLogs' AND column_name IN ('UserId', 'CompanyId', 'IsDeleted');
