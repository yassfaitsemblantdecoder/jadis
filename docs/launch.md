# Jadis launch plan
## Public demo
Static fictional prototype; never enter personal information. Deploy root via Vercel, framework preset Other, no build step, output root. No secrets.
## Private beta (not yet enabled)
Create a Supabase project in EU, apply migration, verify RLS against two separate accounts, configure Auth and allowed redirects, implement verified adult registration, consent-based class discovery RPC with mutual block checks, rate-limited contact requests, reporting and account deletion. Add privacy notice and retention policy. No service-role key in browser or GitHub. Official directory results must be validated server-side before persistence. No public member lists or non-consenting teacher identities.
## Release gates
Browser/mobile tests; live directory API test; abuse tests; database policy tests; moderation process; verify actual deployment URL. Do not enable real profiles until these pass.
