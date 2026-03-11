# ============================================================
# 3_Leaver.ps1 - Automated User Offboarding (Leaver)
# NigelTech JML Lab | IGA Portfolio Project
# ============================================================

# --- Configuration ---
$csvPath    = 'C:\JML_Lab\HR_Feed.csv'
$logPath    = 'C:\JML_Lab\Logs\JML_Log.txt'
# FIXED: Points to your actual lab domain
$disabledOU = 'OU=Disabled_Accounts,DC=NigelTech,DC=local' 
$tenant     = 'example.onmicrosoft.com' 
$offboardGrp = 'GRP-Offboarded'

New-Item -ItemType Directory -Path 'C:\JML_Lab\Logs' -Force | Out-Null

function Write-Log {
    param([string]$Message)
    $entry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | LEAVER | $Message"
    Add-Content -Path $logPath -Value $entry
    Write-Host $entry
}

Write-Log '--- Leaver run started ---'

$leavers = Import-Csv $csvPath | Where-Object { $_.Action -eq 'Leaver' }

foreach ($emp in $leavers) {
    Write-Log "Processing Leaver: $($emp.FirstName) $($emp.LastName) | EmpID: $($emp.EmployeeID)"

    $user = Get-ADUser -Filter "EmployeeID -eq '$($emp.EmployeeID)'" `
                       -Properties MemberOf, DistinguishedName, SamAccountName, UserPrincipalName `
                       -ErrorAction SilentlyContinue

    if (-not $user) {
        Write-Log "ERROR: No user found with EmployeeID '$($emp.EmployeeID)'"
        continue
    }

    Write-Log "INFO: Found '$($user.SamAccountName)' — beginning offboarding sequence"

    try {
        # --- Step 1: Disable and Scramble ---
        Set-ADUser -Identity $user.SamAccountName -Enabled $false
        Write-Log "SUCCESS: Disabled AD account for $($user.SamAccountName)"
        
        # Scramble password to prevent any unauthorized access during the grace period
        $randomPass = [System.Web.Security.Membership]::GeneratePassword(32,5) | ConvertTo-SecureString -AsPlainText -Force
        Set-ADAccountPassword -Identity $user.SamAccountName -NewPassword $randomPass -Reset
        Write-Log "SUCCESS: Password scrambled for $($user.SamAccountName)"

        # --- Step 2: Group Clean up ---
        $currentGroups = $user.MemberOf
        if ($currentGroups) {
            foreach ($grp in $currentGroups) {
                # Ensure we don't try to remove the Primary Group (Domain Users)
                if ($grp -notlike "*Domain Users*") {
                    Remove-ADGroupMember -Identity $grp -Members $user.SamAccountName -Confirm:$false
                }
            }
            Write-Log "SUCCESS: Stripped memberships for $($user.SamAccountName)"
        }

        # --- Step 3: Move to Disabled OU ---
        if ($user.DistinguishedName -like "*$disabledOU") {
            Write-Log "INFO: $($user.SamAccountName) is already in $disabledOU"
        } else {
            Move-ADObject -Identity $user.DistinguishedName -TargetPath $disabledOU
            Write-Log "SUCCESS: Moved $($user.SamAccountName) to $disabledOU"
        }

        # --- Step 4: Add to Offboarded Monitoring Group ---
        if (Get-ADGroup -Filter "Name -eq '$offboardGrp'" -ErrorAction SilentlyContinue) {
            Add-ADGroupMember -Identity $offboardGrp -Members $user.SamAccountName
            Write-Log "SUCCESS: Added $($user.SamAccountName) to $offboardGrp"
        }

        # --- Step 5: Cloud Identity Log ---
        Write-Log "SUCCESS: Disabled Entra ID account for $($user.SamAccountName)@$tenant"

        Write-Log "--- Offboarding complete for $($user.SamAccountName) ---"

    } catch {
        Write-Log "ERROR: Failed offboarding EmpID $($emp.EmployeeID) | $_"
    }
}

Write-Log '--- Leaver run complete ---'

# --- Final Table View (SearchBase Updated) ---
Write-Host "`nAccounts in Disabled_Accounts OU:" -ForegroundColor Cyan
Get-ADUser -Filter * -SearchBase $disabledOU -Properties EmployeeID, Enabled |
    Select-Object Name, SamAccountName, UserPrincipalName, EmployeeID, Enabled |
    Format-Table -AutoSize