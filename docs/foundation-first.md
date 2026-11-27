# JADIS — Foundation First
Date: 2026-11-27 | Status: initial internal review, not a security certification
Decision: keep the existing invite-only prototype; no public launch, no additional paid services, no local infrastructure. Product redesign follows foundation acceptance. This public repository document intentionally contains no secrets, personal data, exploit instructions or private audit evidence.

## 1. Observed baseline
- GitHub repository public; default branch main. Latest observed application commit 8a7a21d0f675df956137364947b3f982dc9f4f4f. Tests and Pages deployment reported success. Current CI uses Node 22 and node --test; deployment also checks beta.js syntax. These are not end-to-end or security test results.
- Single Supabase project in EU (Ireland), PostgreSQL. Six recorded migrations correspond to six SQL files in the repository.
- Fifteen application tables across public and jadis_private: all have RLS enabled; none grants anonymous SELECT. Four internal tables have no direct authenticated read/write grants. Three public application RPCs are invoker wrappers; privileged implementations reside in jadis_private. The inspected application RPCs deny anonymous EXECUTE.
- Aggregate database counts at review: zero auth accounts, invitations redeemed, schools, classes, journeys or beta school entries. This is a useful opportunity to consolidate data before real use.
- Security advisor: four INFO findings for internal tables with RLS and no policies. Current direct grants deny client access; retain deny-by-default, verify in automated tests and document rationale.
- Performance advisor: 13 auth_rls_initplan warnings, seven unindexed foreign key notices, six unused-index notices. No index removal solely because an empty database reports no usage.
- Basic pattern scan across 15 selected current files did not find a private-key marker, secret Supabase key, common GitHub/AWS token pattern or JWT. A client publishable Supabase key is intentional. Not a scan of the full Git history, Actions secrets, logs or all token formats.
- No dependency packages declared in package.json at review. CI supply-chain pinning, branch protection, MFA, Auth settings, backup configuration, full history scan and runtime testing remain unverified. No LICENSE file observed; legal ownership/license review required.

## 2. Data and architecture decisions (proposed, pending acceptance)
Retain PostgreSQL, Supabase Auth and GitHub Actions. Do not add a graph database, microservices or paid components without a measured need and separate budget approval. Keep demo fixtures isolated from real accounts. Use a single canonical model before expanding features.
- Institutions: internal stable identifier, institution type and lifecycle; external identifiers in a separate source mapping table, unique by source + identifier. Preserve UAI and higher-education identifiers with provenance, import date, aliases and status; do not assume different identifiers or campuses represent the same institution.
- Historical names and closures: temporal aliases and successor/predecessor relations; never rewrite a user's historical attendance to a successor without confirmation.
- Education structure: institution -> campus/faculty where known -> programme -> academic year -> cohort/class/group; nullable fields for uncertain information. Distinguish an exact class from an overlapping school year.
- Attendance: one authoritative user-owned enrollment model, year/period and optional cohort; explicit declared versus verified provenance and user confirmation. Consolidate legacy journeys, memberships and beta_school_entries only after migration tests. Never infer membership as a fact from age.
- Identity: separate auth account from profile and public discovery preferences; verified email is not verified identity. Do not require date of birth, former name or childhood city unless justified.
- Connections: explicit consent for discoverability and bilateral acceptance for messaging; blocks apply in both directions. Separate private messages, moderation, invitations and retention controls from public directory data.
- Official directory ingestion: server-side validation, batch imports with versioned source metadata, checksums, record counts and error quarantine. Prefer scheduled incremental refresh with periodic reconciliation. Confirm dataset schema, license, coverage, pagination, rate limits and historical completeness before import. No bulk collection of people, alumni or teachers. No direct public directory search should silently become identity validation.
- Data flow: browser -> HTTPS frontend -> Auth / restricted API -> PostgreSQL; server-side reference ingestion -> staging -> validation -> canonical directory. No personal search terms forwarded to third-party open-data APIs after migration. Storage for photos deferred.
- Environments: separate synthetic test data from real users; ephemeral CI database where feasible; free-tier resource constraints must be assessed before provisioning permanent staging. Future public hosting choice subject to terms and cost review.

