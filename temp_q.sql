SELECT "Id", "CustomerName", "SubscriptionId", "PlanName", "PlanPrice", "CollectionType", "ActivationDate", "SessionId" FROM "SubscriptionLogs" WHERE "IsDeleted" = false ORDER BY "Id";
