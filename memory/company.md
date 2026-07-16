# Local Stack — Company Memory

## What this is
AEF2: a self-hosted local AI stack on a single VM (10.10.10.27 / host alias set via HOST_IP in
.env), orchestrated via `local-stack.yml` + per-service compose files under `compose/`, driven
by profiles: core, knowledge, automation, memory, extras, observability, tools.

## Host
- Ubuntu VM, 16 vCPU, 20GB RAM, no GPU passthrough.
- Root disk: LVM (`ubuntu-vg/ubuntu-lv` on `/dev/sda3`), ext4. Grown 2026-07-15 from 62GB to
  124GB live (had 63GB free in the VG, unused — no reboot/hypervisor resize was needed).
- Docker enabled at boot (`systemctl is-enabled docker` = enabled); all services use
  `restart: unless-stopped`, so a reboot is safe and self-healing.

## Stack shape (see memory/departments/devops.md for the live port/service registry)
Shared Postgres (single instance, role `aef2`, one DB per app: n8n, affine, flowise, langfuse,
mem0, litellm). Shared Redis. LiteLLM is the single LLM gateway — every service is expected to
route through it, never call Ollama directly. Model aliases follow an `openai/morpheus-*`
naming convention defined in `config/litellm/config.yml` (the file actually mounted into the
litellm container — NOT litellm.yml or setup-default-config.yaml, which are unused duplicates/
reference copies sitting in the same directory).

## Known, deliberately-deferred gaps (not bugs — do not re-litigate without new information)
- **mem0** (`compose/ai-ml/mem0/mem0.yml`): image is ARM64-only on Docker Hub, incompatible
  with this x86_64 host; also hardcodes pgvector (this stack's Postgres has no pgvector
  extension) and needs a second DB not yet provisioned. Documented in-file since 2026-07-13.
  Product has flagged it as possibly redundant with Hermes's own native memory. Service stays
  `profiles: [memory]` opt-in only; excluded from routine bring-up.
