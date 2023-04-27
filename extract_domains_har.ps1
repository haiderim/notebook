#This script will extract domains from HTTP Archive that has been exported from any web browser

#Load the HAR file
$har = Get-Content -Path "Path\to\har.har" -Raw | ConvertFrom-Json
#Extract domains from the file
$domains = $har.log.entries.request.url | ForEach-Object { [uri]$_ } | Select-Object -ExpandProperty Host | Sort-Object -Unique
#Output the domains
Write-Output $domains
