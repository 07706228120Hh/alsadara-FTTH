WITH running AS (
  SELECT t."Id",
    SUM(CASE WHEN t."Type" = 0 THEN t."Amount" ELSE 0 END) OVER (PARTITION BY t."AgentId" ORDER BY t."CreatedAt", t."Id") as charges,
    SUM(CASE WHEN t."Type" = 1 THEN t."Amount" ELSE 0 END) OVER (PARTITION BY t."AgentId" ORDER BY t."CreatedAt", t."Id") as payments
  FROM "AgentTransactions" t WHERE t."IsDeleted" = false
)
UPDATE "AgentTransactions" SET "BalanceAfter" = running.payments - running.charges
FROM running WHERE "AgentTransactions"."Id" = running."Id";

SELECT "Id","Type","Amount","BalanceAfter" FROM "AgentTransactions" WHERE "IsDeleted" = false ORDER BY "CreatedAt";
