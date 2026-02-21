#!/bin/bash
export PGPASSWORD=sadara_secure_password_2024
psql -h localhost -U sadara_user -d sadara_db -c "UPDATE \"Accounts\" SET \"Name\" = 'صندوق الشركة الرئيسي', \"UpdatedAt\" = NOW() WHERE \"Code\" = '11104' AND \"IsDeleted\" = false"
psql -h localhost -U sadara_user -d sadara_db -t -A -c "SELECT \"Code\", \"Name\" FROM \"Accounts\" WHERE \"Code\" LIKE '1110%' AND \"IsDeleted\" = false ORDER BY \"Code\""
