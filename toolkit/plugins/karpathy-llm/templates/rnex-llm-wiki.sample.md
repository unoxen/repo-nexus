# Multi-Repo LLM Wiki: Architecture & Knowledge Index

> Based on the **Andrej Karpathy LLM Wiki Pattern**: Compiling raw multi-repo codebase knowledge into persistent, indexed Markdown notes that compound across AI coding sessions.

---

## 1. Workspace Overview

* **Workspace Name:** `my-multi-repo-workspace`
* **Orchestrator:** Repo Nexus (`rnex`)
* **Primary Scope:** Member repositories under `./repos/`

---

## 2. Member Repository Topology & Boundaries

| Repository | Path / Scope | Primary Tech Stack | Role & Responsibility |
| :--- | :--- | :--- | :--- |
| `backend-api` | `repos/backend-api` | Node.js / TypeScript | REST & GraphQL endpoints, database access |
| `frontend-web` | `repos/frontend-web` | React / Vite | User interface, client-side state management |
| `shared-contracts` | `repos/shared-contracts` | TypeScript / JSON Schema | Shared types, DTOs, and protocol definitions |

---

## 3. Cross-Repository Contracts & Protocols

### 3.1. API Contracts
* Detail endpoints, payloads, and auth requirements connecting `frontend-web` to `backend-api`.

### 3.2. Shared Types & Data Models
* Document how type definitions in `shared-contracts` are propagated and consumed by member services.

---

## 4. Key Architectural Decisions (ADR Log)

### ADR-001: Independent Git Repositories over Monorepo
* **Date:** YYYY-MM-DD
* **Decision:** Keep repositories completely independent without Git submodules. Orchestrate via Repo Nexus Virtual Meta-Repo.
* **Consequences:** Autonomous CI/CD per repo; AI assistants maintain shared context via `AGENTS.md` and `behavioral.md`.

---

## 5. Agent Instructions for Updating This Wiki

1. When introducing a new cross-repo API or altering an existing contract, update **Section 3**.
2. When registering a new member repository via `rnex add`, add its entry to **Section 2**.
3. Keep entries concise and factual. Do not duplicate code; provide references to source files.
