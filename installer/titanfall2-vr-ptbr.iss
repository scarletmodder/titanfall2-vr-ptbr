; Inno Setup script of the translation installer: a per-user wizard (no admin rights to install).
; It installs the tool, applies the translation to the chosen game folder and, on uninstall, puts the
; originals back through the tool itself before removing anything.
;
; Build with scripts\build.ps1, which compiles the tool first and passes the version.

#if VER < EncodeVer(6, 3, 0)
  #error Inno Setup 6.3 or newer is required (ExecAndCaptureOutput, UTF-8 script without BOM)
#endif

#define AppName "Tradução PT-BR do mod Titanfall 2 VR"
#define AppPublisher "Scarlet Modder"
#define AppURL "https://github.com/scarletmodder/titanfall2-vr-ptbr"
#define ExeName "Titanfall2VR-PTBR.exe"
#define WindowExeName "Titanfall2VR-PTBR-Window.exe"
; The window of the Start menu holds this while it is open: it also appears in src\Window.cs.
#define WindowMutex "ScarletModder.Titanfall2VRPTBR.Window"
; Identifies the installation across upgrades: never change it.
#define AppGuid "7B0E5C1A-3D42-4F6B-9A58-2C8D1E7F4A36"
; What versions before the installer registered, and where they kept a copy of the exe.
#define LegacyUninstallKey "Software\Microsoft\Windows\CurrentVersion\Uninstall\Titanfall2VR-PTBR"
#define LegacyCopyDir "{localappdata}\ScarletModder\Titanfall2VR-PTBR\uninstall"
#define ModTokens "TF2VR\mods\Titanfall2VR.Cockpit\mod\resource\tf2vr_english.txt"
#define ModInstallerUrl "https://github.com/CircuitLord/CircuitLordVRModInstaller"
; Exit code of Setup when the tool was installed but the translation was not applied.
#define ExitTranslationFailed 30

#define DistDir AddBackslash(SourcePath) + "..\dist"
#if !FileExists(DistDir + "\" + ExeName) || !FileExists(DistDir + "\" + WindowExeName)
  #error The programs are not in dist: run scripts\build.ps1
#endif
#ifndef AppVersion
  #error AppVersion is missing: run scripts\build.ps1
#endif

