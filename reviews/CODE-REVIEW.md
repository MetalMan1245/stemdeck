# Code Review — Uncommitted Changes (main branch)

**Scope:** `desktop/src-tauri/src/main.rs`, `desktop/src-tauri/Cargo.toml`, `desktop/ui/setup.js`
**Date:** 2026-05-25

---

## Tool Availability

| Tool | Status |
|------|--------|
| Architecture & Design (manual) | Ran |
| Regression History (`git log`) | Ran |
| Go Static Analysis | N/A — no `.go` files |
| Protobuf Linting | N/A — no `.proto` files |

---

## Consolidated Findings

| Severity | ID | Finding | Source | Tracked |
|----------|----|---------|--------|---------|
| HIGH | 1 | **`BackendState` two independent `Mutex`es can diverge.** `main.rs:28-31`. `child` and `url` must be co-located in a single `Mutex<Option<BackendHandles>>` to enforce the both-Some/both-None invariant atomically. Pre-existing. | ARCH-2 | #133 |
| MEDIUM | 2 | **Path resolution duplicated** across `python_path()`, `ffmpeg_path()`, `ffprobe_path()`. `main.rs:~1461–1503`. Env-var override + fallback logic repeated three times. Pre-existing. | DEP-1 | #134 |
| LOW | 3 | ~~**Missing `// SAFETY:` comment on `libc::kill()`.**~~ | ARCH-3 | **FIXED** in this PR |

---

## Regression History

No regressions detected. All changes are additive. 30-minute timeout preserved in `download_file_blocking`. Prior fix logic in `verify_runtime_pack`, Python validation, and `setup.js` error hints is intact.

---

## Recommended Fix Order

1. **#1 (HIGH) — BackendState Mutex consolidation.** Tracked in #133. Separate PR; pre-existing design debt. ~1 hour effort.
2. **#2 (MEDIUM) — Path resolver consolidation.** Tracked in #134. Separate refactor PR; pre-existing. ~30 min effort.
