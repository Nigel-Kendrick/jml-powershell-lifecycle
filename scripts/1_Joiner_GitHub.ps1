# ============================================================
# 1_Joiner.ps1 - Automated New Hire Provisioning
# NigelTech JML Lab | IGA Portfolio Project
# ============================================================

# --- Configuration ---
$csvPath    = 'C:\JML_Lab\HR_Feed.csv'
$logPath    = 'C:\JML_Lab\Logs\JML_Log.txt'
$domain     = 'nigeltech.onmicrosoft.com'
$licGroup   = 'GRP-M365-E5-Licensed'
$licGroupOU = 'OU=Security-Groups,OU=Groups,DC=nigeltech,DC=local'
$tempPass   = ConvertTo-SecureString 'Welcome1!' -AsPlainText -Force

# --- Department to OU map ---
$ouMap = @{
    'IT'      = 'OU=IT,OU=Departments,DC=nigeltech,DC=local'
    'Finance' = 'OU=Finance,OU=Departments,DC=nigeltech,DC=local'
    'HR'      = 'OU=HR,OU=Departments,DC=nigeltech,DC=local'
    'Sales'   = 'OU=Sales,OU=Departments,DC=nigeltech,DC=local'
}

# --- Department to Security Group map ---
$groupMap = @{
    'IT'      = 'GRP-IT-Staff'
    'Finance' = 'GRP-Finance-Staff'
    'HR'      = 'GRP-HR-Staff'
    'Sales'   = 'GRP-Sales-Staff'
}

New-Item -ItemType Directory -Path 'C:\JML_Lab\Logs' -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | JOINER | $Message"
    Add-Content -Path $logPath -Value $entry
    Write-Host $entry
}

# -----------------------------------------------------------
# Generates unique SamAccountName: first initial + lastname
# e.g. Steven Bell -> sbell
# If taken -> sbell1, sbell2, etc.
# -----------------------------------------------------------
function Get-UniqueSamAccountName {
    param([string]$FirstName, [string]$LastName)
    $base = ($FirstName.Substring(0,1) + $LastName).ToLower() -replace '[^a-z]', ''
    $existing = Get-ADUser -Filter "SamAccountName -eq '$base'" -ErrorAction SilentlyContinue
    if (-not $existing) { return $base }
    $counter = 1
    do {
        $candidate = "$base$counter"
        $existing  = Get-ADUser -Filter "SamAccountName -eq '$candidate'" -ErrorAction SilentlyContinue
        if (-not $existing) { return $candidate }
        $counter++
    } while ($true)
}

Write-Log '--- Joiner run started ---'

$employees = Import-Csv $csvPath | Where-Object { $_.Action -eq 'Joiner' }

foreach ($emp in $employees) {
    $displayName = "$($emp.FirstName) $($emp.LastName)"
    $targetOU    = $ouMap[$emp.Department]
    $group       = $groupMap[$emp.Department]

    Write-Log "Processing Joiner: $displayName | EmpID: $($emp.EmployeeID) | Dept: $($emp.Department)"

    if (-not $targetOU) {
        Write-Log "ERROR: No OU mapping for department '$($emp.Department)' — skipping $displayName"
        continue
    }

    # --- Check: EmployeeID already exists ---
    $existingEmpID = Get-ADUser -Filter "EmployeeID -eq '$($emp.EmployeeID)'" `
                                -Properties EmployeeID -ErrorAction SilentlyContinue
    if ($existingEmpID) {
        Write-Log "SKIPPED: EmployeeID '$($emp.EmployeeID)' already exists (account: $($existingEmpID.SamAccountName))"
        continue
    }

    # --- Generate unique SamAccountName ---
    $samAccount = Get-UniqueSamAccountName -FirstName $emp.FirstName -LastName $emp.LastName
    $upn        = "$samAccount@$domain"

    # --- Check: UPN already exists ---
    $existingUPN = Get-ADUser -Filter "UserPrincipalName -eq '$upn'" -ErrorAction SilentlyContinue
    if ($existingUPN) {
        Write-Log "SKIPPED: UPN '$upn' already exists — skipping $displayName"
        continue
    }

    Write-Log "INFO: SamAccountName assigned as '$samAccount' | UPN: $upn"

    try {
        New-ADUser -Name $displayName `
                   -GivenName $emp.FirstName `
                   -Surname $emp.LastName `
                   -SamAccountName $samAccount `
                   -UserPrincipalName $upn `
                   -Department $emp.Department `
                   -Title $emp.JobTitle `
                   -Manager $emp.Manager `
                   -EmployeeID $emp.EmployeeID `
                   -AccountPassword $tempPass `
                   -ChangePasswordAtLogon $true `
                   -Enabled $true `
                   -Path $targetOU

        Write-Log "SUCCESS: AD account created — $displayName | SAM: $samAccount | OU: $targetOU"

        # --- Add to department security group ---
        $groupExists = Get-ADGroup -Filter "Name -eq '$group'" -ErrorAction SilentlyContinue
        if ($groupExists) {
            Add-ADGroupMember -Identity $group -Members $samAccount
            Write-Log "SUCCESS: Added $samAccount to $group"
        } else {
            Write-Log "WARNING: Group '$group' not found — skipping group assignment"
        }

        # --- Add to M365 E5 license group ---
        $licExists = Get-ADGroup -Filter "Name -eq '$licGroup'" `
                                 -SearchBase $licGroupOU -ErrorAction SilentlyContinue
        if ($licExists) {
            Add-ADGroupMember -Identity $licExists.DistinguishedName -Members $samAccount
            Write-Log "SUCCESS: Added $samAccount to $licGroup (license pending Entra sync)"
        } else {
            Write-Log "WARNING: '$licGroup' not found at $licGroupOU — skipping license group"
        }

    } catch {
        Write-Log "ERROR: Failed creating $displayName | $_"
    }
}

Write-Log '--- Joiner run complete ---'

Write-Host "`nJML Joiner accounts:" -ForegroundColor Cyan
Get-ADUser -Filter * -SearchBase 'OU=Departments,DC=nigeltech,DC=local' `
    -Properties Department, Title, EmployeeID, Enabled |
    Where-Object { $_.EmployeeID -in @('EMP1001','EMP1002','EMP1003') } |
    Select-Object Name, SamAccountName, UserPrincipalName, Department, Title, EmployeeID, Enabled |
    Format-Table -AutoSize
