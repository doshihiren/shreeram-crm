# Approved product decisions (implementation defaults)

| Decision | Choice |
|----------|--------|
| Demo URL | `https://aweliontech.com/shreeram-crm` |
| New Meta lead assignment | Unassigned pool (manual assign by Owner/Admin) |
| Duplicate handling | Create linked duplicate row (`is_duplicate` + `duplicate_of_lead_id`); never auto-delete |
| Flutter state | Riverpod 3 (`Notifier`) |
| Lost modeling | Configurable stage with `is_lost=true` (seeded `LOST`) |
| Finance fields | Out of scope for V1 |

See `ARCHITECTURE.md` for full design.
