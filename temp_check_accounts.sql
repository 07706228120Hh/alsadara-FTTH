SELECT a."Code", a."Name", a."CurrentBalance", a."AccountType", p."Code" as parent_code 
FROM "Accounts" a 
LEFT JOIN "Accounts" p ON a."ParentAccountId" = p."Id" 
WHERE a."IsActive" = true AND a."IsDeleted" = false 
ORDER BY a."Code";
