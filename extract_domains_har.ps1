#Load the HAR file
$har = Get-Content -Path "Path\to\har.har" -Raw | ConvertFrom-Json
#Extract domains from the file
$domains = $har.log.entries.request.url | ForEach-Object { [uri]$_ } | Select-Object -ExpandProperty Host | Sort-Object -Unique
#Output the domains
Write-Output $domains
