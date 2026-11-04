param([switch]$BuildArtifacts, [switch]$BrowserStorage)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
function Check([scriptblock]$Action) {
  & $Action
  if ($LASTEXITCODE -ne 0) { throw "Release check failed (exit $LASTEXITCODE)." }
}
Check { flutter --suppress-analytics analyze }
Check { flutter --suppress-analytics test --concurrency=2 }
Check { npm.cmd --prefix backend test }
Check { npm.cmd --prefix backend run check }
if ($BrowserStorage) {
  Check { flutter --suppress-analytics build web --release --no-web-resources-cdn --target=test/support/browser_storage_probe.dart --output=.cache/browser-storage-probe }
  Check { node tools/browser_storage_smoke.cjs }
}
if ($BuildArtifacts) {
  Check { flutter --suppress-analytics build web --release --no-web-resources-cdn --dart-define-from-file=config/development.json }
  Check { flutter --suppress-analytics build appbundle --release --dart-define-from-file=config/development.json }
}
