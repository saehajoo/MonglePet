#ifndef AppVersion
  #error AppVersion must be provided with /DAppVersion=<version>.
#endif

#ifndef PublishDir
  #error PublishDir must be provided with /DPublishDir=<absolute-path>.
#endif

#ifndef OutputDir
  #error OutputDir must be provided with /DOutputDir=<absolute-path>.
#endif

#ifndef OutputBaseFilename
  #error OutputBaseFilename must be provided with /DOutputBaseFilename=<name>.
#endif

#define AppName "MonglePet"
#define AppExeName "MonglePet.Windows.exe"
#define AppPublisher "MapleRoom"
#define AppWebsite "https://dev.mapleroom.kr/monglepet"
#define AppWindowName "MonglePet Unpackaged Notification Area"
#define QuitMessageName "MonglePet.Quit.1"

[Setup]
AppId={{D8FC2ADD-4E8D-45E6-8246-AD6F951A1B1A}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppWebsite}
AppSupportURL={#AppWebsite}
AppUpdatesURL={#AppWebsite}
DefaultDirName={localappdata}\Programs\MonglePet
DefaultGroupName=MonglePet
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.26200
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
SetupIconFile={#PublishDir}\Assets\AppIcon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter={#AppExeName}
RestartApplications=no
ChangesAssociations=no
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} Windows Installer
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}
VersionInfoVersion={#AppVersion}

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "바탕 화면에 바로 가기 만들기"; GroupDescription: "추가 바로 가기:"; Flags: unchecked

[Files]
Source: "{#PublishDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MonglePet"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\MonglePet"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "MonglePet 실행"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[Code]
const
  RunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';
  RunValueName = 'MonglePet';

function RequestRunningAppToQuit: Boolean;
var
  AppWindow: HWND;
  Attempt: Integer;
  QuitMessage: Cardinal;
begin
  Result := False;
  QuitMessage := RegisterWindowMessage('{#QuitMessageName}');
  if QuitMessage = 0 then
    Exit;

  for Attempt := 1 to 100 do
  begin
    AppWindow := FindWindowByWindowName('{#AppWindowName}');
    if AppWindow = 0 then
    begin
      Result := True;
      Exit;
    end;

    PostMessage(AppWindow, QuitMessage, 0, 0);
    Sleep(100);
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  if RequestRunningAppToQuit then
    Result := ''
  else
    Result := '실행 중인 MonglePet을 종료하지 못했습니다. 트레이 메뉴에서 MonglePet을 종료한 뒤 다시 시도해 주세요.';
end;

function InitializeUninstall: Boolean;
begin
  Result := RequestRunningAppToQuit;
  if not Result then
  begin
    SuppressibleMsgBox(
      '실행 중인 MonglePet을 종료하지 못했습니다. 트레이 메뉴에서 MonglePet을 종료한 뒤 다시 시도해 주세요.',
      mbError,
      MB_OK,
      IDOK);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ExistingCommand: String;
  InstalledCommand: String;
begin
  if CurUninstallStep <> usPostUninstall then
    Exit;

  InstalledCommand := '"' + ExpandConstant('{app}\{#AppExeName}') + '" --startup';
  if RegQueryStringValue(HKCU, RunKey, RunValueName, ExistingCommand) and
     (CompareText(ExistingCommand, InstalledCommand) = 0) then
  begin
    RegDeleteValue(HKCU, RunKey, RunValueName);
  end;
end;
