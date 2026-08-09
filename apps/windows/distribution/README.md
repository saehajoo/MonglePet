# MonglePet Windows 웹 배포

## 현재 첫 Preview: EXE 설치기

코드 서명 자격 증명이 없는 첫 Preview는 자체 웹사이트의 `MonglePet-Windows-<version>-x64-Setup.exe`를 기본 다운로드로 제공하고, GitHub Releases에 같은 파일과 `SHA256SUMS.txt`를 보조 사본으로 올린다. 설치기는 x64 unpackaged WinUI 3 앱과 .NET·Windows App SDK 런타임을 포함하며 관리자 권한 없이 현재 사용자에게 설치된다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File '.\apps\windows\scripts\New-WindowsExeInstaller.ps1' `
    -AllowUnsigned
```

공개 전 다음 값을 확인한다.

```powershell
Get-AuthenticodeSignature '.\dist\windows-exe\<version>\MonglePet-Windows-<version>-x64-Setup.exe'
Get-FileHash '.\dist\windows-exe\<version>\MonglePet-Windows-<version>-x64-Setup.exe' -Algorithm SHA256
```

미서명 Preview는 Windows SmartScreen 경고가 표시되거나 Smart App Control·조직 정책에서 차단될 수 있다. 다운로드 페이지에는 Windows 11 25H2 build 26200 이상·x64 요구사항, 미서명 Preview라는 사실, 정확한 파일명·크기·SHA-256과 수동 업데이트 방식을 함께 안내한다. 경고 우회 안내는 공식 웹 또는 GitHub Release에서 받은 파일의 SHA-256이 일치할 때만 제공한다.

업로드 순서는 버전별 Setup EXE와 SHA256SUMS를 먼저 올리고 다운로드 페이지 링크를 마지막에 교체한다. 새 버전은 기존 AppId를 유지한 설치기로 덮어 설치하며 제거는 앱 파일·바로가기·자동 실행만 정리하고 `%LOCALAPPDATA%\MonglePet` 데이터는 보존한다.

## 향후 서명된 MSIX·App Installer 채널

코드 서명 자격 증명이 준비되면 신뢰 가능한 코드 서명이 적용된 버전별 MSIX, 고정 URL의 App Installer 파일과 SHA-256 체크섬을 자동 업데이트 채널로 추가할 수 있다. 사용자 웹사이트가 기본 다운로드 화면을 제공하고 GitHub Releases는 같은 산출물의 버전 기록과 보조 다운로드 경로로 사용한다.

현재 `Package.appxmanifest`의 `Publisher="CN=AppPublisher"`는 개발용 자리표시자다. 이 Publisher로 만든 미서명 MSIX는 공개하지 않는다.

## 첫 공개 버전 전에 고정할 값

1. 공개 코드 서명 인증서 또는 신뢰 가능한 원격 서명 서비스를 준비한다.
2. `Package.appxmanifest`의 `Identity Publisher`를 서명 인증서의 전체 subject와 정확히 같게 바꾼다.
3. `PublisherDisplayName`을 웹사이트에 표시할 배포자 이름으로 바꾼다.
4. 현재 `Identity Name`을 유지할지 최종 확인한다.
5. 첫 공개 설치 이후에는 `Identity Name`과 `Publisher`를 바꾸지 않는다. 바꾸면 Windows가 다른 앱으로 인식하고 기존 설치의 자동 업데이트가 끊긴다.

PFX 파일, 비밀번호, 인증서 저장소 내보내기와 서명 서비스 자격 증명은 저장소에 넣지 않는다.

## 서명된 MSIX 만들기

인증서를 `Cert:\CurrentUser\My`에 설치했다면 다음 명령으로 코드 서명 인증서와 subject를 확인할 수 있다.

```powershell
Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
    Select-Object Subject, Thumbprint, NotAfter
```

manifest의 Publisher를 인증서 subject로 갱신한 뒤 저장소 루트에서 Release MSIX를 만든다. 아래의 thumbprint는 실제 인증서 값으로 교체한다.

```powershell
$certificateThumbprint = '<CODE-SIGNING-CERTIFICATE-THUMBPRINT>'

dotnet msbuild apps/windows/src/MonglePet.Windows/MonglePet.Windows.csproj `
    /restore `
    /p:Configuration=Release `
    /p:Platform=x64 `
    /p:RuntimeIdentifier=win-x64 `
    /p:GenerateAppxPackageOnBuild=true `
    /p:UapAppxPackageBuildMode=SideloadOnly `
    /p:AppxBundle=Never `
    /p:AppxPackageSigningEnabled=true `
    /p:PackageCertificateThumbprint=$certificateThumbprint
