param(
    [string]$Python = 'python',
    [string]$RuntimeRoot = ''
)
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
if (-not $RuntimeRoot) { $RuntimeRoot = Join-Path (Split-Path $RepoRoot -Parent) 'ARGONAUTICA_work\demo' }
$RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot)
[IO.Directory]::CreateDirectory($RuntimeRoot) | Out-Null
$env:TEMP = Join-Path $RuntimeRoot 'tmp'
$env:TMP = $env:TEMP
$env:PIP_CACHE_DIR = Join-Path $RuntimeRoot 'cache\pip'
$env:PYTHONDONTWRITEBYTECODE = '1'
[IO.Directory]::CreateDirectory($env:TEMP) | Out-Null
[IO.Directory]::CreateDirectory($env:PIP_CACHE_DIR) | Out-Null
$VenvRoot = Join-Path $RuntimeRoot '.venv'
$DemoPython = Join-Path $VenvRoot 'Scripts\python.exe'
if (-not (Test-Path -LiteralPath $DemoPython)) {
    & $Python -m venv $VenvRoot
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the demo Python environment.' }
}
& $DemoPython -m pip install -r (Join-Path $PSScriptRoot 'requirements-yolo-demo.txt')
if ($LASTEXITCODE -ne 0) { throw 'Demo dependency installation failed.' }
& $DemoPython -X utf8 -B -c 'import numpy, PIL, serial, tkinter; print(numpy.__version__, PIL.__version__, serial.__version__)'
if ($LASTEXITCODE -ne 0) { throw 'Demo dependencies are incomplete.' }
Write-Output 'DEMO_ENVIRONMENT_READY'
Write-Output "Python: $DemoPython"
Write-Output "Runtime and cache: $RuntimeRoot"
