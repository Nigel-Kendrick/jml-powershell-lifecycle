# PowerShell JML Identity Lifecycle Automation

Automated Joiner/Mover/Leaver (JML) identity lifecycle management for hybrid Microsoft environments, demonstrating Identity Governance & Administration (IGA) principles used by enterprise tools like SailPoint IdentityIQ and Saviynt.

## 🎯 Project Overview

This lab simulates a production Identity Governance workflow where an HR system (CSV feed) drives automated provisioning, role changes, and deprovisioning across on-premises Active Directory and Azure Entra ID (Azure AD).

**Environment:**
- **Domain:** NigelTech.local / nigeltech.onmicrosoft.com
- **Infrastructure:** Windows Server 2022 DC, Windows 11 admin workstation
- **Identity Platform:** Microsoft Entra ID P2, Entra Connect sync
- **Licensing:** Microsoft 365 E5 (group-based assignment)

**IGA Capabilities Demonstrated:**
- ✅ Automated user provisioning from authoritative source (HR feed)
- ✅ Role-based access control (RBAC) via department groups
- ✅ Identity lifecycle state transitions (Joiner → Active → Mover → Leaver)
- ✅ Separation of duties (manager hierarchy enforcement)
- ✅ Automated deprovisioning and access revocation
- ✅ Audit logging for compliance

---

## 📂 Repository Structure
```
jml-powershell-lifecycle/
├── scripts/
│   ├── 0_Create_Managers.ps1       # Pre-flight: Create manager accounts
│   ├── 0_Create_Mover_Leaver.ps1   # Pre-flight: Setup existing users for Mover/Leaver demo
│   ├── 1_Joiner.ps1                # New hire provisioning
│   ├── 2_Mover.ps1                 # Role change / transfer automation
│   └── 3_Leaver.ps1                # Termination / offboarding automation
├── sample-data/
│   └── HR_Feed.csv                 # Mock HR system of record (5 employees)
├── screenshots/
│   ├── joiner/                     # Before/after AD user creation, group membership
│   ├── mover/                      # Department transfer, OU move, manager update
│   └── leaver/                     # Account disable, group removal, Entra ID status
└── docs/
    ├── SETUP.md                    # Lab environment setup guide
    └── IGA_CONCEPTS.md             # Mapping to enterprise IGA tools
```

---

## 🚀 Quick Start

### Prerequisites
- Windows Server with Active Directory Domain Services
- Azure Entra ID tenant with Entra Connect configured
- Microsoft 365 E5 licenses (or trial)
- PowerShell 5.1+ with Active Directory and Microsoft.Graph modules

### Setup Steps

1. **Clone the repository:**
```powershell
   git clone https://github.com/nigel-kendrick/jml-powershell-lifecycle.git
   cd jml-powershell-lifecycle
```

2. **Create lab directory structure:**
```powershell
   New-Item -Path "C:\JML_Lab" -ItemType Directory
   New-Item -Path "C:\JML_Lab\Logs" -ItemType Directory
   Copy-Item .\sample-data\HR_Feed.csv -Destination C:\JML_Lab\
   Copy-Item .\scripts\*.ps1 -Destination C:\JML_Lab\
```

3. **Configure Graph API credentials** (for Leaver script):
```powershell
   # Create graph_creds.json with app registration details
   @{
       tenantId = "your-tenant-id"
       clientId = "your-app-id"
       clientSecret = "your-secret"
   } | ConvertTo-Json | Out-File C:\JML_Lab\graph_creds.json
```

4. **Run pre-flight scripts:**
```powershell
   .\0_Create_Managers.ps1
   .\0_Create_Mover_Leaver.ps1
```

5. **Execute JML workflows:**
```powershell
   .\1_Joiner.ps1    # Provision new hires
   .\2_Mover.ps1     # Process role changes
   .\3_Leaver.ps1    # Offboard terminated employees
```

---

## 📋 HR Feed Structure

The `HR_Feed.csv` acts as the authoritative source (like Workday, SuccessFactors, or UKG):