```

사용하는 서명 방식이 MSBuild 단계에서 RFC 3161 타임스탬프를 넣지 않는다면, 서명 서비스나 `SignTool` 단계에서 타임스탬프를 추가해야 한다. 인증서 만료 뒤에도 기존 배포 파일의 서명을 검증하기 위해 필요하다.

## App Installer와 체크섬 만들기

서명된 MSIX 경로를 지정하면 스크립트가 패키지 내부 manifest를 직접 읽고 서명 상태, Publisher, 인증서 subject와 타임스탬프를 검증한다.

```powershell
.\apps\windows\scripts\New-WindowsReleaseArtifacts.ps1 `
    -MsixPath '.\apps\windows\src\MonglePet.Windows\AppPackages\<SIGNED-PACKAGE>\MonglePet.Windows_<VERSION>_x64.msix' `
    -BaseUri 'https://dev.mapleroom.kr/monglepet/downloads/windows'
```

현재 PC처럼 PowerShell 스크립트 실행 정책이 차단된 환경에서는 시스템 정책을 변경하지 않고 이번 프로세스에만 우회 옵션을 준다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File '.\apps\windows\scripts\New-WindowsReleaseArtifacts.ps1' `
    -MsixPath '.\apps\windows\src\MonglePet.Windows\AppPackages\<SIGNED-PACKAGE>\MonglePet.Windows_<VERSION>_x64.msix' `
    -BaseUri 'https://dev.mapleroom.kr/monglepet/downloads/windows'
```

기본 출력은 다음과 같다.

```text
dist/windows/
├─ MonglePet.appinstaller
└─ 1.0.0.13/
   ├─ MonglePet-Windows-1.0.0.13-x64.msix
   ├─ MonglePet.appinstaller
   └─ SHA256SUMS.txt
```

같은 버전 폴더를 의도적으로 다시 만들 때만 `-OverwriteVersion`을 사용한다. `-AllowUnsigned`, `-AllowDevelopmentPublisher`, `-AllowMissingTimestamp`는 내부 구조 검증을 위한 옵션이며 그 결과물을 공개하면 안 된다.

생성되는 App Installer는 앱 실행 시 업데이트를 확인하고 Windows의 백그라운드 확인도 허용한다. 새 릴리스에서는 MSIX `Identity Version`을 반드시 이전 공개 버전보다 높인다.

## 웹 업로드 순서

다음 순서로 올려야 기존 사용자가 아직 업로드되지 않은 MSIX를 참조하지 않는다.

1. `/<version>/MonglePet-Windows-<version>-x64.msix`
2. `/<version>/MonglePet.appinstaller`
3. `/<version>/SHA256SUMS.txt`
4. 마지막에 고정 URL `/MonglePet.appinstaller`

웹 서버는 HTTPS를 사용하고 다음 MIME type을 제공한다.

```text
.msix          application/msix
.msixbundle    application/msixbundle
.appinstaller  application/appinstaller
```

다운로드 페이지의 기본 버튼은 고정된 `MonglePet.appinstaller`를 가리킨다. 직접 설치가 필요한 사용자를 위해 같은 버전의 MSIX와 SHA256SUMS 링크도 함께 제공한다. GitHub Release에는 버전별 MSIX, App Installer 사본과 SHA256SUMS를 동일한 이름으로 올린다.

## 공개 전 확인

```powershell
Get-AuthenticodeSignature '.\dist\windows\<version>\MonglePet-Windows-<version>-x64.msix' |
    Format-List Status, StatusMessage, SignerCertificate, TimeStamperCertificate

Get-FileHash '.\dist\windows\<version>\MonglePet-Windows-<version>-x64.msix' -Algorithm SHA256
```

깨끗한 Windows 사용자 계정 또는 별도 PC에서 최초 설치, 시작 메뉴 실행, 로그인 자동 실행, 업데이트, 제거와 재설치를 확인한다. 업데이트 시험은 낮은 버전을 설치한 뒤 높은 버전의 MSIX와 App Installer를 시험 HTTPS 위치에 올려 수행한다.
