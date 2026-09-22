[CmdletBinding()]
param(
    [ValidateSet("Release", "RelWithDebInfo")]
    [string]$Configuration = "Release",
    [string]$WindowsSdkVersion = "10.0",
    [switch]$SkipAngle,
    [switch]$SkipPackage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$portRoot = Join-Path $repoRoot "ports\uwp"
$thirdPartyRoot = Join-Path $portRoot "third_party"
$manifestPath = Join-Path $thirdPartyRoot "manifest.json"
$metadata = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json

$sdlRoot = Join-Path $thirdPartyRoot "sdl2"
$sdlSource = Join-Path $sdlRoot "source"
$sdlInstall = Join-Path $portRoot "build\sdl2-install"
$loveRoot = Join-Path $thirdPartyRoot "love"
$loveSource = Join-Path $loveRoot "source"
$loveBuild = Join-Path $portRoot "build\love"
$luajitSource = Join-Path $thirdPartyRoot "luajit\source"
$angleRoot = Join-Path $thirdPartyRoot "angle"
$angleSource = Join-Path $angleRoot "source"
$depotToolsSource = Join-Path $angleRoot "depot_tools"
$runtimeRoot = Join-Path $thirdPartyRoot "runtime"
$vcpkgSource = Join-Path $runtimeRoot "source"
$vcpkgInstalled = Join-Path $vcpkgSource "installed\x64-uwp"
$licensesRoot = Join-Path $thirdPartyRoot "licenses"

function Invoke-Tool {
    param([string]$FilePath)

    & $FilePath @args
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE."
    }
}

function Assert-Command {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required tool not found on PATH: $Name"
    }
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Ensure-GitSource {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Revision,
        [Parameter(Mandatory)][string]$Path,
        [switch]$AllowTrackedChanges
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Host "Cloning $Name at $Revision..."
        Ensure-Directory (Split-Path -Parent $Path)
        Invoke-Tool git init $Path
        Invoke-Tool git -C $Path remote add origin $Repository
        Invoke-Tool git -C $Path fetch --depth 1 origin $Revision
        Invoke-Tool git -C $Path checkout --detach FETCH_HEAD
    }

    $gitDirectory = Join-Path $Path ".git"
    if (-not (Test-Path -LiteralPath $gitDirectory -PathType Container)) {
        throw "$Name source has no Git metadata. Remove '$Path' to recreate the pinned checkout."
    }

    $actual = (& git -C $Path rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect the $Name source checkout."
    }
    if ($actual -ne $Revision) {
        throw "$Name source is at $actual; expected $Revision. Remove '$Path' to recreate it."
    }
    if (-not $AllowTrackedChanges) {
        Assert-GitSourceClean -Name $Name -Path $Path
    }
}

function Assert-GitSourceClean {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Path
    )

    & git -C $Path diff --quiet --ignore-submodules --
    $worktreeDirty = $LASTEXITCODE -ne 0
    & git -C $Path diff --cached --quiet --ignore-submodules --
    $indexDirty = $LASTEXITCODE -ne 0
    if ($worktreeDirty -or $indexDirty) {
        throw "$Name source has local changes. Remove '$Path' to recreate the pinned checkout."
    }
}

function Copy-RequiredFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Expected build output not found: $Source"
    }
    Ensure-Directory (Split-Path -Parent $Destination)
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Reset-Directory {
    param([Parameter(Mandatory)][string]$Path)

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Ensure-DepotToolsGit {
    $wrapper = Join-Path $depotToolsSource "git.bat"
    if (Test-Path -LiteralPath $wrapper -PathType Leaf) {
        return
    }

    $gitExe = (Get-Command git).Source
    $content = "@echo off`r`n`"$gitExe`" %*`r`n"
    [System.IO.File]::WriteAllText($wrapper, $content, [System.Text.ASCIIEncoding]::new())
}

function Get-Sha256 {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$NormalizeLineEndings
    )

    if ($NormalizeLineEndings) {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes).Replace("`r`n", "`n")
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($text)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            return [System.BitConverter]::ToString($sha256.ComputeHash($bytes)).Replace("-", "")
        } finally {
            $sha256.Dispose()
        }
    }

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hash = $sha256.ComputeHash($stream)
            return [System.BitConverter]::ToString($hash).Replace("-", "")
        } finally {
            $sha256.Dispose()
        }
    } finally {
        $stream.Dispose()
    }
}

