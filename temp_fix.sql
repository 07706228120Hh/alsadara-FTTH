-- «ÌÃ«œ «·„” Œœ„Ì‰ Ê«·‘—ﬂ«  «·„ «Õ…
SELECT "Id", "FullName", "Username" FROM "Users" WHERE "IsDeleted" = false LIMIT 5;
SELECT "Id", "Name" FROM "Companies" WHERE "IsDeleted" = false LIMIT 5;
-- »Ì«‰«  «·”Ã·«  «·Õ«·Ì…
SELECT "Id", "ActivatedBy", "PartnerName", "UserId", "CompanyId", "CollectionType" FROM "SubscriptionLogs" WHERE "IsDeleted" = false;
