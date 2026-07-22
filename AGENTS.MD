# AGENTS.md

# Sarthi AI Coding Instructions

## Project Overview

Sarthi is a fleet management and emergency vehicle dispatch platform.

Primary goals:
- Real-time vehicle tracking
- Nearest vehicle dispatch
- Accurate road routing
- Clean, maintainable code
- Minimal regressions

---

## Tech Stack

Backend
- Django
- Django REST Framework
- PostgreSQL
- PostGIS

Frontend
- React
- TypeScript
- Leaflet

Mobile
- Flutter

Routing
- Self-hosted OSRM

Authentication
- JWT

---

## Architecture

Vehicle GPS
↓
PostGIS (candidate search)
↓
OSRM (road distance & route)
↓
Dispatch ranking
↓
Frontend route visualization

---

## Coding Principles

- Make the smallest possible change.
- Preserve existing architecture.
- Reuse existing code whenever possible.
- Do not rewrite working modules.
- Do not introduce unnecessary dependencies.
- Keep code readable and production-ready.

---

## Routing Rules

- OSRM is the source of truth for road distance.
- Never rank vehicles using straight-line distance.
- Verify longitude/latitude ordering when interacting with OSRM.
- Keep PostGIS for candidate filtering only.
- Return both route geometry and road distance.

---

## Performance

- Avoid unnecessary API calls.
- Prefer OSRM Table API when comparing multiple vehicles.
- Keep database queries efficient.
- Do not introduce N+1 queries.

---

## Before Making Changes

Always:

1. Understand the existing implementation.
2. Identify the root cause.
3. Modify only the necessary files.
4. Explain what changed.
5. Mention any trade-offs.

---

## Output Format

For every task provide:

1. Root cause
2. Files modified
3. Code changes
4. Why the fix works
5. Possible future improvements

---

## General Rules

- Do not remove existing functionality.
- Follow existing coding style.
- Keep functions small and maintainable.
- Avoid duplicate logic.
- Preserve API compatibility unless explicitly requested.

When requirements are unclear, inspect the codebase before making assumptions.