#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $MsixPath,

    [Parameter(Mandatory = $true)]
    [uri] $BaseUri,

    [string] $OutputRoot,

    [ValidateRange(0, 255)]
    [int] $HoursBetweenUpdateChecks = 0,

    [switch] $AllowUnsigned,

    [switch] $AllowDevelopmentPublisher,

    [switch] $AllowInsecureUri,

    [switch] $AllowMissingTimestamp,

    [switch] $OverwriteVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $PSScriptRoot '..\..\..\dist\windows'
}

function Read-MsixIdentity {
    param([Parameter(Mandatory = $true)][string] $Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $manifestEntry = $archive.Entries |
            Where-Object { $_.FullName -ieq 'AppxManifest.xml' } |
            Select-Object -First 1

        if ($null -eq $manifestEntry) {
            throw "MSIX 안에서 AppxManifest.xml을 찾을 수 없습니다: $Path"
        }

        if ($manifestEntry.Length -gt 1MB) {
            throw "MSIX AppxManifest.xml이 허용 크기 1 MiB를 넘습니다: $Path"
        }

        $stream = $manifestEntry.Open()
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
        try {
            [xml] $manifest = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
            $stream.Dispose()
        }

        $identity = $manifest.Package.Identity
        if ($null -eq $identity) {
            throw "MSIX manifest에 Identity가 없습니다: $Path"
        }

        $requiredAttributes = @('Name', 'Publisher', 'Version', 'ProcessorArchitecture')
        foreach ($attribute in $requiredAttributes) {
            if ([string]::IsNullOrWhiteSpace([string] $identity.$attribute)) {
                throw "MSIX Identity의 $attribute 값이 비어 있습니다: $Path"
            }
        }

        [pscustomobject]@{
            Name                  = [string] $identity.Name
            Publisher             = [string] $identity.Publisher
            Version               = [string] $identity.Version
            ProcessorArchitecture = ([string] $identity.ProcessorArchitecture).ToLowerInvariant()
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Write-AppInstallerFile {
    param(
        [Parameter(Mandatory = $true)] $Identity,
        [Parameter(Mandatory = $true)][string] $AppInstallerUri,
        [Parameter(Mandatory = $true)][string] $PackageUri,
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][int] $UpdateHours
    )

    $namespace = 'http://schemas.microsoft.com/appx/appinstaller/2018'
    $document = [System.Xml.XmlDocument]::new()
    $declaration = $document.CreateXmlDeclaration('1.0', 'utf-8', $null)
    [void] $document.AppendChild($declaration)

    $root = $document.CreateElement('AppInstaller', $namespace)
    $root.SetAttribute('Uri', $AppInstallerUri)
    $root.SetAttribute('Version', $Identity.Version)
    [void] $document.AppendChild($root)

    $mainPackage = $document.CreateElement('MainPackage', $namespace)
    $mainPackage.SetAttribute('Name', $Identity.Name)
    $mainPackage.SetAttribute('Publisher', $Identity.Publisher)
    $mainPackage.SetAttribute('Version', $Identity.Version)
    $mainPackage.SetAttribute('ProcessorArchitecture', $Identity.ProcessorArchitecture)
    $mainPackage.SetAttribute('Uri', $PackageUri)
    [void] $root.AppendChild($mainPackage)

    $updateSettings = $document.CreateElement('UpdateSettings', $namespace)
    $onLaunch = $document.CreateElement('OnLaunch', $namespace)
    $onLaunch.SetAttribute('HoursBetweenUpdateChecks', [string] $UpdateHours)
    $onLaunch.SetAttribute('ShowPrompt', 'true')
    $onLaunch.SetAttribute('UpdateBlocksActivation', 'false')
    [void] $updateSettings.AppendChild($onLaunch)
    [void] $updateSettings.AppendChild($document.CreateElement('AutomaticBackgroundTask', $namespace))
    [void] $root.AppendChild($updateSettings)

    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
    $settings.Indent = $true
    $settings.IndentChars = '  '
    $settings.NewLineChars = "`n"
    $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace

    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try {
        $document.Save($writer)
    }
    finally {
        $writer.Dispose()
    }
}

$resolvedMsixPath = (Resolve-Path -LiteralPath $MsixPath).Path
if ([System.IO.Path]::GetExtension($resolvedMsixPath) -ine '.msix') {
    throw "현재 생성기는 단일 x64 .msix만 지원합니다: $resolvedMsixPath"
}

if (-not $BaseUri.IsAbsoluteUri) {
    throw 'BaseUri는 절대 URI여야 합니다.'
}

if (-not [string]::IsNullOrEmpty($BaseUri.Query) -or -not [string]::IsNullOrEmpty($BaseUri.Fragment)) {
    throw 'BaseUri에는 query 또는 fragment를 넣을 수 없습니다.'
}

if ($BaseUri.Scheme -ne 'https' -and -not $AllowInsecureUri) {
    throw '공개 배포 BaseUri는 HTTPS여야 합니다. 로컬 시험에만 -AllowInsecureUri를 사용하세요.'
}

$identity = Read-MsixIdentity -Path $resolvedMsixPath
[void] [version]::Parse($identity.Version)

if ($identity.ProcessorArchitecture -ne 'x64') {
    throw "현재 공개 채널은 x64 MSIX만 지원합니다: $($identity.ProcessorArchitecture)"
}

if ($identity.Publisher -ieq 'CN=AppPublisher' -and -not $AllowDevelopmentPublisher) {
    throw '개발용 Publisher CN=AppPublisher 패키지는 공개 산출물로 만들 수 없습니다. 인증서 subject로 manifest를 먼저 갱신하세요.'
}

$signature = Get-AuthenticodeSignature -LiteralPath $resolvedMsixPath
if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    if (-not $AllowUnsigned) {
        throw "MSIX 서명이 유효하지 않습니다: $($signature.Status). 공개 산출물에는 신뢰 가능한 코드 서명이 필요합니다."
    }

    Write-Warning "내부 시험용 미서명 산출물을 생성합니다. 공개 배포하지 마세요. 서명 상태: $($signature.Status)"
}
else {
    if ($null -eq $signature.SignerCertificate) {
        throw '서명 상태는 Valid이지만 서명 인증서를 읽을 수 없습니다.'
    }

    if (-not [string]::Equals(
            $signature.SignerCertificate.Subject,
            $identity.Publisher,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "인증서 subject와 MSIX Publisher가 다릅니다. 인증서: '$($signature.SignerCertificate.Subject)', Publisher: '$($identity.Publisher)'"
    }

    if ($null -eq $signature.TimeStamperCertificate -and -not $AllowMissingTimestamp) {
        throw 'MSIX에 신뢰 가능한 타임스탬프가 없습니다. 인증서 만료 뒤에도 서명을 검증하려면 RFC 3161 타임스탬프를 추가하세요.'
    }
}

$normalizedBaseUri = $BaseUri.AbsoluteUri.TrimEnd('/')
$resolvedOutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$versionDirectory = Join-Path $resolvedOutputRoot $identity.Version
$packageFileName = "MonglePet-Windows-$($identity.Version)-$($identity.ProcessorArchitecture).msix"
$versionedAppInstallerName = 'MonglePet.appinstaller'
$packageDestination = Join-Path $versionDirectory $packageFileName
$versionedAppInstallerPath = Join-Path $versionDirectory $versionedAppInstallerName
$checksumPath = Join-Path $versionDirectory 'SHA256SUMS.txt'
$stableAppInstallerPath = Join-Path $resolvedOutputRoot $versionedAppInstallerName

$versionTargets = @($packageDestination, $versionedAppInstallerPath, $checksumPath)
$existingTargets = @($versionTargets | Where-Object { Test-Path -LiteralPath $_ })
if ($existingTargets.Count -gt 0 -and -not $OverwriteVersion) {
    throw "같은 버전의 산출물이 이미 있습니다. 버전을 올리거나 -OverwriteVersion을 명시하세요: $($existingTargets -join ', ')"
}

[void] (New-Item -ItemType Directory -Path $versionDirectory -Force)
Copy-Item -LiteralPath $resolvedMsixPath -Destination $packageDestination -Force:$OverwriteVersion

$appInstallerUri = "$normalizedBaseUri/$versionedAppInstallerName"
$packageUri = "$normalizedBaseUri/$($identity.Version)/$packageFileName"
Write-AppInstallerFile `
    -Identity $identity `
    -AppInstallerUri $appInstallerUri `
    -PackageUri $packageUri `
    -Path $versionedAppInstallerPath `
    -UpdateHours $HoursBetweenUpdateChecks

$packageHash = (Get-FileHash -LiteralPath $packageDestination -Algorithm SHA256).Hash
$appInstallerHash = (Get-FileHash -LiteralPath $versionedAppInstallerPath -Algorithm SHA256).Hash
$checksumContents = @(
    "$packageHash  $packageFileName"
    "$appInstallerHash  $versionedAppInstallerName"
) -join "`n"
[System.IO.File]::WriteAllText(
    $checksumPath,
    "$checksumContents`n",
    [System.Text.UTF8Encoding]::new($false))

# 자동 업데이트 파일은 버전별 MSIX와 체크섬을 모두 만든 뒤 마지막에 교체한다.
# 웹에 올릴 때도 같은 순서를 사용하면 기존 사용자가 아직 없는 MSIX를 참조하지 않는다.
$stableTemporaryPath = "$stableAppInstallerPath.tmp"
Copy-Item -LiteralPath $versionedAppInstallerPath -Destination $stableTemporaryPath -Force
Move-Item -LiteralPath $stableTemporaryPath -Destination $stableAppInstallerPath -Force

[pscustomobject]@{
    Version             = $identity.Version
    Name                = $identity.Name
    Publisher           = $identity.Publisher
    Architecture        = $identity.ProcessorArchitecture
    SignatureStatus     = [string] $signature.Status
    Package             = $packageDestination
    AppInstaller        = $stableAppInstallerPath
    VersionedInstaller  = $versionedAppInstallerPath
    Checksums           = $checksumPath
    PackageUri          = $packageUri
    AppInstallerUri     = $appInstallerUri
}
