SELECT COUNT(*) as total, COUNT("UserId") as with_user, COUNT("CompanyId") as with_company, COUNT("CollectionType") as with_collection FROM "SubscriptionLogs" WHERE "IsDeleted" = false;
SELECT "UserId", "CompanyId", "CollectionType", "ActivatedBy", "ActivationDate" FROM "SubscriptionLogs" WHERE "IsDeleted" = false ORDER BY "ActivationDate" DESC LIMIT 5;
