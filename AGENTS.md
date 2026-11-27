# JADIS — Agent instructions
Jadis / Reconnecting People: adult-first, consent-based school reconnection. Current stage: Foundation First, not public launch.
Read docs/foundation-first.md and docs/codex-mission.md before implementing. GitHub issues are the work queue; resolve prerequisites first.
## Execution
- Work autonomously within the task, implement and test rather than returning plans alone. Use a feature branch and pull request; never push directly to main, merge automatically or deploy to production. These are contributor rules, not a claim that branch protection is configured.
- Cloud only; existing GitHub, PostgreSQL/Supabase and free CI first. No paid service, billing change, external account creation or API credits without founder approval.
- Use synthetic data only in tests. Never connect a coding environment to production with privileged credentials, run production migrations, open registration, publish personal data or change live infrastructure without separate approval.
- Prefer incremental, reversible changes. Preserve migration history; new migrations must follow verified tooling conventions. Verify current vendor docs and source dataset terms. No graph database or microservices without measured justification.
- Security and privacy from first change: least privilege, RLS and explicit grants, deny by default, server-side validation, consent, blocks both directions, no third-party personal data lookup. Never trust user-editable metadata for authorization. No secrets, tokens, raw personal data or exploit details in public commits/issues/logs.
- No feature or visual redesign until foundation gates pass. Preserve dark retro 1999–2004 constellation identity and primary colors for later.
## Verification
Run npm test and relevant syntax checks; add regression tests for each behavior change. DB tests must run against an isolated disposable database with synthetic users; never silently skip or claim success for unavailable tests. Cover anonymous, non-member, owner, unrelated member, blocked users and account deletion. Review constraints, concurrency, grants, RLS, indexes and rollback strategy.
Pin new dependencies and CI actions appropriately; avoid new dependencies without justification. Use minimal CI permissions. Do not bypass test failures.
## Deliverables
PR includes scope, issue references, decisions, files changed, commands/results, residual risks, rollback and deployment prerequisites. Update docs and issue status only with evidence. Legal drafts are not legal approval; audit results are not certification. Stop at production release gates, financial decisions and legal/operator decisions. Keep detailed vulnerability findings in a restricted channel, not public GitHub.