function Update-Manifest {
    $roots = @(
        "angle\bin",
        "love\bin",
        "love\lib",
        "runtime\bin",
        "sdl2\bin",
        "sdl2\include",
        "sdl2\lib"
    )
    $files = foreach ($relativeRoot in $roots) {
        $path = Join-Path $thirdPartyRoot $relativeRoot
        Get-ChildItem -LiteralPath $path -File -Recurse | ForEach-Object {
            $relative = $_.FullName.Substring($thirdPartyRoot.Length + 1).Replace("\", "/")
            $normalize = $relative.StartsWith("sdl2/include/", [System.StringComparison]::Ordinal)
            [ordered]@{
                path = $relative
                sha256 = Get-Sha256 -Path $_.FullName -NormalizeLineEndings:$normalize
            }
        }
    }

    $metadata.configuration = $Configuration
    $metadata.files = @($files | Sort-Object { $_['path'] })
    $json = $metadata | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($manifestPath, "$json`r`n", [System.Text.UTF8Encoding]::new($false))
}

Assert-Command git
Assert-Command cmake

Ensure-GitSource `
    -Name "SDL2" `
    -Repository $metadata.sources.sdl2.repository `
    -Revision $metadata.sources.sdl2.commit `
    -Path $sdlSource `
    -AllowTrackedChanges

$sdlPatch = Join-Path $thirdPartyRoot $metadata.sources.sdl2.patch
Push-Location $sdlSource
try {
    & git apply --unidiff-zero --reverse --check $sdlPatch 2>$null
    if ($LASTEXITCODE -eq 0) {
        Invoke-Tool git apply --unidiff-zero --reverse $sdlPatch
        try {
            Assert-GitSourceClean -Name "SDL2" -Path $sdlSource
        } finally {
            Invoke-Tool git apply --unidiff-zero $sdlPatch
        }
    } else {
        Assert-GitSourceClean -Name "SDL2" -Path $sdlSource
        Invoke-Tool git apply --unidiff-zero --check $sdlPatch
        Invoke-Tool git apply --unidiff-zero $sdlPatch
    }
} finally {
    Pop-Location
}

Write-Host "Building SDL2..."
& (Join-Path $PSScriptRoot "build_sdl2_angle.ps1") `
    -Configuration $Configuration `
    -WindowsSdkVersion $WindowsSdkVersion
if ($LASTEXITCODE -ne 0) {
    throw "SDL2 build failed with exit code $LASTEXITCODE."
}

Ensure-GitSource `
    -Name "vcpkg" `
    -Repository $metadata.sources.vcpkg.repository `
    -Revision $metadata.sources.vcpkg.commit `
    -Path $vcpkgSource

$vcpkgExe = Join-Path $vcpkgSource "vcpkg.exe"
if (-not (Test-Path -LiteralPath $vcpkgExe -PathType Leaf)) {
    Write-Host "Bootstrapping vcpkg..."
    Invoke-Tool (Join-Path $vcpkgSource "bootstrap-vcpkg.bat") -disableMetrics
}

Write-Host "Installing the LÖVE runtime dependencies..."
$vcpkgPackages = @($metadata.sources.vcpkg.packages | ForEach-Object { "${_}:x64-uwp" })
Invoke-Tool $vcpkgExe install @vcpkgPackages --recurse --clean-after-build --vcpkg-root $vcpkgSource

Ensure-GitSource `
    -Name "LÖVE" `
    -Repository $metadata.sources.love.repository `
    -Revision $metadata.sources.love.commit `
    -Path $loveSource `
    -AllowTrackedChanges

$lovePatch = Join-Path $thirdPartyRoot $metadata.sources.love.patch
Push-Location $loveSource
try {
    & git apply --unidiff-zero --reverse --check $lovePatch 2>$null
    if ($LASTEXITCODE -eq 0) {
        Invoke-Tool git apply --unidiff-zero --reverse $lovePatch
        try {
            Assert-GitSourceClean -Name "LÖVE" -Path $loveSource
        } finally {
            Invoke-Tool git apply --unidiff-zero $lovePatch
        }
    } else {
        Assert-GitSourceClean -Name "LÖVE" -Path $loveSource
        Invoke-Tool git apply --unidiff-zero --check $lovePatch
        Invoke-Tool git apply --unidiff-zero $lovePatch
    }
} finally {
    Pop-Location
}

Ensure-GitSource `
    -Name "LuaJIT" `
    -Repository $metadata.sources.luajit.repository `
    -Revision $metadata.sources.luajit.commit `
    -Path $luajitSource

Write-Host "Building LÖVE..."
Invoke-Tool cmake --fresh -S $loveSource -B $loveBuild `
    -G "Visual Studio 17 2022" -A x64 `
    -DCMAKE_SYSTEM_NAME=WindowsStore `
    "-DCMAKE_SYSTEM_VERSION=$WindowsSdkVersion" `
    "-DCMAKE_TOOLCHAIN_FILE=$(Join-Path $vcpkgSource 'scripts\buildsystems\vcpkg.cmake')" `
    -DVCPKG_TARGET_TRIPLET=x64-uwp `
    "-DLOVE_UWP_SDL_ROOT=$sdlInstall" `
    -DLOVE_UWP_LUAJIT=ON `
    -DLOVE_UWP_ANGLE=ON `
    "-DFETCHCONTENT_SOURCE_DIR_LOVE_LUAJIT_SOURCE=$luajitSource"
Invoke-Tool cmake --build $loveBuild --config $Configuration --parallel

if (-not $SkipAngle) {
    Ensure-GitSource `
        -Name "depot_tools" `
        -Repository $metadata.sources.depotTools.repository `
        -Revision $metadata.sources.depotTools.commit `
        -Path $depotToolsSource
    Ensure-DepotToolsGit

    Ensure-GitSource `
        -Name "ANGLE" `
        -Repository $metadata.sources.angle.repository `
        -Revision $metadata.sources.angle.commit `
        -Path $angleSource

    $gclientPath = Join-Path $angleSource ".gclient"
    if (-not (Test-Path -LiteralPath $gclientPath -PathType Leaf)) {
        $gclient = @"
solutions = [
  {
    "name": ".",
    "url": "$($metadata.sources.angle.repository)",
    "deps_file": "DEPS",
    "managed": False,
    "custom_deps": {},
    "custom_vars": {},
  },
]
target_os = ["winuwp"]
"@
        [System.IO.File]::WriteAllText($gclientPath, $gclient, [System.Text.UTF8Encoding]::new($false))
    }

    $gn = Join-Path $angleSource "buildtools\win\gn.exe"
    $ninja = Join-Path $angleSource "third_party\ninja\ninja.exe"
    if (-not (Test-Path -LiteralPath $gn -PathType Leaf) -or
        -not (Test-Path -LiteralPath $ninja -PathType Leaf)) {
        Write-Host "Synchronising ANGLE dependencies..."
        $oldPath = $env:PATH
        $oldDepotToolsUpdate = $env:DEPOT_TOOLS_UPDATE
        $oldDepotToolsToolchain = $env:DEPOT_TOOLS_WIN_TOOLCHAIN
        try {
            $env:PATH = "$depotToolsSource;$oldPath"
            $env:DEPOT_TOOLS_UPDATE = "0"
            $env:DEPOT_TOOLS_WIN_TOOLCHAIN = "0"
            Push-Location $angleSource
            try {
                Invoke-Tool (Join-Path $depotToolsSource "gclient.bat") sync -D
            } finally {
                Pop-Location
            }
        } finally {
            $env:PATH = $oldPath
            $env:DEPOT_TOOLS_UPDATE = $oldDepotToolsUpdate
            $env:DEPOT_TOOLS_WIN_TOOLCHAIN = $oldDepotToolsToolchain
        }
    } else {
        Write-Host "Using the existing ANGLE dependency checkout."
    }

    Write-Host "Building ANGLE..."
    $angleBuild = Join-Path $angleSource "out\uwp-release"
    $gnArgs = ($metadata.sources.angle.gnArgs -join "`n")
    $oldPath = $env:PATH
    $oldDepotToolsToolchain = $env:DEPOT_TOOLS_WIN_TOOLCHAIN
    try {
        $env:PATH = "$depotToolsSource;$oldPath"
        $env:DEPOT_TOOLS_WIN_TOOLCHAIN = "0"
        Push-Location $angleSource
        try {
            Invoke-Tool $gn gen $angleBuild "--args=$gnArgs"
        } finally {
            Pop-Location
        }
        Invoke-Tool $ninja -C $angleBuild libEGL libGLESv2
    } finally {
        $env:PATH = $oldPath
        $env:DEPOT_TOOLS_WIN_TOOLCHAIN = $oldDepotToolsToolchain
    }

    Reset-Directory (Join-Path $angleRoot "bin")
    foreach ($name in @("libEGL.dll", "libGLESv2.dll", "d3dcompiler_47.dll")) {
        Copy-RequiredFile (Join-Path $angleBuild $name) (Join-Path $angleRoot "bin\$name")
    }
    Copy-RequiredFile (Join-Path $angleSource "AUTHORS") (Join-Path $angleRoot "AUTHORS")
    Copy-RequiredFile (Join-Path $angleSource "LICENSE") (Join-Path $angleRoot "LICENSE")
} else {
    Write-Host "Keeping the existing ANGLE runtime (-SkipAngle)."
}

