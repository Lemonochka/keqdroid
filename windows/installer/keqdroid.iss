; собирает tool/build_windows_installer.ps1, компилятор Inno Setup 7.1.1, тот же в .github/workflows/release.yml

#ifndef AppVersion
  #error AppVersion is not defined
#endif
#ifndef BuildDir
  #error BuildDir is not defined
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

[Setup]
; не менять никогда: по нему установщик находит прежнюю установку, а апдейтер свою запись в Uninstall (windows_install.dart)
AppId={{2F4ADD17-AA28-4805-B040-B3EE05138A9C}
AppName=keqdroid
AppVersion={#AppVersion}
AppVerName=keqdroid {#AppVersion}
AppPublisher=keqdroid
AppPublisherURL=https://github.com/Lemonochka/keqdroid
AppSupportURL=https://github.com/Lemonochka/keqdroid/issues
AppUpdatesURL=https://github.com/Lemonochka/keqdroid/releases
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\keqdroid
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
; мьютекс одного экземпляра из windows/runner/main.cpp, его держит и портабельная копия: настройки у них общие
AppMutex=Local\KeqDroid.SingleInstance
RestartApplications=no
ShowLanguageDialog=no
WizardStyle=modern
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\keqdroid.exe
UninstallDisplayName=keqdroid
OutputDir={#OutputDir}
OutputBaseFilename=keqdroid-windows-x64-{#AppVersion}-setup
Compression=lzma2/max
SolidCompression=yes
#ifdef SignedUninstallerDir
SignedUninstaller=yes
SignedUninstallerDir={#SignedUninstallerDir}
#endif

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "de"; MessagesFile: "compiler:Languages\German.isl"
Name: "zh"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
; неофициальный перевод, в комплект Inno Setup не входит: Files/Languages/Unofficial/Farsi.isl из issrc на теге is-7_1_1
Name: "fa"; MessagesFile: "languages\Farsi.isl"

[CustomMessages]
en.RemoveUserData=Also delete keqdroid settings, subscriptions and logs?%n%nA portable copy of keqdroid on this computer uses the same ones. Choose No if you are going to install keqdroid again.
ru.RemoveUserData=Удалить также настройки, подписки и журналы keqdroid?%n%nПортабельная копия keqdroid на этом компьютере пользуется ими же. Выберите «Нет», если собираетесь поставить keqdroid снова.
de.RemoveUserData=Auch die Einstellungen, Abonnements und Protokolle von keqdroid löschen?%n%nEine portable Kopie von keqdroid auf diesem Computer verwendet dieselben. Wähle „Nein“, wenn du keqdroid wieder installieren willst.
zh.RemoveUserData=同时删除 keqdroid 的设置、订阅和日志吗？%n%n本机上的 keqdroid 便携版也使用这些数据。如果您打算重新安装 keqdroid，请选择“否”。
fa.RemoveUserData=تنظیمات، اشتراک‌ها و گزارش‌های keqdroid هم حذف شوند؟%n%nنسخهٔ قابل‌حمل keqdroid روی این رایانه هم از همین‌ها استفاده می‌کند. اگر می‌خواهید keqdroid را دوباره نصب کنید، «خیر» را انتخاب کنید.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\keqdroid"; Filename: "{app}\keqdroid.exe"
Name: "{autodesktop}\keqdroid"; Filename: "{app}\keqdroid.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\keqdroid.exe"; Description: "{cm:LaunchProgram,keqdroid}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: dirifempty; Name: "{app}"

[Code]
// задача автозапуска с правами от портабельной копии смотрит на её exe, а приложение без UAC её не перепишет
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssPostInstall then
    Exec(ExpandConstant('{app}\keqdroid.exe'), '--adopt-autostart', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure RemoveUserData;
begin
  // имена папок path_provider берёт из CompanyName и ProductName в windows/runner/Runner.rc
  DelTree(ExpandConstant('{userappdata}\com.keqdroid\keqdroid'), True, True, True);
  RemoveDir(ExpandConstant('{userappdata}\com.keqdroid'));
  DelTree(ExpandConstant('{localappdata}\keqdroid'), True, True, True);
  RegDeleteKeyIncludingSubkeys(HKCU, 'Software\KeqDroid');
end;

// не в InitializeUninstall: тот идёт раньше проверки AppMutex и снял бы прокси и ядра у запущенной копии
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
    // зависший прокси снимает только сам exe при старте, а после удаления старта не будет
    Exec(ExpandConstant('{app}\keqdroid.exe'), '--uninstall-cleanup', '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
  else if CurUninstallStep = usPostUninstall then
  begin
    if not UninstallSilent and
       (MsgBox(CustomMessage('RemoveUserData'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES) then
      RemoveUserData;
  end;
end;
