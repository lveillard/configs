$ErrorActionPreference = 'Stop'
$testConfig = Join-Path $PSScriptRoot 'test.lua'
$testOutput = (& wezterm --config-file $testConfig show-keys --lua 2>&1 | Out-String)
$testExit = $LASTEXITCODE
$testOutput -split "`r?`n" | Where-Object { $_ -match 'logging|Config checks' } | Write-Output
# show-keys can return success with default bindings after a Lua error.
if ($testExit -ne 0 -or -not $testOutput.Contains('Config checks passed:')) {
  throw 'WezTerm configuration checks failed; the success marker was not produced.'
}
