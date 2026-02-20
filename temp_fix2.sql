UPDATE "SubscriptionLogs" 
SET "UserId" = '83bc3385-f50a-4143-8bc7-1952069b809e', 
    "CompanyId" = '3ebc4eb3-3511-487d-94d4-1812376491eb'
WHERE "IsDeleted" = false AND "UserId" IS NULL;
