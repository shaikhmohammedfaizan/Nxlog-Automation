; Inno Setup Script for NXLog Deployment
; Updated to support MSSQL Configuration prompts
; Save as nxlog-setup.iss and compile with Inno Setup Compiler

[Setup]
AppName=NXLog Auto Setup
AppVersion=2.0
DefaultDirName={pf}\NXLogSetup
OutputBaseFilename=NXLogSetup
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin

; -----------------------------
; FILES
; -----------------------------
[Files]
; PowerShell script converted to EXE (Ensure your converted EXE is named autov2_updated.exe or update here)
Source: "autov2_updated.exe"; DestDir: "{app}"; Flags: ignoreversion

; NXLog MSI installer
Source: "nxlog.msi"; DestDir: "{app}"; Flags: ignoreversion

; Config files
Source: "nxlog.conf"; DestDir: "{app}"; Flags: ignoreversion
Source: "nxlog.d\*"; DestDir: "{app}\nxlog.d"; Flags: recursesubdirs ignoreversion

Source: "LGPO.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "policy.csv"; DestDir: "{app}"; Flags: ignoreversion
Source: "Powershell.txt"; DestDir: "{app}"; Flags: ignoreversion

; -----------------------------
; RUN
; -----------------------------
[Run]
Filename: "{app}\autov2_updated.exe"; \
    Parameters: "-CCEIP ""{code:GetCCEIP}"" -SqlInstalled ""{code:GetSqlStatus}"" -SqlInstance ""{code:GetSqlInstance}"" -SqlAuthType ""{code:GetSqlAuthType}"" -SqlUser ""{code:GetSqlUser}"" -SqlPass ""{code:GetSqlPass}"""; \
    Flags: waituntilterminated

; -----------------------------
; ICONS
; -----------------------------
[Icons]
Name: "{group}\NXLog Auto Setup"; Filename: "{app}\autov2_updated.exe"

; -----------------------------
; CODE
; -----------------------------
[Code]
var
  CCEIPPage: TInputQueryWizardPage;
  SqlCheckPage: TInputOptionWizardPage;
  SqlInstancePage: TWizardPage;
  InstanceCombo: TComboBox;
  SelectedInstance: String;
  SqlAuthPage: TInputOptionWizardPage;
  SqlCredsPage: TInputQueryWizardPage;
  TempPS1, TempOut: String;
  PSContent: String;
  ResultCode, i: Integer;
  SL: TStringList;
  DevLabel, LinkLabel: TNewStaticText;
  
  procedure OpenLinks(Sender: TObject);
