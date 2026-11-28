[Setup]
AppId=app.memorytaker.MT
AppName=MRecorder
AppVersion=1.3.2
AppPublisher=MRecorder contributors
DefaultDirName={localappdata}\Programs\MT
DefaultGroupName=MRecorder
PrivilegesRequired=lowest
OutputDir=..\..\build\installer
OutputBaseFilename=MR_windows_1.3.2
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\MRecorder.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
Type: files; Name: "{app}\MT.exe"

[Icons]
Name: "{group}\MRecorder"; Filename: "{app}\MRecorder.exe"
Name: "{autodesktop}\MRecorder"; Filename: "{app}\MRecorder.exe"; Tasks: desktopicon

[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Run]
Filename: "{app}\MRecorder.exe"; Description: "Launch MRecorder"; Flags: nowait postinstall skipifsilent
