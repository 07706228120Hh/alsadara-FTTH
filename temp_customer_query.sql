SELECT "CustomerId", "CustomerName", "OperationType", "PlanName", "PlanPrice", "ActivatedBy", "PartnerName", "PartnerId", "DeviceUsername", "ZoneName", "CreatedAt"
FROM "SubscriptionLogs"
WHERE "CustomerId" = '2902268'
ORDER BY "CreatedAt" DESC
LIMIT 20;
