# ============================================================
# 0_Create_Managers.ps1 - Pre-flight: Ensure Manager Accounts Exist
# Project: IGA Portfolio - Joiner/Mover/Leaver (JML) Lab
# ============================================================

# --- CONFIGURATION (Update these for your environment) ---
$domain     = 'example.com'  # Replaces nigeltech.onmicrosoft.com
$rootOU     = 'DC=example,DC=local'
$logPath    = 'C:\JML_Lab\Logs\Preflight_Log.txt'
$licGroup   = 'GRP-M365-E5-Licensed'
$licGroupOU = "OU=Security-Groups,OU=Groups,$rootOU"

# Use a parameter for the password so it isn't hardcoded in the script
param(
    [Parameter(Mandatory=$true)]
    [SecureString]$TempPassword
)

$ouMap = @{
    'IT'      = "OU=IT,OU=Departments,$rootOU"
    'Finance' = "OU=Finance,OU=Departments,$rootOU"
    'HR'      = "OU=HR,OU=Departments,$rootOU"
    'Sales'   = "OU=Sales,OU=Departments,$rootOU"
}

$managers = @(
    @{ SamAccountName = 'mthomas'; FirstName = 'Michael'; LastName = 'Thomas'; Department = 'IT';      JobTitle = 'IT Manager' },
    @{ SamAccountName = 'jsmith';  FirstName = 'Jane';    LastName = 'Smith';  Department = 'Finance'; JobTitle = 'Financial Analyst' },
    @{ SamAccountName = 'kdavis';  FirstName = 'Karen';   LastName = 'Davis';  Department = 'Finance'; JobTitle = 'Finance Manager' },
    @{ SamAccountName = 'ltaylor'; FirstName = 'Lisa';    LastName = 'Taylor'; Department = 'HR';      JobTitle = 'HR Manager' },
    @{ SamAccountName = 'rbrown';  FirstName = 'Robert';  LastName = 'Brown';  Department = 'Sales';   JobTitle = 'Sales Manager' }
)

# --- EXECUTION ---
New-Item -ItemType Directory -Path (Split-Path $logPath) -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | PREFLIGHT | $Message"
    Add-Content -Path $logPath -Value $entry
    Write-Host $entry
}

Write-Log '--- Manager pre-flight check started ---'

foreach ($mgr in $managers) {
    $existing = Get-ADUser -Filter "SamAccountName -eq '$($mgr.SamAccountName)'" -ErrorAction SilentlyContinue

    if ($existing) {
        Write-Log "EXISTS: $($mgr.SamAccountName) already in AD — skipping"
        continue
    }

    $displayName = "$($mgr.FirstName) $($mgr.LastName)"
    $upn         = "$($mgr.SamAccountName)@$domain"
    $targetOU    = $ouMap[$mgr.Department]

    try {
        New-ADUser -Name $displayName `
                   -GivenName $mgr.FirstName `
                   -Surname $mgr.LastName `
                   -SamAccountName $mgr.SamAccountName `
                   -UserPrincipalName $upn `
                   -Department $mgr.Department `
                   -Title $mgr.JobTitle `
                   -AccountPassword $TempPassword `
                   -ChangePasswordAtLogon $true `
                   -Enabled $true `
                   -Path $targetOU

        Write-Log "CREATED: $displayName ($($mgr.SamAccountName))"

        # Licensing Group Logic
        if (Get-ADGroup -Filter "Name -eq '$licGroup'" -SearchBase $licGroupOU) {
            Add-ADGroupMember -Identity $licGroup -Members $mgr.SamAccountName
            Write-Log "SUCCESS: Added to $licGroup"
        }
    } catch {
        Write-Log "ERROR: Failed to create $($mgr.SamAccountName) | $_"
    }
}