## 3. Remediation backlog and acceptance gates
All P0 items block public release; only synthetic tests until privacy and safety requirements for any real pilot are met.

| ID | Priority | Deliverable / acceptance evidence |
|---|---|---|
| DATA-01 | P0 | Canonical ERD, data dictionary, constraints, migration and rollback strategy; no ambiguous duplicate attendance source. |
| DATA-02 | P0 | Validate all three intended reference datasets against real responses and published metadata; verify licenses, field mappings, historical coverage and import reproducibility. |
| DATA-03 | P0 | Idempotent reference ingestion with stable IDs, alias/campus handling, quarantine, quality metrics and fixtures. |
| ARCH-01 | P0 | Architecture decision records, data flows, trust boundaries and environment inventory; no secrets in client or docs. |
| ARCH-02 | P0 | Isolated test environment, reproducible migration replay and rollback plan; no real data in CI. |
| SEC-01 | P0 | Full permission matrix including grants, functions, storage, API surface; negative tests for anonymous, uninvited and unrelated authenticated accounts. |
| SEC-02 | P0 | Validate email delivery/redirects, password reset, session expiry/revocation, abuse limits, admin MFA and account takeover controls. |
| SEC-03 | P0 | Scan complete Git history and CI configuration; secret scanning, least-privilege workflows, pinned action revisions and protected release process; assess public repo/IP decision. |
| SEC-04 | P0 | Review authorization, input validation, concurrency and abuse cases for discovery, invitations, blocks, messaging and reports; synthetic multi-account integration tests. |
| PRIV-01 | P0 | Inventory purpose, minimization, visibility, retention and access per field; explicit discovery opt-in and revocation tests; no third-party disclosure without documented basis. |
| PRIV-02 | P0 | Account deletion, data export, session revocation, retention/cleanup jobs and backup deletion handling; documented test evidence. |
| LEGAL-01 | P0 | Identify controller/operator, legal form, contact details, IP and trademark clearance; professional advice where necessary. |
| LEGAL-02 | P0 | Processing register, lawful bases, privacy notice, processor contracts and transfer assessment; assess DPIA and applicable platform rules with counsel; no claim of certification or compliance without review. |
| TRUST-01 | P0 | Adult-only pilot policy and proportionate age assurance, impersonation/harassment controls, no unsolicited contact, privacy-safe abuse reporting. |
| TRUST-02 | P0 | Moderation queue, escalation and response ownership, content removal/appeals where applicable, incident procedures. |
| OPS-01 | P0 | Backup/restore test, monitoring, incident runbook and service limits; prove recovery with synthetic data. |
| OPS-02 | P0 | Cost thresholds, quota monitoring, performance/load tests, index review based on realistic workload; no paid upgrade without approval. |
| PROD-01 | Later | Retro dark constellation design and onboarding; no visual work ahead of foundations acceptance. |

## 4. Definition of done
A ticket requires documented acceptance criteria, a reviewed change, repeatable test evidence, and an identified residual risk or explicit risk acceptance. A green deployment is not proof of product readiness. Public release requires every P0 gate to be reviewed; a real-user pilot has its own privacy/security gate. Release evidence must contain synthetic or anonymized data only; detailed vulnerability findings and credentials belong in restricted channels, not this public repository.

## 5. Cost guardrails
Target zero recurring spend in development where feasible. Use existing cloud services, official open data and open-source test tooling first. Paid upgrades, custom domain, legal services and independent audits require approval and separate estimates. Free-tier uptime, email, storage, database backups, quotas and commercial hosting terms must be verified before launch; free is not a substitute for recovery or compliance. No local user machine dependency.

## 6. Next executable sprint
DATA-01 first: reconcile migrations with live schema, define the canonical institution/identifier/alias/cohort/attendance model, create migration tests and an architecture decision record. DATA-02 next: verify actual official endpoint responses and license metadata, then implement controlled ingestion. Security and privacy design constraints apply from the first schema change even though their dedicated remediation phase follows data architecture. Do not collect real user data yet.

## Scope limitations
This review is a baseline, not a pentest, legal opinion, complete secret audit, directory API validation or production sign-off. No account, infrastructure, billing or production schema was changed in the audit. The new documentation itself may trigger existing GitHub Actions.
