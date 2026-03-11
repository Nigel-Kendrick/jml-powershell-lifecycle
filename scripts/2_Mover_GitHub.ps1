# ============================================================
# 2_Mover.ps1 - Automated Role Transition (Mover)
# NigelTech JML Lab | IGA Portfolio Project
# ============================================================

$csvPath = 'C:\JML_Lab\HR_Feed.csv'
$logPath = 'C:\JML_Lab\Logs\JML_Log.txt'

# --- FIXED: Use your actual lab domain DC=NigelTech,DC=local ---
$ouMap = @{
    'IT'      = 'OU=IT,OU=Departments,DC=NigelTech,DC=local'
    'Finance' = 'OU=Finance,OU=Departments,DC=NigelTech,DC=local'
    'HR'      = 'OU=HR,OU=Departments,DC=NigelTech,DC=local'
    'Sales'   = 'OU=Sales,OU=Departments,DC=NigelTech,DC=local'
}

$groupMap = @{
    'IT'      = 'GRP-IT-Staff'
    'Finance' = 'GRP-Finance-Staff'
    'HR'      = 'GRP-HR-Staff'
    'Sales'   = 'GRP-Sales-Staff'
}

New-Item -ItemType Directory -Path 'C:\JML_Lab\Logs' -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | MOVER | $Message"
    Add-Content -Path $logPath -Value $entry
    Write-Host $entry
}

Write-Log '--- Mover run started ---'

$movers = Import-Csv $csvPath | Where-Object { $_.Action -eq 'Mover' }

foreach ($emp in $movers) {
    Write-Log "Processing Mover: $($emp.FirstName) $($emp.LastName) | EmpID: $($emp.EmployeeID) | $($emp.Department) -> $($emp.NewDepartment)"

    if ([string]::IsNullOrWhiteSpace($emp.NewDepartment)) {
        Write-Log "ERROR: NewDepartment is blank for EmpID $($emp.EmployeeID) — skipping"
        continue
    }

    $newOU = $ouMap[$emp.NewDepartment]
    if (-not $newOU) {
        Write-Log "ERROR: No OU mapping for NewDepartment '$($emp.NewDepartment)' — skipping"
        continue
    }

    # --- Look up user by EmployeeID ---
    $user = Get-ADUser -Filter "EmployeeID -eq '$($emp.EmployeeID)'" `
                       -Properties EmployeeID, Department, MemberOf, DistinguishedName, SamAccountName `
                       -ErrorAction SilentlyContinue

    if (-not $user) {
        Write-Log "ERROR: No user found with EmployeeID '$($emp.EmployeeID)'"
        continue
    }

    $oldGroup = $groupMap[$emp.Department]
    $newGroup = $groupMap[$emp.NewDepartment]

    try {
        # --- Step 1: Remove from old department group ---
        if ($oldGroup) {
            $isMember = $user.MemberOf | Where-Object { $_ -like "*$oldGroup*" }
            if ($isMember) {
                Remove-ADGroupMember -Identity $oldGroup -Members $user.SamAccountName -Confirm:$false
                Write-Log "SUCCESS: Removed $($user.SamAccountName) from $oldGroup"
            }
        }

        # --- Step 2: Move to new OU ---
        # Note: Added a check to see if the user is already in the target OU
        if ($user.DistinguishedName -like "*$newOU") {
            Write-Log "INFO: $($user.SamAccountName) is already in the correct OU — skipping move"
        } else {
            Move-ADObject -Identity $user.DistinguishedName -TargetPath $newOU
            Write-Log "SUCCESS: Moved $($user.SamAccountName) to $newOU"
        }

        # --- Step 3: Update Department and Title ---
        $updatedTitle = if (-not [string]::IsNullOrWhiteSpace($emp.NewTitle)) { $emp.NewTitle } else { $emp.JobTitle }
        Set-ADUser -Identity $user.SamAccountName `
                   -Department $emp.NewDepartment `
                   -Title $updatedTitle
        Write-Log "SUCCESS: Updated Department to '$($emp.NewDepartment)' | Title to '$updatedTitle'"

        # --- Step 4: Update Manager ---
        $newManager = Get-ADUser -Filter "SamAccountName -eq 'kdavis'" -ErrorAction SilentlyContinue
        if ($newManager) {
            Set-ADUser -Identity $user.SamAccountName -Manager $newManager
            Write-Log "SUCCESS: Updated Manager to kdavis"
        }

        # --- Step 5: Add to new department group ---
        if (Get-ADGroup -Filter "Name -eq '$newGroup'" -ErrorAction SilentlyContinue) {
            Add-ADGroupMember -Identity $newGroup -Members $user.SamAccountName
            Write-Log "SUCCESS: Added $($user.SamAccountName) to $newGroup"
        }

    } catch {
        Write-Log "ERROR: Failed processing EmpID $($emp.EmployeeID) | $_"
    }
}

Write-Log '--- Mover run complete ---'

# --- Final Table View (Fixed SearchBase) ---
Write-Host "`nMover accounts (after):" -ForegroundColor Cyan
$moverIDs = (Import-Csv $csvPath | Where-Object { $_.Action -eq 'Mover' }).EmployeeID
Get-ADUser -Filter * -SearchBase 'OU=Departments,DC=NigelTech,DC=local' `
    -Properties Department, Title, EmployeeID |
    Where-Object { $_.EmployeeID -in $moverIDs } |
    Select-Object Name, SamAccountName, Department, Title, EmployeeID |
    Format-Table -AutoSize