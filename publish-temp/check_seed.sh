#!/bin/bash
PGPASSWORD=sadara_secure_password_2024 psql -h localhost -U sadara_user -d sadara_db -c "SELECT \"Id\", \"NameAr\" FROM \"OperationTypes\" WHERE \"Id\" >= 9 ORDER BY \"Id\";"
PGPASSWORD=sadara_secure_password_2024 psql -h localhost -U sadara_user -d sadara_db -c "SELECT \"Id\", \"NameAr\" FROM \"Services\" WHERE \"Id\" >= 10;"
