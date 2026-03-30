Write-Host "=== CMD 1: src subfolders ==="
Get-ChildItem 'C:\SadaraPlatform\src' -Directory | ForEach-Object {
    $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    [PSCustomObject]@{Name=$_.Name; SizeGB=[math]::Round($size/1GB, 2)}
} | Sort-Object SizeGB -Descending | Format-Table -AutoSize

Write-Host ""
Write-Host "=== CMD 2: root folders ==="
Get-ChildItem 'C:\SadaraPlatform' -Directory | ForEach-Object {
    $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    [PSCustomObject]@{Name=$_.Name; SizeGB=[math]::Round($size/1GB, 2)}
} | Sort-Object SizeGB -Descending | Format-Table -AutoSize

Write-Host ""
Write-Host "=== CMD 3: top 30 largest files ==="
Get-ChildItem 'C:\SadaraPlatform\src' -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -gt 10MB } |
    Select-Object @{N='SizeMB';E={[math]::Round($_.Length/1MB,1)}}, FullName |
    Sort-Object SizeMB -Descending |
    Select-Object -First 30 |
    Format-Table -AutoSize

Write-Host ""
Write-Host "=== CMD 4: build/cache folders ==="
@('build','node_modules','.dart_tool','packages','.pub-cache') | ForEach-Object {
    $pattern = $_
    Get-ChildItem 'C:\SadaraPlatform\src' -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq $pattern } | ForEach-Object {
            $size = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
            [PSCustomObject]@{Folder=$_.FullName.Replace('C:\SadaraPlatform\',''); SizeMB=[math]::Round($size/1MB,0)}
        }
} | Sort-Object SizeMB -Descending | Format-Table -AutoSize
