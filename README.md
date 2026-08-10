# ShreeRam CRM

Real Estate Lead Management CRM for multi-platform use (Android, iOS, Web).

## Stack (planned)

- **Frontend:** Flutter (Android / iOS / Web)
- **Backend:** Laravel REST API (modular monolith)
- **Database:** MySQL

## Status

Architecture phase complete. **No application implementation until architecture approval.**

See the full technical plan:

→ [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

## Environment

Documented variables (no secrets): [`.env.example`](.env.example)

Never commit `.env` files, Meta tokens, API keys, or database passwords.

## VPS safety

This app must be deployed in an **isolated** project directory/database/vhost only.  
Do not modify other projects on the shared demo VPS.
