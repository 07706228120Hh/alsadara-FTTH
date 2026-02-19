-- إعادة حساب الرصيد من المعاملات الفعلية
UPDATE "Users" u SET
  "TechTotalPayments" = COALESCE(pay.total, 0),
  "TechNetBalance" = COALESCE(pay.total, 0) - u."TechTotalCharges"
FROM (
  SELECT "TechnicianId", SUM("Amount") as total
  FROM "TechnicianTransactions"
  WHERE "Type" = 1 AND "IsDeleted" = false
  GROUP BY "TechnicianId"
) pay
WHERE u."Id" = pay."TechnicianId" AND u."FullName" = 'علي علي';
