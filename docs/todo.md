# Autonomous SDLC Platform — TODO

## Phase 1: Foundation

- [ ] **Set up repo structure** — `.github/workflows/`, scripts dir, config templates
- [ ] **Create reusable workflow** (`on: workflow_call`) with parameterized inputs (repo, SonarQube project key, etc.)
- [ ] **Create example caller workflow** — minimal YAML a target repo drops into `.github/workflows/`

## Phase 2: GH Actions Checks (keep minimal)

- [ ] **SonarQube Cloud (free tier)** — set up org + project, add scan step to workflow (sonar-scanner action)
- [ ] **Snyk OSS scan** — `snyk test` + `snyk code test` in workflow (free tier, 1–2 vuln categories: deps + code)
- [ ] **Code Diff Analysis step** — script that detects: contract changes (OpenAPI/proto), missing test files for changed source files, new endpoints. Output JSON summary. (File-presence heuristic only — no coverage math.)
- [ ] **Coverage gate** — handled by SonarQube quality gate ("coverage on new code ≥ 90%"). SonarQube ingests JaCoCo/Cobertura XML if the repo produces one; if not, coverage = 0% → fails gate → triggers test playbook. No custom per-language coverage parsing needed.
- [ ] **Karate test check** — presence-based only ("do API tests exist for changed endpoints?"), not coverage-based. Karate tests are integration/API-level and don't produce code coverage without extra JaCoCo wiring.

## Phase 3: Triage (Rule-Based Router)

- [ ] **Triage script** — reads SonarQube, Snyk, and Diff outputs → decides which playbooks to invoke → builds Devin API payload
- [ ] **Triage rules (keep simple)**:
  - SonarQube quality gate failed → SonarQube playbook
  - Snyk high/critical findings → Security playbook
  - Contract changes detected → README + Postman playbooks
  - Code changed without tests / coverage < 90% → Test playbook

## Phase 4: Devin Integration

- [ ] **Get Devin org ID** from API (org name: `taylor-demos`) — needs API key
- [ ] **Devin session creation step** — POST to `/v3beta1/organizations/{org_id}/sessions` with prompt + repo context + scan outputs
- [ ] **Write playbook prompts** (no Devin playbook IDs yet — use freeform `prompt` field):
  - SonarQube fix prompt
  - Security fix prompt
  - README update prompt
  - Karate/API test prompt
  - Postman collection update prompt

## Phase 5: PR Artifact Writeback

- [ ] **Devin commits** back to PR branch (handled by Devin itself via prompt instructions)
- [ ] **PR comment step** — GH Actions posts summary comment with links to what changed

## Open Items / Secrets Needed

- [ ] SonarQube Cloud account + project key + `SONAR_TOKEN` secret
- [ ] Snyk free account + `SNYK_TOKEN` secret
- [ ] Devin API key → `DEVIN_API_KEY` secret
- [ ] Devin org ID (look up via API once key is available)

## Principles

- **Free tier / OSS only** — no paid tools
- **Minimal demo** — 1–2 examples per check, not exhaustive coverage
- **Show the architecture** — the point is demonstrating how the pieces connect, not production hardening
