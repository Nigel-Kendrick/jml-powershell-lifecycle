# PowerShell JML Identity Lifecycle Automation

Automated Joiner/Mover/Leaver (JML) identity lifecycle management for hybrid Microsoft environments, demonstrating Identity Governance & Administration (IGA) principles used by enterprise platforms like SailPoint IdentityIQ and Saviynt.

---

## 🎯 Project Overview

This lab simulates a production Identity Governance workflow where an HR system (CSV feed) drives automated provisioning, role changes, and deprovisioning across on-premises Active Directory and Microsoft Entra ID.

**Environment:**
- **Domain:** NigelTech.local / nigeltech.onmicrosoft.com
- **Infrastructure:** Windows Server 2022 DC, Windows 11 admin workstation
- **Identity Platform:** Microsoft Entra ID P2, Entra Connect sync
- **Licensing:** Microsoft 365 E5 (group-based assignment)

**IGA Capabilities Demonstrated:**
- ✅ Automated user provisioning from authoritative source (HR feed)
- ✅ Role-based access control (RBAC) via department security groups
- ✅ Identity lifecycle state transitions (Joiner → Active → Mover → Leaver)
- ✅ Manager hierarchy enforcement and attribute management
- ✅ Automated deprovisioning and access revocation
- ✅ Group-based license assignment and revocation
- ✅ Microsoft Graph API integration for real-time Entra ID account management
- ✅ Audit logging for compliance

---

## 🔬 Lab Scope

This project covers **EMP1001–EMP1005** exclusively. The NigelTech tenant contains additional accounts from prior lab projects (Entra API-driven provisioning, Hybrid Azure AD Join, Conditional Access, etc.) which appear in some screenshots but are outside the scope of this project. All JML scripts use `EmployeeID` as the authoritative identifier, so pre-existing accounts are never touched.

---

## 👥 HR Feed — Employee Roster

| EmployeeID | Name | Department | Action | Manager |
|---|---|---|---|---|
| EMP1001 | Steven Bell | IT | Joiner | mthomas (Michael Thomas) |
| EMP1002 | Layla Hassan | Finance | Joiner | kdavis (Karen Davis) |
| EMP1003 | Darius King | HR | Joiner | ltaylor (Lisa Taylor) |
| EMP1004 | Simone Ford | IT → Finance | Mover | mthomas → kdavis |
| EMP1005 | Ray Chen | Sales | Leaver | rbrown (Robert Brown) |

> **Note:** Jane Smith (`jsmith`) is a Finance staff account representing a pre-existing tenant user. She is not a manager in this project. IT is managed by Michael Thomas (`mthomas`).

---

## 📂 Repository Structure

```
jml-powershell-lifecycle/
├── scripts/
│   ├── 0_Create_Managers.ps1       # Pre-flight: Create manager accounts
│   ├── 0_Create_Mover_Leaver.ps1   # Pre-flight: Create Mover/Leaver accounts for before state
│   ├── 1_Joiner.ps1                # New hire provisioning
│   ├── 2_Mover.ps1                 # Role change / department transfer automation
│   └── 3_Leaver.ps1                # Termination / offboarding automation
├── sample-data/
│   └── HR_Feed.csv                 # Mock HR system of record (5 employees)
├── screenshots/
│   ├── joiner/                     # AD user creation, group membership, Entra sync, license assignment
│   ├── mover/                      # Before/after: OU move, group change, manager update
│   └── leaver/                     # Account disable, group removal, Entra ID disabled status
└── docs/
    ├── SETUP.md                    # Lab environment setup guide
    └── IGA_CONCEPTS.md             # Mapping to enterprise IGA tools
```

---

## 🚀 Quick Start

### Prerequisites
- Windows Server with Active Directory Domain Services
- Microsoft Entra ID tenant with Entra Connect configured
- Microsoft 365 E5 licenses (or trial)
- PowerShell 5.1+ with Active Directory module (RSAT)
- App registration in Entra ID with `User.ReadWrite.All` application permission (for Leaver script)

### Setup

