param(
    [Parameter(Mandatory = $true)][string]$JdkDirectory,
    [ValidateSet('debug', 'profile', 'release')][string]$Mode = 'debug'
)

$ErrorActionPreference = 'Stop'
$jdk = (Resolve-Path -LiteralPath $JdkDirectory).Path
if (-not (Test-Path -LiteralPath (Join-Path $jdk 'bin/java.exe'))) {
    throw 'JdkDirectory must contain bin/java.exe.'
}
$previousGradleOptions = $env:GRADLE_OPTS
$previousDirectory = Get-Location
try {
    Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
    # Kotlin incremental caches cannot relativize C: packages against an F:
    # project. Limit this workaround and the JDK selection to this process.
    $env:GRADLE_OPTS = "$previousGradleOptions `"-Dorg.gradle.java.home=$jdk`" -Dorg.gradle.project.kotlin.incremental=false"
    & flutter build apk "--$Mode"
    $buildExit = $LASTEXITCODE
} finally {
    $env:GRADLE_OPTS = $previousGradleOptions
    Set-Location -LiteralPath $previousDirectory.Path
}
exit $buildExit
