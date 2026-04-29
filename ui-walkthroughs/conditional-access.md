# Conditional Access policies - UI walkthrough

CA policies are tenant-wide rules in Entra ID that gate access based on conditions (user, location, device, app, risk). Mostly UI-driven (limited Graph API).

Required license: at least Entra ID P1 (most have via M365 E3+).

Time: 1–2 hours for baseline.

## Pre-requisites

- Entra ID admin role (Conditional Access Administrator at minimum).
- 2 break-glass cloud-only accounts created and excluded from all CA (otherwise you can lock yourself out).
- Hardware token / phishing-resistant MFA on break-glass.

## Open

**https://entra.microsoft.com/** → **Protection** → **Conditional Access** → **Policies**.

## Baseline policy set (apply in order; report-only first, then enforce)

### 1. Block legacy auth

1. **+ New policy** → name `BL01 – Block legacy auth`.
2. **Users**: All users → **Exclude**: break-glass accounts.
3. **Cloud apps**: All cloud apps.
4. **Conditions** → **Client apps** → Configure: Yes; check ONLY the boxes under **Legacy authentication clients** (Exchange ActiveSync + Other clients). Leave the modern auth boxes unchecked.
5. **Grant**: Block access.
6. Enable: **Report-only** for 1 week → review sign-in logs → switch to **On**.

### 2. MFA for admin roles

1. **+ New policy** → `BL02 – MFA for admins`.
2. **Users**: Directory roles → select all admin roles (Global Admin, Privileged Role Admin, Security Admin, Conditional Access Admin, Application Admin, Cloud App Admin, etc.).
3. **Cloud apps**: All cloud apps.
4. **Grant**: Require MFA + Require authentication strength = Phishing-resistant MFA (FIDO2/Windows Hello).
5. Enable: **On**.

### 3. MFA for all users

1. **+ New policy** → `BL03 – MFA for all users`.
2. **Users**: All users → Exclude: break-glass.
3. **Cloud apps**: All cloud apps.
4. **Conditions** → **Sign-in risk** = Medium and above (if Identity Protection licensed; else skip this condition).
5. **Grant**: Require MFA.
6. Enable: **Report-only** then **On**.

### 4. Block sign-in from disallowed countries

1. **Conditions** → **Locations** → **Configure named locations** first:
   - Create `Allowed countries` → pick countries (e.g. PL, DE, US, UK).
   - Create `Trusted IPs` → office public IPs.
2. **+ New policy** → `BL04 – Block disallowed countries`.
3. **Users**: All → Exclude: break-glass.
4. **Cloud apps**: All cloud apps.
5. **Conditions** → **Locations** → Include = Any location, Exclude = `Allowed countries`.
6. **Grant**: Block access.
7. Enable: **On**.

### 5. Compliant device for Azure portal

1. **+ New policy** → `BL05 – Compliant device for Azure mgmt`.
2. **Users**: Members of group `azure-admins`.
3. **Target resources** → **Cloud apps** → Microsoft Azure Management.
4. **Grant**: Require device to be marked as compliant (or hybrid Azure AD joined).
5. Enable: **Report-only** → confirm admins comply → **On**.

### 6. Session controls - sign-in frequency

1. **+ New policy** → `BL06 – Reauth privileged apps`.
2. **Users**: Admin groups.
3. **Cloud apps**: Microsoft Azure Management, Microsoft Graph PowerShell, Office 365.
4. **Session** → Sign-in frequency = 4 hours.
5. Enable: **On**.

## Validation

1. **Sign-ins log** (Entra → Sign-in logs) → filter by Conditional Access → see which policies applied.
2. **What If** tool (Conditional Access blade) → simulate a user/device/location/app combo → see which policies fire.
3. Sign in as a test user from a non-allowed country (use VPN) → expect block.
4. Sign in to Azure portal as admin without MFA → expect MFA prompt.

## Important: emergency access

The 2 break-glass accounts must be:
- Cloud-only (`@<tenant>.onmicrosoft.com`).
- Excluded from ALL CA policies.
- Hardware token required (FIDO2 / smart card).
- Monitored: alert if either signs in.
- Documented: location of credentials known by 2 people.
- Tested quarterly (sign in, change password, log out).

If you lose all admins + the CA policies block recovery: Microsoft Support unlock takes 24+ hours of vetting.

## API (limited support)

Microsoft Graph has read + create for CA policies:
```bash
# List
az rest --method GET --url "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies"

# Create (advanced - JSON body required)
az rest --method POST --url "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" \
    --body @ca-policy.json
```

Some properties are UI-only. For full automation: use the Microsoft `Microsoft365DSC` PowerShell module which abstracts CA + many other M365 settings.

## Common mistakes

1. **Locking yourself out**: didn't exclude break-glass.
2. **Skipping report-only**: turning new policies straight to On - surprises people.
3. **Excluding too few apps**: blocking "All cloud apps" without Sandbox apps for testing.
4. **MFA without phishing-resistant**: SMS/voice MFA still bypassable; require FIDO2 for admins.
5. **Country block by IP only**: VPN bypasses; use country + Identity Protection signals.