Write-Host "Staging SDL2..."
Reset-Directory (Join-Path $sdlRoot "bin")
Reset-Directory (Join-Path $sdlRoot "lib")
Reset-Directory (Join-Path $sdlRoot "include")
Copy-RequiredFile (Join-Path $sdlInstall "bin\SDL2.dll") (Join-Path $sdlRoot "bin\SDL2.dll")
Copy-RequiredFile (Join-Path $sdlInstall "lib\SDL2.lib") (Join-Path $sdlRoot "lib\SDL2.lib")
Copy-Item -LiteralPath (Join-Path $sdlInstall "include\SDL2") -Destination (Join-Path $sdlRoot "include\SDL2") -Recurse

Write-Host "Staging LÖVE and LuaJIT..."
$loveOutput = Join-Path $loveBuild $Configuration
Reset-Directory (Join-Path $loveRoot "bin")
Reset-Directory (Join-Path $loveRoot "lib")
foreach ($name in @("love.dll", "lua51.dll")) {
    Copy-RequiredFile (Join-Path $loveOutput $name) (Join-Path $loveRoot "bin\$name")
}
foreach ($name in @("liblove.lib", "lovestatic.lib", "lua51.lib")) {
    Copy-RequiredFile (Join-Path $loveOutput $name) (Join-Path $loveRoot "lib\$name")
}

