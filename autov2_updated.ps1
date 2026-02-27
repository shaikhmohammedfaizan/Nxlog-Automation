param (
    [Parameter(Mandatory=$false)]
    [string]$CCEIP,
    [Parameter(Mandatory=$false)]
    [string]$SqlInstalled = "no",
    [Parameter(Mandatory=$false)]
    [string]$SqlInstance = "",
    [Parameter(Mandatory=$false)]
    [string]$SqlAuthType = "windows", # "windows" or "sql" 
    [Parameter(Mandatory=$false)]
    [string]$SqlUser = "",
    [Parameter(Mandatory=$false)]
    [string]$SqlPass = ""
)

Write-Host "CCE IP received from installer: $CCEIP"
Write-Host "CCE IP received: $CCEIP"

# VARIABLES
$curDir = (Get-Location).Path
$nxlogInstallDir = "C:\Program Files\nxlog"
$nxlogConfDir = "$nxlogInstallDir\conf"
$nxlogDDir = "$nxlogConfDir\nxlog.d"
$nxlogTemplateDir = "$curDir\nxlog.d\"
$nxlogTargetDir   = "C:\Program Files\nxlog\conf\nxlog.d"
$sqlInstalledValue = if ($null -eq $SqlInstalled) { "" } else { $SqlInstalled }
$isSqlInstalled = $sqlInstalledValue.Trim().ToLowerInvariant() -eq "yes"

# 1. Ensure required NXLog directories exist
try {
    New-Item -Path $nxlogDDir -ItemType Directory -Force | Out-Null
    Write-Host "Step 1: NXLog subdirectory ensured (ok)" -ForegroundColor Green
} catch {
    Write-Host "Step 1: Failed to create NXLog subdirectory: $_" -ForegroundColor Red
}

# 2. Apply LGPO if present
if ((Test-Path "$curDir\LGPO.exe") -and (Test-Path "$curDir\policy.csv")) {
    try {
        & "$curDir\LGPO.exe" /ac "$curDir\policy.csv" 
        Write-Host "Step 2: LGPO policy applied successfully." -ForegroundColor Green
    } catch {
        Write-Host "Step 2: Failed to apply LGPO policy: $_" -ForegroundColor Red
    }
} else {
    Write-Host "Step 2: LGPO.exe or policy.csv not found. Skipping LGPO policy application." -ForegroundColor Yellow
}

.\lgpo.exe /t Powershell.txt

