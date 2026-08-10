#requires -Version 5.1

[CmdletBinding()]
param(
    [string] $Configuration = 'Release',

    [string] $OutputRoot,

    [string] $DotNetPath,

    [string] $InnoCompilerPath,

    [switch] $SkipPublish,

    [switch] $AllowUnsigned,

    [switch] $OverwriteVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $PSScriptRoot '..\..\..\dist\windows-exe'
}

function Resolve-ExecutablePath {
    param(
        [Parameter(Mandatory = $true)][string] $DisplayName,
        [string] $ExplicitPath,
        [Parameter(Mandatory = $true)][string[]] $Candidates
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
            throw "$DisplayName 실행 파일을 찾을 수 없습니다: $ExplicitPath"
        }

        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }

        $command = Get-Command $candidate -CommandType Application -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Source
        }
    }

    throw "$DisplayName 실행 파일을 찾을 수 없습니다. 경로를 매개 변수로 지정하세요."
}

$windowsRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$projectPath = Join-Path $windowsRoot 'src\MonglePet.Windows\MonglePet.Windows.csproj'
$publishProfile = 'win-x64-unpackaged'
$targetFramework = 'net10.0-windows10.0.26100.0'
$publishDirectory = Join-Path $windowsRoot "src\MonglePet.Windows\bin\$Configuration\$targetFramework\win-x64\publish-unpackaged"
$installerScript = Join-Path $windowsRoot 'installer\MonglePet.iss'
$resolvedOutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)

$resolvedDotNetPath = Resolve-ExecutablePath `
    -DisplayName '.NET SDK' `
    -ExplicitPath $DotNetPath `
    -Candidates @('dotnet.exe', (Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'))

if (-not $SkipPublish) {
    & $resolvedDotNetPath publish $projectPath `
        --configuration $Configuration `
        --maxcpucount:1 `
        /p:PublishProfile=$publishProfile `
        /p:NuGetAudit=false

    if ($LASTEXITCODE -ne 0) {
        throw "비패키징 Release 게시가 실패했습니다. 종료 코드: $LASTEXITCODE"
    }
}

$publishedExe = Join-Path $publishDirectory 'MonglePet.Windows.exe'
if (-not (Test-Path -LiteralPath $publishedExe -PathType Leaf)) {
    throw "게시된 실행 파일을 찾을 수 없습니다: $publishedExe"
}

if (Test-Path -LiteralPath (Join-Path $publishDirectory 'AppxManifest.xml')) {
    throw "비패키징 게시 폴더에 AppxManifest.xml이 있습니다: $publishDirectory"
}

$versionInfo = (Get-Item -LiteralPath $publishedExe).VersionInfo
if ([string]::IsNullOrWhiteSpace($versionInfo.FileVersion)) {
    throw "게시 실행 파일에서 FileVersion을 읽을 수 없습니다: $publishedExe"
}

$version = [version]::Parse($versionInfo.FileVersion).ToString()
$sourceSignature = Get-AuthenticodeSignature -LiteralPath $publishedExe
if ($sourceSignature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    if (-not $AllowUnsigned) {
        throw "게시 실행 파일의 서명이 유효하지 않습니다: $($sourceSignature.Status). 미서명 Preview를 만들 때만 -AllowUnsigned를 명시하세요."
    }

    Write-Warning "SmartScreen 경고가 표시될 수 있는 미서명 Preview 설치기를 만듭니다. 실행 파일 서명 상태: $($sourceSignature.Status)"
}

$resolvedInnoCompilerPath = Resolve-ExecutablePath `
    -DisplayName 'Inno Setup Compiler' `
    -ExplicitPath $InnoCompilerPath `
    -Candidates @(
        'ISCC.exe',
        (Join-Path $env:LocalAppData 'Programs\Inno Setup 6\ISCC.exe'),
        (Join-Path $env:LocalAppData 'Programs\Inno Setup 7\ISCC.exe'),
        (Join-Path ${env:ProgramFiles} 'Inno Setup 7\ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe')
    )

$versionDirectory = Join-Path $resolvedOutputRoot $version
$outputBaseFilename = "MonglePet-Windows-$version-x64-Setup"
$installerPath = Join-Path $versionDirectory "$outputBaseFilename.exe"
$checksumPath = Join-Path $versionDirectory 'SHA256SUMS.txt'

$existingTargets = @(@($installerPath, $checksumPath) | Where-Object { Test-Path -LiteralPath $_ })
if ($existingTargets.Count -gt 0 -and -not $OverwriteVersion) {
    throw "같은 버전의 설치기 산출물이 이미 있습니다. 버전을 올리거나 -OverwriteVersion을 명시하세요: $($existingTargets -join ', ')"
}

[void] (New-Item -ItemType Directory -Path $versionDirectory -Force)

$compilerArguments = @(
    '/Qp',
    "/DAppVersion=$version",
    "/DPublishDir=$publishDirectory",
    "/DOutputDir=$versionDirectory",
    "/DOutputBaseFilename=$outputBaseFilename",
    $installerScript
)

& $resolvedInnoCompilerPath $compilerArguments
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup 설치기 생성이 실패했습니다. 종료 코드: $LASTEXITCODE"
}

if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    throw "생성된 설치기를 찾을 수 없습니다: $installerPath"
}

$installerSignature = Get-AuthenticodeSignature -LiteralPath $installerPath
if ($installerSignature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -and -not $AllowUnsigned) {
    throw "설치기 서명이 유효하지 않습니다: $($installerSignature.Status)"
}

$installerHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash
[System.IO.File]::WriteAllText(
    $checksumPath,
    "$installerHash  $([System.IO.Path]::GetFileName($installerPath))`n",
    [System.Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    Version             = $version
    Architecture        = 'x64'
    PublishDirectory    = $publishDirectory
    Installer           = $installerPath
    SignatureStatus     = [string] $installerSignature.Status
    Sha256              = $installerHash
    Checksums            = $checksumPath
}
