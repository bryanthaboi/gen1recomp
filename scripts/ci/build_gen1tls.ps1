$ErrorActionPreference = 'Stop'
$out = "dist/native/win-x64"
New-Item -ItemType Directory -Force -Path $out | Out-Null
dotnet publish native/tls_dial/Gen1Tls.csproj `
  -c Release -r win-x64 -o $out
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed ($LASTEXITCODE)" }
if (-not (Test-Path "$out/gen1tls.dll")) {
  throw "gen1tls.dll missing after publish"
}
Get-Item "$out/gen1tls.dll" | Format-List Name, Length, LastWriteTime