# 3. Install NXLog if not already present, using installer in current folder
if (!(Test-Path "$nxlogInstallDir\nxlog.exe") -and (Test-Path "$curDir\nxlog.msi")) {
    try {
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$curDir\nxlog.msi`" /quiet" -Wait
        Write-Host "Step 3: NXLog installed successfully." -ForegroundColor Green
    } catch {
        Write-Host "Step 3: Failed to install NXLog: $_" -ForegroundColor Red
    }
} elseif (Test-Path "$nxlogInstallDir\nxlog.exe") {
    Write-Host "Step 3: NXLog already installed. Removing Old Config Files." -ForegroundColor Yellow
    rm "$nxlogInstallDir\conf\nxlog.d\*"
} else {
    Write-Host "Step 3: NXLog installer not found. Skipping installation." -ForegroundColor Yellow
}

# 4. Copy nxlog.conf from current folder
if (Test-Path "$curDir\nxlog.conf") {
    try {
        Copy-Item "$curDir\nxlog.conf" "$nxlogConfDir\nxlog.conf" -Force
        Write-Host "Step 4: nxlog.conf copied successfully." -ForegroundColor Green
    } catch {
        Write-Host "Step 4: Failed to copy nxlog.conf: $_" -ForegroundColor Red
    }
} else {
    Write-Host "Step 4: nxlog.conf not found in current directory. Skipping copy." -ForegroundColor Yellow
}

# 5. MSSQL CONFIGURATION (FIXED T-SQL SYNTAX)
if ($isSqlInstalled) {
    if (-not $SqlInstance) {
        Write-Host "No SQL instance provided. Skipping." -ForegroundColor Yellow
    } else {
        Write-Host "Checking MSSQL Version for: $SqlInstance using $SqlAuthType auth" -ForegroundColor Cyan

        $VersionQuery = @"
SET NOCOUNT ON;
SELECT  
    CAST(PARSENAME(CONVERT(VARCHAR(32), SERVERPROPERTY('ProductVersion')), 4) AS INT) AS MajorVersion,
    CAST(SERVERPROPERTY('Edition') AS NVARCHAR(200)) AS Edition;
"@

    $VersionFile = Join-Path $env:TEMP "SeceonVersionCheck.sql"
    $VersionQuery | Out-File -FilePath $VersionFile -Encoding UTF8

    if (Get-Command "sqlcmd" -ErrorAction SilentlyContinue) {

        if ($SqlAuthType -eq "sql") {
            $VersionOutput = sqlcmd -S "$SqlInstance" -U "$SqlUser" -P "$SqlPass" -C -i "$VersionFile" -h -1 -W
        }
        else {
            $VersionOutput = sqlcmd -S "$SqlInstance" -E -C -i "$VersionFile" -h -1 -W
        }

        $VersionParts = $VersionOutput -split "\s+"
        $MajorVersion = [int]$VersionParts[0]
        $Edition = $VersionParts[1..($VersionParts.Length-1)] -join " "

        Write-Host "Detected Version: $MajorVersion | Edition: $Edition" -ForegroundColor Yellow
      
        if ($MajorVersion -ge 11 -and $Edition -notmatch "Express") {

            Write-Host "SQL Audit Supported. Applying full audit configuration..." -ForegroundColor Green

        $TSQL_Config = @"
USE [master];
GO

-- 1. Enable Login Auditing
EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'AuditLevel', REG_DWORD, 3;
GO

-- 2. Create Server Audit if not exists
IF NOT EXISTS (SELECT * FROM sys.server_audits WHERE name = 'Seceon_Audit')
BEGIN
    CREATE SERVER AUDIT [Seceon_Audit] TO APPLICATION_LOG WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE);
END
GO

-- 3. Ensure the Audit is ENABLED before creating specification (prevents some permission errors)
ALTER SERVER AUDIT [Seceon_Audit] WITH (STATE = ON);
GO

-- 4. Create Server Audit Specification if not exists
IF NOT EXISTS (SELECT * FROM sys.server_audit_specifications WHERE name = 'Seceon_Audit_Specification')
BEGIN
    CREATE SERVER AUDIT SPECIFICATION [Seceon_Audit_Specification]
    FOR SERVER AUDIT [Seceon_Audit]
    ADD (SCHEMA_OBJECT_ACCESS_GROUP),
    ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP),
    ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP),
    ADD (DATABASE_PERMISSION_CHANGE_GROUP),
    ADD (SERVER_OBJECT_PERMISSION_CHANGE_GROUP),
    ADD (FAILED_LOGIN_GROUP),
    ADD (SUCCESSFUL_LOGIN_GROUP),
    ADD (LOGOUT_GROUP),
    ADD (DATABASE_PRINCIPAL_CHANGE_GROUP),
    ADD (SCHEMA_OBJECT_CHANGE_GROUP),
    ADD (SERVER_PRINCIPAL_CHANGE_GROUP),
    ADD (SERVER_STATE_CHANGE_GROUP);
END
GO

-- 5. Enable the Specification
ALTER SERVER AUDIT SPECIFICATION [Seceon_Audit_Specification] WITH (STATE = ON);
GO
"@
        
}
        else {

            Write-Host "SQL Audit NOT supported. Applying fallback (Login Auditing Only)..." -ForegroundColor Magenta

            $TSQL_Config = @"
USE [master];

EXEC xp_instance_regwrite 
    N'HKEY_LOCAL_MACHINE',
    N'Software\Microsoft\MSSQLServer\MSSQLServer',
    N'AuditLevel',
    REG_DWORD,
    3;
"@
        }

        $TSQLFile = Join-Path $env:TEMP "SeceonAuditConfig.sql"
        $TSQL_Config | Out-File -FilePath $TSQLFile -Encoding UTF8

        if (Get-Command "sqlcmd" -ErrorAction SilentlyContinue) {
            if ($SqlAuthType -eq "sql") {
                & sqlcmd -S "$SqlInstance" -U "$SqlUser" -P "$SqlPass" -C -i "$TSQLFile"
            } else {
                & sqlcmd -S "$SqlInstance" -E -C -i "$TSQLFile"
            }
            Write-Host "MSSQL configuration applied successfully." -ForegroundColor Green
        } else {
            Write-Host "sqlcmd utility not found." -ForegroundColor Yellow
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Host "MSSQL configuration applied successfully." -ForegroundColor Green
        }
        else {
            Write-Host "Error occurred while applying configuration." -ForegroundColor Red
        }

    }
    else {
        Write-Host "sqlcmd utility not found." -ForegroundColor Yellow
    }
}
    if ($isSqlInstalled) {
    $src = Join-Path $nxlogTemplateDir "mssql.conf"
    $dst = Join-Path $nxlogTargetDir   "mssql.conf"
    if (Test-Path $src) {
        Copy-Item $src $dst -Force
        Write-Host "Mssql NXLog config copied" -ForegroundColor Green
        (Get-Content $src) `
            -creplace 'CCEIP', $CCEIP |
            Set-Content $dst
    }
    else {
        Write-Host "Template not found: $conf" -ForegroundColor Yellow
    }
}
    else {
        $dst = Join-Path $nxlogTargetDir "mssql.conf"
        if (Test-Path $dst) {
            Remove-Item $dst -Force
            Write-Host "SQL not installed; removed existing mssql.conf." -ForegroundColor Yellow
        } else {
            Write-Host "SQL not installed; mssql.conf not deployed." -ForegroundColor Yellow
        }
    }
    
    }