begin
  ShellExec('', 
    'https://www.linkedin.com/in/shaikh-mohammed-faizan-ar', 
    '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);

  ShellExec('', 
    'https://github.com/shaikhmohammedfaizan/Nxlog-Automation', 
    '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
end;

procedure InitializeWizard;
begin
  CCEIPPage := CreateInputQueryPage(wpSelectDir, 'Setup', 'CCE Configuration', 'Enter CCE IP:');
  CCEIPPage.Add('CCE IP:', False);

  SqlCheckPage := CreateInputOptionPage(CCEIPPage.ID, 'SQL Setup', 'SQL Server Detected?', 'Is MS SQL installed on this server?', True, False);
  SqlCheckPage.Add('Yes');
  SqlCheckPage.Add('No');
  SqlCheckPage.SelectedValueIndex := 1;

  // Create custom page instead of input box
SqlInstancePage := CreateCustomPage(SqlCheckPage.ID, 'SQL Details', 'Select SQL Instance');

// Create ComboBox
InstanceCombo := TComboBox.Create(SqlInstancePage);
InstanceCombo.Parent := SqlInstancePage.Surface;
InstanceCombo.Left := ScaleX(8);
InstanceCombo.Top := ScaleY(8);
InstanceCombo.Width := ScaleX(340);
InstanceCombo.Style := csDropDownList;

// --- PowerShell detection ---

TempPS1 := ExpandConstant('{tmp}\get_sql_instances.ps1');
TempOut := ExpandConstant('{tmp}\sqlinstances.txt');

PSContent :=
  'Get-Service MSSQL* | Where-Object {$_.Name -ne ''MSSQLFDLauncher''} | ForEach-Object {' + #13#10 +
  '  if ($_.Name -eq ''MSSQLSERVER'') {' + #13#10 +
  '    Write-Output $env:COMPUTERNAME' + #13#10 +
  '  } else {' + #13#10 +
  '    $n = $_.Name -replace ''^MSSQL\$'',''''; Write-Output ($env:COMPUTERNAME + ''\'' + $n)' + #13#10 +
  '  }' + #13#10 +
  '}';

SaveStringToFile(TempPS1, PSContent, False);

Exec('cmd.exe',
     '/C powershell -NoProfile -ExecutionPolicy Bypass -File "' + TempPS1 + '" > "' + TempOut + '"',
     '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

SL := TStringList.Create;
try
  if FileExists(TempOut) then
  begin
    SL.LoadFromFile(TempOut);
    for i := 0 to SL.Count - 1 do
      InstanceCombo.Items.Add(Trim(SL[i]));
    if InstanceCombo.Items.Count > 0 then
      InstanceCombo.ItemIndex := 0
    else
      InstanceCombo.Items.Add('No instances found');
  end
  else
  begin
    InstanceCombo.Items.Add('No instances found');
    InstanceCombo.ItemIndex := 0;
  end;
finally
  SL.Free;
end;

  SqlAuthPage := CreateInputOptionPage(SqlInstancePage.ID, 'SQL Authentication', 'Authentication Mode', 'Select how to connect to SQL Server:', True, False);
  SqlAuthPage.Add('Windows Authentication');
  SqlAuthPage.Add('SQL Server Authentication');
  SqlAuthPage.SelectedValueIndex := 0;

  SqlCredsPage := CreateInputQueryPage(SqlAuthPage.ID, 'SQL Credentials', 'Login Details', 'Enter your SQL credentials:');
  SqlCredsPage.Add('Username:', False);
  SqlCredsPage.Add('Password:', True);
  
  { --- Developed By Label --- }
  DevLabel := TNewStaticText.Create(WizardForm);
  DevLabel.Parent := WizardForm;
  DevLabel.Caption := 'Developed By Mohammed Faizan';
  DevLabel.AutoSize := True;
  DevLabel.Font.Style := [fsBold];
  DevLabel.Font.Color := clWindowText;

  // Horizontal Alignment: ScaleX(40) matches the input fields above
  DevLabel.Left := ScaleX(50); 
  
  // Vertical Alignment: Aligns the first line with the top of the Next button
  DevLabel.Top := WizardForm.NextButton.Top;

  { --- Links --- }
  LinkLabel := TNewStaticText.Create(WizardForm);
  LinkLabel.Parent := WizardForm;
  LinkLabel.Caption := 'LinkedIn  |  GitHub';
  LinkLabel.AutoSize := True;
  LinkLabel.Cursor := crHand;
  LinkLabel.Font.Color := clBlue;
  LinkLabel.Font.Style := [fsUnderline];

  // Match horizontal alignment
  LinkLabel.Left := ScaleX(50); 
  
  // Vertical Alignment: Places links directly under the name, still inline with the button area
  LinkLabel.Top := DevLabel.Top + DevLabel.Height + ScaleY(2);

  LinkLabel.OnClick := @OpenLinks;
end;

function GetCCEIP(V: string): string; begin Result := CCEIPPage.Values[0]; end;
function GetSqlStatus(V: string): string; begin if SqlCheckPage.SelectedValueIndex = 0 then Result := 'yes' else Result := 'no'; end;
function GetSqlInstance(V: string): string; begin if SqlCheckPage.SelectedValueIndex = 0 then Result := InstanceCombo.Text else Result := ''; end;
function GetSqlAuthType(V: string): string; begin if SqlAuthPage.SelectedValueIndex = 1 then Result := 'sql' else Result := 'windows'; end;
function GetSqlUser(V: string): string; begin Result := SqlCredsPage.Values[0]; end;
function GetSqlPass(V: string): string; begin Result := SqlCredsPage.Values[1]; end;

function CheckSqlInstance(Instance: String; AuthType: String; User: String; Pass: String): Boolean;
var
  ADOConn: Variant;
  ConnStr: String;
begin
  Result := True;
  try
    if AuthType = 'sql' then
      ConnStr := 'Provider=SQLOLEDB;Data Source=' + Instance + ';Initial Catalog=master;User ID=' + User + ';Password=' + Pass + ';Connect Timeout=5;'
    else
      ConnStr := 'Provider=SQLOLEDB;Data Source=' + Instance + ';Initial Catalog=master;Integrated Security=SSPI;Connect Timeout=5;';
    
    ADOConn := CreateOleObject('ADODB.Connection');
    ADOConn.Open(ConnStr);
    ADOConn.Close;
  except
    MsgBox('SQL Connection Failed: ' + GetExceptionMessage, mbError, MB_OK);
    Result := False;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = CCEIPPage.ID then begin
    if CCEIPPage.Values[0] = '' then begin
      MsgBox('CCE IP is required.', mbError, MB_OK);
      Result := False;
    end;
  end
  else if (CurPageID = SqlCredsPage.ID) and (SqlCheckPage.SelectedValueIndex = 0) then begin
    Result := CheckSqlInstance(InstanceCombo.Text, GetSqlAuthType(''), SqlCredsPage.Values[0], SqlCredsPage.Values[1]);
  end
  else if (CurPageID = SqlAuthPage.ID) and (SqlCheckPage.SelectedValueIndex = 0) and (SqlAuthPage.SelectedValueIndex = 0) then begin
    Result := CheckSqlInstance(InstanceCombo.Text, 'windows', '', '');
  end;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if (SqlCheckPage.SelectedValueIndex <> 0) and 
     ((PageID = SqlInstancePage.ID) or (PageID = SqlAuthPage.ID) or (PageID = SqlCredsPage.ID)) then
    Result := True
  else if (PageID = SqlCredsPage.ID) and (SqlAuthPage.SelectedValueIndex = 0) then
    Result := True;
end;