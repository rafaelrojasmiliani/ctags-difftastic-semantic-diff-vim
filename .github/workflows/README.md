# Workflow reference — vim-semantic-ctags-diff

## `ci.yml`

| Field | Value |
|-------|-------|
| **Goal** | Block merges that break Python semantic diffs or Vim plugin helpers |
| **Methodology** | One job, four numbered stages (`S01`–`S04`), no secrets, read-only `contents` |
| **Used by** | GitHub Actions on `push` / `pull_request` → `main`; README CI badge |

### Steps

| Step | Name | What it does |
|------|------|--------------|
| **S01** | Checkout repository and submodules | `actions/checkout@v4` with `submodules: recursive` so `submodules/semantic-ctags-diff` is present at the commit recorded in the parent repo |
| **S02** | Install system packages | `apt`: `git` (temp-repo tests), `universal-ctags` (symbol parsing), `vim` (headless self-checks) |
| **S03** | Python unit tests | `setup-python` 3.12 → `pip install -e ".[dev]"` in submodule → `pytest -v` |
| **S04** | Vim plugin self-checks | `vim -N -u NONE -es -S test/nav_parse.vim` and `test/cache.vim`; non-zero exit on `assert_equal` failure |

### Failure triage

- **S03 pytest** — logic bug in `semantic_branch_diff`; fix in submodule, bump pointer here.
- **S04 nav_parse** — markdown symbol-line parser regression in `autoload/semantic_ctags_diff.vim`.
- **S04 cache** — `/tmp` cache naming or read/write regression in the same autoload file.
- **Submodule missing** — ensure `.gitmodules` URL is reachable and CI uses `submodules: recursive`.
