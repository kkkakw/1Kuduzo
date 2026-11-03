; Установщик Kuduzo VPN для Windows (Inno Setup 6).
; Сборка: ISCC /DMyAppVersion=0.5.0 installer\kuduzo.iss  →  dist\Kuduzo-VPN-Setup-x64.exe
; Ставится в профиль пользователя — права администратора для установки не нужны.
; Тихое обновление из приложения: /SILENT /SUPPRESSMSGBOXES /NORESTART

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#define MyAppName "Kuduzo VPN"
#define MyAppExe "kuduzo.exe"

[Setup]
AppId={{8B5E2F4A-3C1D-4E7A-9F2B-6D4C1A8E5B37}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=Kuduzo
AppPublisherURL=https://vpnkuduzo.ru
AppSupportURL=https://t.me/kuduzohelpbot
DefaultDirName={localappdata}\Programs\Kuduzo VPN
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=Kuduzo-VPN-Setup-x64
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExe}
UninstallDisplayName={#MyAppName}
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
CloseApplications=force
RestartApplications=no
ShowLanguageDialog=auto

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon

[Registry]
; Ссылки kuduzo://… открываются в приложении.
Root: HKCU; Subkey: "Software\Classes\kuduzo"; ValueType: string; ValueName: ""; ValueData: "URL:Kuduzo VPN"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\kuduzo"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\kuduzo\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExe},0"
Root: HKCU; Subkey: "Software\Classes\kuduzo\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExe}"" ""%1"""

[Run]
; Запуск после установки — и после тихого обновления из приложения.
Filename: "{app}\{#MyAppExe}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall

[UninstallRun]
; Закрываем только ядро из папки Kuduzo — xray.exe других программ не трогаем.
Filename: "powershell.exe"; Parameters: "-NoProfile -NonInteractive -Command ""Get-Process xray -ErrorAction SilentlyContinue | Where-Object {{ $_.Path -like '{app}\*' } | Stop-Process -Force"""; Flags: runhidden; RunOnceId: "KillXray"
Filename: "{sys}\taskkill.exe"; Parameters: "/f /im {#MyAppExe}"; Flags: runhidden; RunOnceId: "KillApp"

[Code]
// Перед установкой закрываем ядро Xray из папки Kuduzo: иначе его файл занят и не обновится.
// xray.exe других программ (v2rayN и т. п.) не трогаем.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Code: Integer;
begin
  Exec('powershell.exe',
    '-NoProfile -NonInteractive -Command "Get-Process xray -ErrorAction SilentlyContinue | ' +
    'Where-Object { $_.Path -like ''' + ExpandConstant('{app}') + '\*'' } | Stop-Process -Force"',
    '', SW_HIDE, ewWaitUntilTerminated, Code);
  Result := '';
end;
