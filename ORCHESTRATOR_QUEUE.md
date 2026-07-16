# Orchestrator Queue

Items escalated from the autonomous remediation run for Dispatch/Chairman attention —
things outside the executor's authority (repo visibility/archive, public posting, secrets,
destructive infra) or process gaps worth flagging before audit.

## Process note — dual-owned issues (#8, #12, #27, #28)

The runbook requires BOTH a CTO-side and a DevOps-side `validation_run` before closing
these four. This session ran as a single unified executor (no separate CTO/DevOps
sub-agent role-play with independently recorded validation runs, and no
`enclave_validation` DB exists on disk — checked, not found). Evidence for these issues
was instead recorded as: real live-stack functional probes (command + output) in the
GitHub close comment + `REMEDIATION_LOG.md`.

- **#12** (closed): single unified validation pass only. Flagging for Dispatch to apply
  the CTO/DevOps dual-check retroactively, or confirm the recorded evidence is sufficient.
- #8, #27, #28: not yet reached at time of writing; same caveat will apply when closed.
