[Setup]
AppId=app.memorytaker.MT
AppName=MT - Memory Taker
AppVersion=1.1.0
AppPublisher=MT contributors
DefaultDirName={localappdata}\Programs\MT
DefaultGroupName=MT
PrivilegesRequired=lowest
OutputDir=..\..\build\installer
OutputBaseFilename=MT-Windows-Setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\MT.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MT"; Filename: "{app}\MT.exe"
Name: "{autodesktop}\MT"; Filename: "{app}\MT.exe"; Tasks: desktopicon

[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Run]
Filename: "{app}\MT.exe"; Description: "Launch MT"; Flags: nowait postinstall skipifsilent
