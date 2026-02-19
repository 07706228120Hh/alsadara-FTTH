SELECT "FullName", "TechTotalCharges", "TechTotalPayments", "TechNetBalance" FROM "Users" WHERE "TechTotalCharges" > 0 OR "TechTotalPayments" > 0 OR "TechNetBalance" != 0;