**1. Clone the repository:**
```powershell
git clone https://github.com/nigel-kendrick/jml-powershell-lifecycle.git
cd jml-powershell-lifecycle
```

**2. Create lab directory structure:**
```powershell
New-Item -Path "C:\JML_Lab" -ItemType Directory
New-Item -Path "C:\JML_Lab\Logs" -ItemType Directory
Copy-Item .\sample-data\HR_Feed.csv -Destination C:\JML_Lab\
Copy-Item .\scripts\*.ps1 -Destination C:\JML_Lab\
```

**3. Configure Graph API credentials** (required for Leaver script):
```powershell
@{
    TenantId     = "your-tenant-id"
    ClientId     = "your-app-client-id"
    ClientSecret = "your-client-secret"
} | ConvertTo-Json | Out-File C:\JML_Lab\graph_creds.json
```

**4. Run scripts in order — sequence is required:**
```powershell
# Step 1: Create manager accounts
.\0_Create_Managers.ps1

# Step 2: Provision new hires
.\1_Joiner.ps1

# Step 3: Create Mover/Leaver accounts to establish the before state
# *** Take BEFORE screenshots after this step ***
.\0_Create_Mover_Leaver.ps1

# Step 4: Process role change
.\2_Mover.ps1

# Step 5: Process termination
.\3_Leaver.ps1
```

> ⚠️ **Important:** `0_Create_Mover_Leaver.ps1` must run before `2_Mover.ps1` and `3_Leaver.ps1`. Simone Ford and Ray Chen must exist in AD before the Mover and Leaver scripts can locate them by EmployeeID. Running `2_Mover.ps1` without this pre-flight will log `ERROR: No user found with EmployeeID 'EMP1004'` and skip the record.

---

## ⚙️ Script Details

### 0_Create_Managers.ps1
Creates the manager accounts referenced in `HR_Feed.csv` before any JML scripts run. Safe to re-run — skips any account that already exists. Adds each manager to `GRP-M365-E5-Licensed` for licensing.

| SAM | Name | Department | Role |
|---|---|---|---|
| mthomas | Michael Thomas | IT | IT Manager |
| kdavis | Karen Davis | Finance | Finance Manager |
| ltaylor | Lisa Taylor | HR | HR Manager |
| rbrown | Robert Brown | Sales | Sales Manager |
| jsmith | Jane Smith | Finance | Financial Analyst (staff) |

### 0_Create_Mover_Leaver.ps1
Creates Simone Ford (IT) and Ray Chen (Sales) with correct OU placement, department group membership, and E5 license group. This establishes a realistic "before" state so the Mover and Leaver scripts have accounts to act on. Run this script and take your before screenshots before proceeding to `2_Mover.ps1`.

### 1_Joiner.ps1
Reads `Joiner` rows from `HR_Feed.csv` and performs:
- Generates `SamAccountName` — first initial + last name (e.g. `sbell`), with numeric suffix if taken (`sbell1`, `sbell2`)
- Creates AD account in the correct department OU
- Sets manager attribute from CSV
- Adds to department security group (`GRP-IT-Staff`, `GRP-Finance-Staff`, etc.)
- Adds to `GRP-M365-E5-Licensed` for group-based license assignment
- Checks for duplicate `EmployeeID` and UPN before creating — idempotent safe

### 2_Mover.ps1
Reads `Mover` rows from `HR_Feed.csv` and performs:
- Looks up user by `EmployeeID` (not name — authoritative source pattern)
- Removes from old department security group
- Moves AD account to new department OU
- Updates `Department` and `Title` attributes (uses `NewTitle` column, falls back to `JobTitle`)
- Updates `Manager` attribute to reflect new reporting line
- Adds to new department security group

### 3_Leaver.ps1
Reads `Leaver` rows from `HR_Feed.csv` and performs:
1. Disables AD account
2. Scrambles password to a random 32-character string
3. Strips all group memberships
4. Removes from `GRP-M365-E5-Licensed` (triggers license revocation after Entra Connect sync)
5. Moves account to `OU=Disabled_Accounts`
6. Adds to `GRP-Offboarded` staging group
7. Calls Microsoft Graph API to immediately disable the Entra ID account

