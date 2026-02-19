-- إدراج معاملة تسديد للتحصيل القديم 40000
INSERT INTO "TechnicianTransactions" ("TechnicianId", "Type", "Category", "Amount", "BalanceAfter", "Description", "ReferenceNumber", "Notes", "CompanyId", "CreatedAt", "IsDeleted")
SELECT tc."TechnicianId", 1, 3, tc."Amount", 0, COALESCE(tc."Description", 'تحصيل نقدي'), COALESCE(tc."ReceiptNumber", 'COL-legacy'), tc."Notes", tc."CompanyId", tc."CollectionDate", false
FROM "TechnicianCollections" tc
WHERE tc."IsDeleted" = false
  AND NOT EXISTS (
    SELECT 1 FROM "TechnicianTransactions" tt
    WHERE tt."ReferenceNumber" = tc."ReceiptNumber" AND tt."IsDeleted" = false
  );

-- إعادة حساب الرصيد
UPDATE "Users" u SET
  "TechTotalPayments" = COALESCE(pay.total, 0),
  "TechNetBalance" = COALESCE(pay.total, 0) - u."TechTotalCharges"
FROM (
  SELECT "TechnicianId", SUM("Amount") as total
  FROM "TechnicianTransactions"
  WHERE "Type" = 1 AND "IsDeleted" = false
  GROUP BY "TechnicianId"
) pay
WHERE u."Id" = pay."TechnicianId";
