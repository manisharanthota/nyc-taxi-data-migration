$out  = Join-Path $PSScriptRoot "..\data\raw"
$base = "https://d37ci6vzurychx.cloudfront.net/trip-data"
New-Item -ItemType Directory -Force -Path $out | Out-Null

$years = 2025..2026
$total = $years.Count * 12 * 2
$i = 0

foreach ($year in $years) {
  foreach ($month in 1..12) {
    foreach ($type in "yellow","green") {
      $i++
      $file = "{0}_tripdata_{1}-{2:D2}.parquet" -f $type, $year, $month
      $dest = Join-Path $out $file
      if (Test-Path $dest) { Write-Host "[$i/$total] skip $file"; continue }

      Write-Host "[$i/$total] $file"
      curl.exe -f -L --progress-bar -o $dest "$base/$file"
      if ($LASTEXITCODE -ne 0) {
        Remove-Item $dest -ErrorAction SilentlyContinue
        Write-Host "      n/a (not published yet)" -ForegroundColor Yellow
      }
    }
  }
}
Write-Host "Done." -ForegroundColor Green