[Setup]
AppId={{{#AppGuid}}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany={#AppPublisher}
VersionInfoCopyright={#AppPublisher}, MIT license
VersionInfoDescription={#AppName}
; Per user: no administrator prompt to install, everything under the user's profile and HKCU.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\Titanfall2VR-PTBR
DisableWelcomePage=no
DisableDirPage=yes
DisableProgramGroupPage=yes
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#WindowExeName}
AppMutex={#WindowMutex}
SetupIconFile=scarlet.ico
OutputDir=..\dist
OutputBaseFilename=Instalador-Traducao-PTBR-Mod-Titanfall2VR-v{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Fixed date on the installed files: the build time is not recorded.
TimeStampsInUTC=yes
TouchDate=2026-01-01
TouchTime=00:00

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Messages]
WelcomeLabel1=Bem-vindo ao instalador da [name]
ReadyLabel1=O instalador está pronto para instalar a [name] no seu computador.
PreparingDesc=O instalador está se preparando para instalar a [name] no seu computador.
InstallingLabel=Aguarde enquanto o instalador coloca a [name] no seu computador.
FinishedHeadingLabel=Instalação da [name] concluída
FinishedRestartLabel=Para completar a instalação da [name], o computador precisa reiniciar. Reiniciar agora?
FinishedRestartMessage=Para completar a instalação da [name], o computador precisa reiniciar.%n%nReiniciar agora?
PreviousInstallNotCompleted=A instalação ou remoção de um programa anterior não terminou. Reinicie o computador e abra o instalador de novo para completar a instalação da [name].
SetupAppRunningError=O programa da %1 está aberto.%n%nFeche o programa e clique em OK para continuar, ou em Cancelar para sair.
UninstallAppRunningError=O programa da %1 está aberto.%n%nFeche o programa e clique em OK para continuar, ou em Cancelar para sair.
ConfirmUninstall=Quer mesmo remover a %1? Os textos originais do jogo voltam para o lugar.
UninstallStatusLabel=Aguarde enquanto a %1 é removida do seu computador.
StatusUninstalling=Removendo a %1...
UninstalledAll=A %1 foi removida do seu computador.
UninstalledMost=A remoção da %1 terminou.%n%nAlguns itens não puderam ser removidos: eles podem ser apagados à mão.
UninstalledAndNeedsRestart=Para completar a remoção da %1, o computador precisa reiniciar.%n%nReiniciar agora?
WelcomeLabel2=Este assistente instala a tradução para português do Brasil dos textos do mod Titanfall 2 VR. Não inclui o jogo nem o mod.%n%nAntes de continuar, instale o mod pelo instalador do CircuitLord e feche o jogo.%n%nProjeto de fã, sem vínculo com EA, Respawn ou CircuitLord.
FinishedLabel=A tradução foi aplicada. Pode abrir o jogo.%n%nSe o mod for atualizado, abra "[name]" no menu Iniciar e reaplique a tradução. No mesmo programa você volta ao inglês e troca a pasta do jogo.

[CustomMessages]
GamePageTitle=Pasta do jogo
GamePageSubtitle=Onde está o Titanfall 2?
GamePageText=Escolha a pasta que tem o Titanfall2.exe. No EA app ou na Steam, a opção "Procurar arquivos locais" abre essa pasta.
GamePageLabel=Pasta do jogo:
ReadyGameLabel=Pasta do jogo:
ApplyingStatus=Aplicando a tradução no jogo. Se o Windows pedir permissão de administrador, confirme.
RestoringStatus=Devolvendo os textos originais do jogo. Se o Windows pedir permissão de administrador, confirme.
TranslationPendingLabel=O programa foi instalado, mas a tradução ainda não foi aplicada.%n%nResolva o aviso que apareceu e abra "{#AppName}" no menu Iniciar para traduzir.
NoGame=Não achei o Titanfall2.exe nesta pasta:%n%n%1
NoMod=O mod Titanfall 2 VR não está instalado nesta pasta:%n%n%1%n%nInstale o mod pelo instalador do CircuitLord e tente de novo:%n{#ModInstallerUrl}
TranslationFailed=O programa foi instalado, mas a tradução não foi aplicada.%n%n%1%n%nResolva o aviso e abra "{#AppName}" no menu Iniciar para traduzir.
RestoreFailed=Não consegui devolver os textos originais.%n%n%1%n%nSe o jogo já foi desinstalado, escolha Sim para remover só esta ferramenta. Com o jogo instalado, escolha Não: remover agora perderia a cópia dos originais.
ToolMissing=Não consegui abrir o programa da tradução: um antivírus pode ter levado o arquivo. Sem ele, os textos originais não voltam agora.%n%n%1%n%nEscolha Sim para tirar o programa da lista. A cópia dos originais continua guardada: para voltar ao inglês depois, instale de novo e desinstale.
UninstallStopped=A desinstalação não terminou e nada foi removido. Resolva o aviso e desinstale de novo.

[Files]
Source: "{#DistDir}\{#ExeName}"; DestDir: "{app}"; Flags: ignoreversion touch
Source: "{#DistDir}\{#WindowExeName}"; DestDir: "{app}"; Flags: ignoreversion touch
Source: "..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion touch

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#WindowExeName}"; WorkingDir: "{app}"

[Code]
const
  DetailLines = 8;

var
  GamePage: TInputDirWizardPage;
  ToolDidNotStart: Boolean;
  TranslationDidNotApply: Boolean;

function HasGame(const Dir: String): Boolean;
begin
  Result := (Dir <> '') and FileExists(AddBackslash(Dir) + 'Titanfall2.exe');
end;

function HasMod(const Dir: String): Boolean;
begin
  Result := (Dir <> '') and FileExists(AddBackslash(Dir) + '{#ModTokens}');
end;

{ Keeps the first folder with the game, and a later one only if it has the mod and the first does not. }
procedure Consider(const Dir: String; var Best: String);
begin
  if HasGame(Dir) and ((Best = '') or (HasMod(Dir) and not HasMod(Best))) then
    Best := Dir;
end;

procedure ConsiderSteam(var Best: String);
var
  Root, Library: String;
  Raw: AnsiString;
  Text: String;
  Start: Integer;
begin
  if not RegQueryStringValue(HKCU, 'Software\Valve\Steam', 'SteamPath', Root) then
    if not RegQueryStringValue(HKLM32, 'SOFTWARE\Valve\Steam', 'InstallPath', Root) then
      Exit;
  StringChangeEx(Root, '/', '\', True);
  Consider(AddBackslash(Root) + 'steamapps\common\Titanfall2', Best);
  if not LoadStringFromFile(AddBackslash(Root) + 'steamapps\libraryfolders.vdf', Raw) then
    Exit;
  Text := String(Raw);
  Start := Pos('"path"', Text);
  while Start > 0 do
  begin
    Delete(Text, 1, Start + 5);
    Delete(Text, 1, Pos('"', Text));
    Library := Copy(Text, 1, Pos('"', Text) - 1);
    Delete(Text, 1, Length(Library) + 1);
    StringChangeEx(Library, '\\', '\', True);
    Consider(AddBackslash(Library) + 'steamapps\common\Titanfall2', Best);
    Start := Pos('"path"', Text);
  end;
end;

{ The same places the tool itself looks at: EA app and Origin, Steam libraries, Xbox and default folders. }
function DetectGameDir(): String;
var
  Dir, Drive: String;
  Letter: Integer;
begin
  Result := '';
  if RegQueryStringValue(HKLM64, 'SOFTWARE\Respawn\Titanfall2', 'Install Dir', Dir) then
    Consider(Dir, Result);
  if RegQueryStringValue(HKLM32, 'SOFTWARE\Respawn\Titanfall2', 'Install Dir', Dir) then
    Consider(Dir, Result);
  ConsiderSteam(Result);
  for Letter := Ord('C') to Ord('Z') do
  begin
    Drive := Chr(Letter) + ':\';
    if DirExists(Drive) then
    begin
      Consider(Drive + 'Program Files\EA Games\Titanfall2', Result);
      Consider(Drive + 'EA Games\Titanfall2', Result);
      Consider(Drive + 'Program Files (x86)\Origin Games\Titanfall2', Result);
      Consider(Drive + 'XboxGames\Titanfall 2\Content', Result);
      Consider(Drive + 'XboxGames\Titanfall2\Content', Result);
      Consider(Drive + 'XboxGames\Titanfall 2', Result);
      Consider(Drive + 'XboxGames\Titanfall2', Result);
    end;
  end;
end;

{ A backslash right before the closing quote would escape it. }
function QuotedDir(const Dir: String): String;
begin
  Result := RemoveBackslashUnlessRoot(Dir);
  if Copy(Result, Length(Result), 1) = '\' then
    Result := Result + '\';
  Result := '"' + Result + '"';
end;

{ Runs the tool without a window. The last lines of what it says are the reason shown on failure. }
function RunTool(const Params: String; var Detail: String): Integer;
var
  Output: TExecOutput;
  I, First: Integer;
begin
  Detail := '';
  ToolDidNotStart := False;
  Log('Running the tool: ' + Params);
  if not ExecAndCaptureOutput(ExpandConstant('{app}\{#ExeName}'), Params, ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, Result, Output) then
  begin
    Detail := SysErrorMessage(Result);
    Log('Could not start it: ' + Detail);
    ToolDidNotStart := True;
    if Result = 0 then
      Result := -1;
    Exit;
  end;
  for I := 0 to GetArrayLength(Output.StdOut) - 1 do
    Log(Output.StdOut[I]);
  for I := 0 to GetArrayLength(Output.StdErr) - 1 do
    Log(Output.StdErr[I]);
  First := GetArrayLength(Output.StdOut) - DetailLines;
  if First < 0 then
    First := 0;
  for I := First to GetArrayLength(Output.StdOut) - 1 do
    if Trim(Output.StdOut[I]) <> '' then
      Detail := Detail + Trim(Output.StdOut[I]) + #13#10;
  for I := 0 to GetArrayLength(Output.StdErr) - 1 do
    if Trim(Output.StdErr[I]) <> '' then
      Detail := Detail + Trim(Output.StdErr[I]) + #13#10;
  Log('The tool exited with code ' + IntToStr(Result));
end;

procedure InitializeWizard();
begin
  GamePage := CreateInputDirPage(wpWelcome, CustomMessage('GamePageTitle'), CustomMessage('GamePageSubtitle'),
    CustomMessage('GamePageText'), False, '');
  GamePage.Add(CustomMessage('GamePageLabel'));
  GamePage.Values[0] := GetPreviousData('GameDir', '');
  if not HasGame(GamePage.Values[0]) then
    GamePage.Values[0] := DetectGameDir();
  { Unattended runs name the folder with /GAMEDIR=, since they see no page. }
  if ExpandConstant('{param:GAMEDIR|}') <> '' then
    GamePage.Values[0] := ExpandConstant('{param:GAMEDIR|}');
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  { With nobody to answer, a wrong folder is left to the tool, which fails with the reason. }
  if (CurPageID <> GamePage.ID) or WizardSilent() then
    Exit;
  if not HasGame(GamePage.Values[0]) then
  begin
    MsgBox(FmtMessage(CustomMessage('NoGame'), [GamePage.Values[0]]), mbError, MB_OK);
    Result := False;
  end
  else if not HasMod(GamePage.Values[0]) then
  begin
    MsgBox(FmtMessage(CustomMessage('NoMod'), [GamePage.Values[0]]), mbError, MB_OK);
    Result := False;
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := CustomMessage('ReadyGameLabel') + NewLine + Space + GamePage.Values[0];
end;

procedure RegisterPreviousData(PreviousDataKey: Integer);
begin
  SetPreviousData(PreviousDataKey, 'GameDir', GamePage.Values[0]);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Detail: String;
begin
  if CurStep <> ssPostInstall then
    Exit;
  { The backup of a previous version stays: it is the only copy of the originals. }
  RegDeleteKeyIncludingSubkeys(HKCU, '{#LegacyUninstallKey}');
  DelTree(ExpandConstant('{#LegacyCopyDir}'), True, True, True);
  WizardForm.StatusLabel.Caption := CustomMessage('ApplyingStatus');
  { /TOOLARGS= only exists for the tests, which translate an invented mod with an invented dictionary. }
  if RunTool('--wizard -Action Translate -NoColor -GameDir ' + QuotedDir(GamePage.Values[0]) + ' ' + ExpandConstant('{param:TOOLARGS|}'), Detail) <> 0 then
  begin
    TranslationDidNotApply := True;
    SuppressibleMsgBox(FmtMessage(CustomMessage('TranslationFailed'), [Detail]), mbError, MB_OK, IDOK);
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpFinished) and TranslationDidNotApply then
    WizardForm.FinishedLabel.Caption := CustomMessage('TranslationPendingLabel');
end;

function GetCustomSetupExitCode(): Integer;
begin
  Result := 0;
  if TranslationDidNotApply then
    Result := {#ExitTranslationFailed};
end;

{ Runs before anything is removed: a failure keeps the entry, the tool and the backup, so it can be run again. }
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Detail: String;
begin
  if CurUninstallStep <> usUninstall then
    Exit;
  UninstallProgressForm.StatusLabel.Caption := CustomMessage('RestoringStatus');
  if RunTool('--wizard --uninstall -NoColor ' + ExpandConstant('{param:TOOLARGS|}'), Detail) = 0 then
    Exit;
  { With the tool itself gone only the program leaves: its data folder, with the backup, stays. }
  if ToolDidNotStart then
  begin
    if SuppressibleMsgBox(FmtMessage(CustomMessage('ToolMissing'), [Detail]), mbError, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES then
      Exit;
  end
  else if SuppressibleMsgBox(FmtMessage(CustomMessage('RestoreFailed'), [Detail]), mbError, MB_YESNO or MB_DEFBUTTON2, IDNO) = IDYES then
    if RunTool('--wizard --uninstall --remove-anyway -NoColor', Detail) = 0 then
      Exit;
  SuppressibleMsgBox(CustomMessage('UninstallStopped'), mbError, MB_OK, IDOK);
  Abort;
end;
