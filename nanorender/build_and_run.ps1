param(
    [ValidateSet("Release", "Debug", "RelWithDebInfo")]
    [string]$Configuration = "Release"
)

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    throw "Could not find vswhere.exe at '$vswhere'."
}

$vsInstallPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsInstallPath) {
    throw "No compatible Visual Studio installation with C++ build tools was found."
}

$vcvars = Join-Path $vsInstallPath "VC\Auxiliary\Build\vcvarsall.bat"
if (-not (Test-Path $vcvars)) {
    throw "Expected MSVC environment script was not found at '$vcvars'."
}

$ninjaCommand = Get-Command ninja -ErrorAction SilentlyContinue
if (-not $ninjaCommand) {
    throw "Could not find 'ninja' on PATH."
}

$ninjaPath = $ninjaCommand.Source
$buildDir = "$PSScriptRoot\build\$Configuration"
$cachePath = Join-Path $buildDir "CMakeCache.txt"

if (Test-Path $cachePath) {
    $cachedNinja = Select-String -Path $cachePath -Pattern '^CMAKE_MAKE_PROGRAM:FILEPATH=(.+)$' | Select-Object -First 1
    if ($cachedNinja) {
        $cachedNinjaPath = $cachedNinja.Matches[0].Groups[1].Value
        if (($cachedNinjaPath -ne $ninjaPath) -or (-not (Test-Path $cachedNinjaPath))) {
            Remove-Item $buildDir -Recurse -Force
        }
    }
}

# 1. Configure the CMake project
# This sets up the MSVC environment and generates the Ninja build files
cmd /c "`"$vcvars`" x64 && cmake -G Ninja -DCMAKE_BUILD_TYPE=$Configuration -DCMAKE_MAKE_PROGRAM=`"$ninjaPath`" -B `"$buildDir`" -S `"$PSScriptRoot`""
if ($LASTEXITCODE -ne 0) {
    Write-Error "CMake configuration failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

# 2. Build the project
# We need to set up the MSVC environment again for the build step
cmd /c "`"$vcvars`" x64 && cmake --build `"$buildDir`""

if ($LASTEXITCODE -eq 0) {
    & "$buildDir\minigui.exe"
} else {
    Write-Error "Build failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}
