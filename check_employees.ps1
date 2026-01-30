[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
$loginBody = '{"companyCode":"SADARA","username":"0770","password":"123456"}'
$loginResponse = Invoke-RestMethod -Uri "https://72.61.183.61/api/companies/login" -Method POST -Body $loginBody -ContentType "application/json"
$loginResponse | ConvertTo-Json -Depth 10