Write-Host "Staging the vcpkg runtime..."
Reset-Directory (Join-Path $runtimeRoot "bin")
foreach ($name in $metadata.sources.vcpkg.runtimeFiles) {
    Copy-RequiredFile (Join-Path $vcpkgInstalled "bin\$name") (Join-Path $runtimeRoot "bin\$name")
}

Write-Host "Updating dependency licences..."
Ensure-Directory $licensesRoot
Copy-RequiredFile (Join-Path $loveSource "license.txt") (Join-Path $licensesRoot "love.txt")
Copy-RequiredFile (Join-Path $luajitSource "COPYRIGHT") (Join-Path $licensesRoot "luajit.txt")
Copy-RequiredFile (Join-Path $sdlSource "LICENSE.txt") (Join-Path $licensesRoot "sdl2.txt")
Copy-RequiredFile (Join-Path $angleRoot "LICENSE") (Join-Path $licensesRoot "angle.txt")
foreach ($license in $metadata.sources.vcpkg.licenses.PSObject.Properties) {
    Copy-RequiredFile `
        (Join-Path $vcpkgInstalled "share\$($license.Name)\copyright") `
        (Join-Path $licensesRoot $license.Value)
}

Write-Host "Updating dependency hashes..."
Update-Manifest
& (Join-Path $PSScriptRoot "verify_dependencies.ps1") -Manifest $manifestPath
if ($LASTEXITCODE -ne 0) {
    throw "Dependency verification failed with exit code $LASTEXITCODE."
}

if (-not $SkipPackage) {
    Write-Host "Building the Release package..."
    $gitRoot = Split-Path -Parent (Split-Path -Parent (Get-Command git).Source)
    $bash = Join-Path $gitRoot "bin\bash.exe"
    if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) {
        throw "Git Bash was not found at $bash."
    }

    $buildScript = [System.IO.Path]::GetFullPath(
        (Join-Path $portRoot "..\..\scripts\build_xbox_uwp.sh")
    ).Replace("\", "/")
    if ($buildScript -match "^([A-Za-z]):/(.*)$") {
        $buildScript = "/$($Matches[1].ToLowerInvariant())/$($Matches[2])"
    }
    $packageConfiguration = if ($Configuration -eq "RelWithDebInfo") {
        "--relwithdebinfo"
    } else {
        "--release"
    }
    Invoke-Tool $bash $buildScript $packageConfiguration
}

Write-Host "UWP dependencies rebuilt and staged successfully."
