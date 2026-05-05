## Unreleased

- Add explicit unknown-freshness rejection for durable micro-state stale-read
  validation and tests for bounded recovery, cursor, lease-view, and stale-read
  states.
- Expand source policy tests to cover all repo-owned code for dynamic atom
  construction, direct atom conversion, `Module.concat`, and pattern-engine
  APIs; replace dynamic test process names with finite source-owned atoms.
- Add governed durable authority validation for recovered state, initial-state
  round trips, sync writes, and node heartbeat metadata.
- Keep standalone environment-backed object storage configuration intact while
  rejecting authority-bearing sticky-placement environment names in governed
  supervisors.

## 0.1.1 (2026-04-29) 🚀
- Initial release!