# 6. DYNAMIC SERVICE DETECTION AND CONFIG UPDATE
$serviceMap = @{
    "Oracle"   = @(
        "OracleService*",
        "OracleOraDB*",
        "OracleJobScheduler*",
        "OracleVssWriter*",
        "*TNSListener*"
    )
    "IIS"      = @("W3SVC", "World Wide Web Publishing Service")
    "DNS"      = @("DNS Server")
    "DHCP"     = @("DHCP Server")
    "Exchange" = @("MSExchange*")
    "Apache"   = @("*Tomcat*")
}



function Update-NxlogConf {
    param (
        [string]$Service,
        [string]$LogPath
    )

    $template = Join-Path $nxlogTemplateDir "$Service.conf"
    $target   = Join-Path $nxlogTargetDir   "$Service.conf"

    if ((Test-Path $template) -and $LogPath -and $CCEIP) {
        (Get-Content $template) `
            -creplace 'LOGPA', $LogPath `
            -creplace 'CCEIP', $CCEIP |
            Set-Content $target
        Write-Host "NXLog config deployed for $Service" -ForegroundColor Green
    }
    else {
        Write-Host "Skipped $Service (template missing, LogPath empty, or CCEIP missing)" -ForegroundColor Yellow
    }
}

# Always copy mandatory NXLog configs
$mandatoryConfs = @("ps.conf")

if (Test-Path "$curDir\nxlog.conf") {
    (Get-Content "$curDir\nxlog.conf") `
        -creplace 'CCEIP', $CCEIP |
        Set-Content "$nxlogConfDir\nxlog.conf"
}

foreach ($conf in $mandatoryConfs) {
    $src = Join-Path $nxlogTemplateDir $conf
    $dst = Join-Path $nxlogTargetDir   $conf
    if (Test-Path $src) {
        Copy-Item $src $dst -Force
        Write-Host "Mandatory NXLog config copied: $conf" -ForegroundColor Green
        (Get-Content $src) `
            -creplace 'CCEIP', $CCEIP |
            Set-Content $dst
    }
    else {
        Write-Host "Template not found: $conf" -ForegroundColor Yellow
    }
}

