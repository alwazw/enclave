# Security Policy

Enclave's entire thesis is provable integrity, so we treat security seriously and
disclose responsibly — **after** a fix is available, not before. The honest threat
model (what Enclave does and does **not** defend against) lives in
[docs/GOVERNANCE.md](docs/GOVERNANCE.md); read the "What this does NOT defend
against" section.

## Reporting a vulnerability

**Please do not open a public issue for a security vulnerability.**

Use GitHub's **private vulnerability reporting** on this repository:
**Security → Report a vulnerability**. This opens a private advisory visible only to
the maintainers — no email address required, and nothing is public until we publish
a fix and advisory together.

Please include: affected version/commit, a description, reproduction steps, and the
impact you observed. We aim to acknowledge reports within a few days and to keep you
updated through the advisory thread.

## Scope

- Enclave is **local-first and self-hosted**: whoever runs the host controls it.
  Enclave governs *agents*, not a malicious operator (see the threat model).
- In-scope: the governance plane (Registrar evidence gate, jurisdiction scoping,
  audit trail), the board UI, the setup/secret-generation flow, and the service
  compose definitions.
- Out of scope: issues requiring root on the host, and the honest limitations
  already documented in `docs/GOVERNANCE.md`.

## Handling secrets

Secrets live only in a gitignored `.env`; `.env.example` holds placeholders. A
`gitleaks` scan and a personal-identifier denylist run before anything is published.
If you find a secret committed to history, report it privately as above.