| EmployeeID | FirstName | LastName | Department | Title | Manager | Action |
|------------|-----------|----------|------------|-------|---------|--------|
| EMP1001 | Steven | Bell | IT | Systems Administrator | mthomas | Joiner |
| EMP1002 | Layla | Hassan | Finance | Financial Analyst | kdavis | Joiner |
| EMP1003 | Darius | King | HR | HR Specialist | ltaylor | Joiner |
| EMP1004 | Simone | Ford | Finance | Senior Financial Analyst | kdavis | Mover |
| EMP1005 | Ray | Chen | Sales | Account Executive | rbrown | Leaver |

**Action Types:**
- **Joiner:** New employee - create AD account, assign to department OU/group, provision M365 license
- **Mover:** Role change - update department, OU, groups, manager, title
- **Leaver:** Termination - disable account, revoke access, move to disabled OU, scramble password

---

## 🔐 Identity Lifecycle Workflows

### 1️⃣ Joiner (New Hire Provisioning)

**Business Process:**
- HR system sends new hire record on start date
- IT provisions access before employee arrives

**Automation (`1_Joiner.ps1`):**
```powershell
# For each Joiner in HR_Feed.csv:
1. Generate SamAccountName (first initial + lastname, e.g. sbell)
2. Check for duplicate EmployeeID and UPN
3. Create AD user in department OU (e.g. OU=IT,OU=Departments,DC=nigeltech,DC=local)
4. Set attributes: EmployeeID, Department, Title, Manager, UPN
5. Add to department security group (e.g. GRP-IT)
6. Add to GRP-M365-E5-Licensed (triggers license assignment via group-based licensing)
7. Log action to C:\JML_Lab\Logs\JML_Log.txt
```

**Result:** User created in AD, synced to Entra ID via Entra Connect, auto-assigned M365 E5 license

---

### 2️⃣ Mover (Role Change / Department Transfer)

**Business Process:**
- Employee transfers from IT to Finance
- Access should reflect new role (remove old permissions, grant new)

**Automation (`2_Mover.ps1`):**
```powershell
# For each Mover in HR_Feed.csv:
1. Lookup user by EmployeeID
2. Remove from old department group (GRP-IT)
3. Move user to new department OU (OU=Finance,OU=Departments)
4. Update AD attributes: Department, Title, Manager
5. Add to new department group (GRP-Finance)
6. Entra Connect sync propagates changes to Azure AD
```

**IGA Concept:** **Birthright provisioning** - users automatically get access based on role/department

---

### 3️⃣ Leaver (Termination / Offboarding)

**Business Process:**
- Employee terminated or resigned
- Immediate access revocation required for security/compliance

**Automation (`3_Leaver.ps1`):**
```powershell
# For each Leaver in HR_Feed.csv:
1. Disable AD account
2. Generate random 32-character password (prevents re-activation without password reset)
3. Remove from ALL security groups
4. Remove from GRP-M365-E5-Licensed (revokes M365 license)
5. Move to OU=Disabled_Accounts (isolates from active users)
6. Add to GRP-Offboarded (for audit/reporting)
7. Use Microsoft Graph API to disable Entra ID account (prevents cloud-only app access)
8. Log full action details
```

**Security Features:**
- Password scramble prevents unauthorized access even if account re-enabled
- Group removal follows least-privilege principle
- Dual disable (AD + Entra) prevents cloud app access during sync delay
- Audit trail via logging and GRP-Offboarded membership

---

## 🏢 Enterprise IGA Tool Mapping

This lab demonstrates concepts used in production Identity Governance tools:

| Concept | This Lab | SailPoint IdentityIQ | Saviynt | Microsoft Entra ID Governance |
|---------|----------|---------------------|---------|-------------------------------|
| **Authoritative Source** | HR_Feed.csv | HR connector (Workday, SAP) | Source systems integration | HR-driven provisioning |
| **Provisioning** | 1_Joiner.ps1 | Provisioning policy | Account aggregation workflow | Lifecycle workflows |
| **Role-Based Access** | Department groups | Role definitions | Role catalog | Entitlements |
| **Access Certification** | Manual review of groups | Access review campaigns | Access certification | Access reviews |
| **Deprovisioning** | 3_Leaver.ps1 | Leaver workflow | Termination process | Lifecycle workflows (Leaver) |
| **Audit Logging** | JML_Log.txt | Audit reports | Compliance reports | Sign-in logs + audit logs |
| **Separation of Duties** | Manager hierarchy | SoD policies | SoD violations | Privileged access reviews |