$allServices = Get-Service
foreach ($service in $serviceMap.Keys) {
    foreach ($pattern in $serviceMap[$service]) {
        $match = $allServices | Where-Object {
            $_.Name -like $pattern -or $_.DisplayName -like $pattern
        }
        if ($match) {
            Write-Host "`n[$service] detected" -ForegroundColor Cyan
            switch ($service) {
                "dns" {
                    $LogPath = "C:\Windows\System32\dns\*.log"
                    Set-DnsServerDiagnostics `
-Udp $true `
-Tcp $true `
-SendPackets $true `
-ReceivePackets $false `
-Answers $true `
-Queries $false `
-Updates $true `
-Notifications $false `
-UnmatchedResponse $false `
-EnableLoggingToFile $true
                    Set-DnsServerDiagnostics -LogFilePath "C:\Windows\System32\dns\dns.log"
                    Update-NxlogConf -Service "DNS" -LogPath $LogPath
                }
                "DHCP" {
                    Set-DhcpServerAuditLog -Enable $true
                    $logPath = (Get-DhcpServerAuditLog).Path + "\DhcpSrvLog*"
                    Update-NxlogConf -Service "DHCP" -LogPath $logPath
                }
                "IIS" {
                    Import-Module WebAdministration
                    $allFields = "Date,Time,ClientIP,UserName,SiteName,ComputerName,ServerIP,Method,UriStem,UriQuery,HttpStatus,Win32Status,BytesSent,BytesRecv,TimeTaken,ServerPort,UserAgent,Cookie,Referer,ProtocolVersion,Host,HttpSubStatus"
                    Set-WebConfigurationProperty `
                        -Filter "/system.applicationHost/sites/siteDefaults/logFile" `
                        -Name "logExtFileFlags" `
                        -Value $allFields
                    $logPath = [Environment]::ExpandEnvironmentVariables(
    (Get-ItemProperty "IIS:\Sites\Default Web Site").logFile.directory
) + "\W3SVC*\u_ex*"
                    Update-NxlogConf -Service "IIS" -LogPath $logPath
                }
                "Exchange" {
                    try {
                        # Attempt to load the Exchange Snap-in
                        Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn -ErrorAction Stop
                        # Attempt to get the server identity and specific log path
                        $iden = (Get-TransportService -ErrorAction Stop | Select-Object -First 1).Name 
                        $logPath = (Get-TransportService -Identity "$iden" -ErrorAction Stop).MessageTrackingLogPath.PathName + "\*"
                    }
                    catch {
                        # Fallback logic if the Snap-in or Get-TransportService fails
                        Write-Warning "Exchange cmdlets failed or not found. Falling back to environment variable path."
                        $logPath = Join-Path $env:ExchangeInstallPath "TransportRoles\Logs\MessageTracking\*"
                    }
                    finally {
                        # Execute the update regardless of which path was chosen
                        Update-NxlogConf -Service "Exchange" -LogPath $logPath
                    }
                }
                "Apache" {
                    $TomcatPath = Get-ChildItem "HKLM:\Software\Apache Software Foundation" -Recurse | 
                    Get-ItemProperty | 
                    Where-Object { $_.InstallPath } | 
                    Select-Object -First 1 -ExpandProperty InstallPath
                    $logPath = Join-Path $TomcatPath "logs\*"
                    Update-NxlogConf -Service "Apache" -LogPath $logPath
                }
                "Oracle" {
                    $OracleBase = $env:ORACLE_BASE

if (-not $OracleBase) {

    $OracleKeys = Get-ChildItem "HKLM:\SOFTWARE\ORACLE" -ErrorAction SilentlyContinue

    foreach ($key in $OracleKeys) {
        $props = Get-ItemProperty $key.PSPath -ErrorAction SilentlyContinue

        if ($props.PSObject.Properties.Name -contains "ORACLE_BASE") {
            $OracleBase = $props.ORACLE_BASE
            break
        }
    }
}

if ($OracleBase) {

    $TraceDir = Get-ChildItem -Path "$OracleBase\diag\rdbms" -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq "trace" } |
        Select-Object -First 1 -ExpandProperty FullName

    if ($TraceDir) {
        $LogPath = "$TraceDir\*"
        Update-NxlogConf -Service "Oracle" -LogPath $LogPath
    }
}
                }
            }
            break
        }
    }
}

$nxlogConfPath = "$nxlogConfDir\nxlog.conf"
if (Test-Path $nxlogConfPath) {
    try {
        $targetLine = 12
        $includeLines = Get-ChildItem "$nxlogDDir\*.conf" | ForEach-Object { "include $($_.FullName)" }
        $content = Get-Content $nxlogConfPath
        $inserted = $false
        foreach ($line in $includeLines) {
            if ($content -notcontains $line) {
                $content = $content[0..($targetLine - 2)] + $includeLines + $content[($targetLine - 1)..($content.Length - 1)]
                Set-Content -Path $nxlogConfPath -Value ($content -join "`r`n") -Encoding Default
                Write-Host "Step 9: Inserted include lines into nxlog.conf." -ForegroundColor Green
                $inserted = $true
                break
            }
        }
        if (-not $inserted) {
            Write-Host "Step 9: Include lines already present. No changes made." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Step 9: Failed to insert include lines into nxlog.conf: $_" -ForegroundColor Red
    }
}

# 11. Start/restart nxlog service
try {
    if (Get-Service -Name nxlog -ErrorAction SilentlyContinue) {
        Restart-Service -Name nxlog
        Write-Host "Step 11: NXLog service restarted." -ForegroundColor Green
    } else {
        Start-Service -Name nxlog
        Write-Host "Step 11: NXLog service started." -ForegroundColor Green
    }
    Set-Service -Name nxlog -StartupType Automatic
    Write-Host "Step 11: NXLog service set to start automatically." -ForegroundColor Green
} catch {
    Write-Host "Step 11: Error managing the nxlog service: $_" -ForegroundColor Red
}
