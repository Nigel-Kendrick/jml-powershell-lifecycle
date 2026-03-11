# ============================================================
# 0_Create_Mover_Leaver.ps1 - Pre-flight: Create Simone Ford & Ray Chen
# NigelTech JML Lab | IGA Portfolio Project
# ============================================================

param(
    [Parameter(Mandatory=$false)]
    $Password = 'Welcome1!'
)

# --- Configuration ---
$logPath    = 'C:\JML_Lab\Logs\JML_Log.txt'
$domain     = 'example.onmicrosoft.com' # Sanitized tenant
$licGroup   = 'GRP-M365-E5-Licensed'
$licGroupOU = 'OU=Security-Groups,OU=Groups,DC=nigeltech,DC=local'
$tempPass   = ConvertTo-SecureString $Password -AsPlainText -Force

$ouMap = @{
    'IT'      = 'OU=IT,OU=Departments,DC=nigeltech,DC=local'
    'Finance' = 'OU=Finance,OU=Departments,DC=nigeltech,DC=local'
    'HR'      = 'OU=HR,OU=Departments,DC=nigeltech,DC=local'
    'Sales'   = 'OU=Sales,OU=Departments,DC=nigeltech,DC=local'
}

$groupMap = @{
    'IT'      = 'GRP-IT-Staff'
    'Finance' = 'GRP-Finance-Staff'
    'HR'      = 'GRP-HR-Staff'
    'Sales'   = 'GRP-Sales-Staff'
}

# EMP1004 = Mover (Simone Ford - starts in IT, moves to Finance)
# EMP1005 = Leaver (Ray Chen - Sales, will be offboarded)
$accounts = @(
    @{
        EmployeeID = 'EMP1004'
        FirstName  = 'Simone'
        LastName   = 'Ford'
        Department = 'IT'
        JobTitle   = 'Help Desk Technician'
        Manager    = 'mthomas'
    },
    @{
        EmployeeID = 'EMP1005'
        FirstName  = 'Ray'
        LastName   = 'Chen'
        Department = 'Sales'
        JobTitle   = 'Account Executive'
        Manager    = 'rbrown'
    }
)

New-Item -ItemType Directory -Path 'C:\JML_Lab\Logs' -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | PREFLIGHT | $Message"
    Add-Content -Path $logPath -Value $entry
    Write-Host $entry
}

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

Write-Log '--- Mover/Leaver pre-flight started ---'

foreach ($emp in $accounts) {
    $displayName = "$($emp.FirstName) $($emp.LastName)"
    Write-Log "Checking: $displayName | EmpID: $($emp.EmployeeID)"

    $existingEmpID = Get-ADUser -Filter "EmployeeID -eq '$($emp.EmployeeID)'" `
                                -Properties EmployeeID -ErrorAction SilentlyContinue
    if ($existingEmpID) {
        Write-Log "EXISTS: $displayName already in AD as '$($existingEmpID.SamAccountName)' — skipping"
        continue
    }

    $samAccount = Get-UniqueSamAccountName -FirstName $emp.FirstName -LastName $emp.LastName
    $upn        = "$samAccount@$domain"
    $targetOU   = $ouMap[$emp.Department]
    $group      = $groupMap[$emp.Department]

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

        Write-Log "SUCCESS: Created $displayName | SAM: $samAccount | UPN: $upn | OU: $targetOU"

        $groupExists = Get-ADGroup -Filter "Name -eq '$group'" -ErrorAction SilentlyContinue
        if ($groupExists) {
            Add-ADGroupMember -Identity $group -Members $samAccount
            Write-Log "SUCCESS: Added $samAccount to $group"
        }

        $licExists = Get-ADGroup -Filter "Name -eq '$licGroup'" `
                                 -SearchBase $licGroupOU -ErrorAction SilentlyContinue
        if ($licExists) {
            Add-ADGroupMember -Identity $licExists.DistinguishedName -Members $samAccount
            Write-Log "SUCCESS: Added $samAccount to $licGroup"
        }

    } catch {
        Write-Log "ERROR: Failed creating $displayName | $_"
    }
}

Write-Log '--- Mover/Leaver pre-flight complete ---'

Write-Host "`nSimone Ford and Ray Chen account summary:" -ForegroundColor Cyan
Get-ADUser -Filter * -SearchBase 'OU=Departments,DC=nigeltech,DC=local' `
    -Properties Department, Title, EmployeeID, MemberOf, Enabled |
    Where-Object { $_.EmployeeID -in @('EMP1004', 'EMP1005') } |
    ForEach-Object {
        $groups = ($_.MemberOf | ForEach-Object { (Get-ADGroup -Identity $_).Name }) -join ', '
        [PSCustomObject]@{
            Name       = $_.Name
            SAM        = $_.SamAccountName
            UPN        = $_.UserPrincipalName
            Department = $_.Department
            Title      = $_.Title
            EmployeeID = $_.EmployeeID
            Groups     = $groups
            Enabled    = $_.Enabled
        }
    } | Format-Table -AutoSize