**Key Insight:** This PowerShell lab is functionally equivalent to an IGA tool's core capabilities - the enterprise tools add UI, compliance reporting, analytics, and multi-application connectors.

---

## 🛠️ Technical Details

### Naming Conventions
- **SamAccountName:** First initial + last name (e.g. `sbell` for Steven Bell)
  - Conflict resolution: Numeric suffix (`sbell2`, `sbell3`)
- **UPN:** `samaccountname@nigeltech.onmicrosoft.com`
- **EmployeeID:** Unique identifier from HR system (e.g. `EMP1001`)

### Group-Based Licensing
Users are added to GRP-M365-E5-Licensed in on-premises Active Directory. Entra Connect syncs the group membership to Entra ID, where the group has an M365 E5 license assigned to it. Entra's group-based licensing automatically assigns the license to any synced member. For Leavers, removing the user from the group in AD triggers license revocation after the next sync cycle.- Simplifies script logic (no Graph licensing calls needed)
- Provides centralized license management
- Automatically handles license removal when user leaves group

### Logging
All scripts append to `C:\JML_Lab\Logs\JML_Log.txt`:
```
2025-01-29 14:32:15 | JOINER | EMP1001 | Steven Bell | sbell | Created in OU=IT, added to GRP-IT, GRP-M365-E5-Licensed
2025-01-29 14:35:22 | MOVER | EMP1004 | Simone Ford | sford | Moved IT->Finance, updated manager mthomas->kdavis
2025-01-29 14:38:47 | LEAVER | EMP1005 | Ray Chen | rchen | Disabled AD, removed groups, disabled Entra ID
```

---

## 📸 Screenshots

See `screenshots/` folder for before/after evidence:
- **Joiner:** AD user creation, group membership, Entra ID sync, M365 license assignment
- **Mover:** Department change, OU move, manager update, group membership changes
- **Leaver:** Disabled account status, group removal, Entra ID disabled, Disabled_Accounts OU

---

## 🎓 Skills Demonstrated

### Technical
- PowerShell scripting for identity automation
- Active Directory management (user creation, OU structure, group membership)
- Microsoft Graph API — used in the Leaver script to immediately disable the Entra ID account via PATCH /users, ensuring cloud access is revoked without waiting for the next Entra Connect sync cycle.)
- CSV parsing and data validation
- Error handling and logging
- Idempotent script design (safe to re-run)

### Identity Governance Concepts
- Identity lifecycle management (Joiner/Mover/Leaver)
- Authoritative source integration (HR feed)
- Role-based access control (RBAC)
- Separation of duties (manager hierarchy)
- Least privilege principle (group removal on departure)
- Audit trails and compliance logging

### Enterprise Relevance
- Demonstrates understanding of IGA tools (SailPoint, Saviynt)
- Applicable to real-world IAM analyst workflows
- Scalable patterns (CSV could be replaced with API calls to Workday, SAP, etc.)

---

## 🔗 Related Projects

- [IAM Portfolio Website](https://nigel-kendrick.github.io) - SSPR, Hybrid Join, Conditional Access, SAML SSO labs
- [NigelTech.local Lab Environment](https://github.com/nigel-kendrick/nigeltech-lab-docs) - Hybrid AD/Entra infrastructure

---

## 📄 License

MIT License - Free to use for educational and portfolio purposes

---

## 👤 Author

**Nigel Kendrick**  
IAM Analyst | Systems Administrator  
[Portfolio](https://nigel-kendrick.github.io) | [LinkedIn](https://linkedin.com/in/nigel-kendrick1) | [Email](mailto:Nigeldkendrick@gmail.com)

---

## 🙏 Acknowledgments

Built as part of a structured IAM training curriculum, this lab demonstrates practical application of Identity Governance principles for enterprise environments.