---

## 🔑 License Management

Users are added to `GRP-M365-E5-Licensed` in on-premises Active Directory. Entra Connect syncs the group membership to Entra ID, where the group has an M365 E5 license assigned to it. Entra's group-based licensing automatically assigns the license to any synced member. For Leavers, removing the user from the group in AD triggers license revocation after the next sync cycle.

> This mirrors the enterprise pattern used in production IGA deployments. Direct per-user license assignment via Graph API is avoided intentionally — group-based licensing scales correctly and ties revocation to group membership logic automatically.

---

## 🔗 Microsoft Graph API Integration

The Leaver script uses the Graph API (`PATCH /users/{id}`) to immediately disable the Entra ID account upon offboarding, without waiting for the next Entra Connect sync cycle. This ensures cloud access is revoked in real time even if the sync window has not yet fired.

Credentials are loaded from `C:\JML_Lab\graph_creds.json` using an app registration with `User.ReadWrite.All` application permission and client credentials flow.

---

## 📋 Lab Notes

**Pre-existing tenant accounts:** The NigelTech tenant was built across multiple lab projects. Accounts such as Ethan Brooks, Derek Nguyen (EMP1010), and others visible in screenshots belong to earlier project batches and are unrelated to this project's scope. This project's scripts are scoped to EMP1001–EMP1005 via `EmployeeID` filtering.

**GRP-M365-E3-Licensed:** A legacy group visible in some screenshots from earlier lab work. Only `GRP-M365-E5-Licensed` is used in this project.

**Ray Chen — license group observation:** The before screenshot shows Ray Chen as a member of `GRP-M365-E5-Licensed`. The Leaver log records `INFO: rchen was not in GRP-M365-E5-Licensed` at the time the script ran. This is consistent with real-world timing in a hybrid environment — group membership state at script execution time may differ from a screenshot taken earlier in the same session depending on sync cycle timing.

**First Mover run error:** The full JML log shows an initial failed Mover attempt (`ERROR: No user found with EmployeeID 'EMP1004'`) followed by a successful run after `0_Create_Mover_Leaver.ps1` was executed. This is documented intentionally — it demonstrates why the pre-flight sequencing exists and what happens when it is skipped, which mirrors how enterprise IGA platforms enforce workflow prerequisites.

---

## 🗺️ IGA Concept Mapping

| This Lab | Enterprise Equivalent |
|---|---|
| HR_Feed.csv | Authoritative source (Workday, SAP HR) |
| 1_Joiner.ps1 | Joiner workflow / provisioning policy |
| 2_Mover.ps1 | Mover workflow / role change event |
| 3_Leaver.ps1 | Leaver workflow / termination event |
| GRP-M365-E5-Licensed | Entitlement / access profile |
| GRP-IT-Staff, GRP-Finance-Staff | Role-based groups / access profiles |
| EmployeeID as lookup key | Authoritative identifier / correlation key |
| JML_Log.txt | Audit trail / provisioning log |
| Graph API account disable | Real-time deprovisioning / connector action |

---

## 📸 Screenshots

Screenshots are organized by lifecycle phase in the `screenshots/` directory:

- **joiner/** — HR feed, script log, AD account creation, group membership, Entra ID sync, M365 license assignment
- **mover/** — Before state (IT OU), script output, after state (Finance OU, updated manager and title)
- **leaver/** — Before state (Sales OU), script output, GRP-Offboarded membership, Entra ID disabled status

---

## 🔗 Related Projects

This project is part of the NigelTech IAM portfolio:

| Repository | Pillar |
|---|---|
| jml-powershell-lifecycle *(this repo)* | IGA — PowerShell lifecycle automation |
| jml-entra-provisioning | IGA — API-driven SCIM provisioning |
| salesforce-saml-sso | Federation / SSO |
| hybrid-azure-ad-join | Device Identity |
| conditional-access-policies | Access Management |
| sspr-configuration | Identity Management |
| privileged-identity-management *(coming soon)* | PAM |
