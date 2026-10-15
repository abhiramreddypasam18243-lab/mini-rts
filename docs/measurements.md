# Measurements

Performance targets marked *(initial target)* in SPEC section 12, with the measured values.

| AC | Target | Measured | Date | Machine and method |
| --- | --- | --- | --- | --- |
| AC-18 | Worst-case 48 × 48 path ≤ 5 ms | **2.0 ms** (average of 20 runs, 1,175-step serpentine maze) | 2026-10-15 | Laptop, WSL2 Ubuntu 24.04, Godot 4.7.2 headless, `test_ac_18_worst_case_48_by_48_within_budget` |
| AC-83 | First-load transfer ≤ 20 MB (compressed) | **10.2 MB** (`index.wasm` 10.1 MB gzipped, `.js` 69 KB, `.pck` 26 KB) | 2026-10-15 | `curl` with `Accept-Encoding: gzip` against the container and GitHub Pages |
