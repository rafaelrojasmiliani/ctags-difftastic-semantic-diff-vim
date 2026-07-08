# GitHub Actions — vim-semantic-ctags-diff

Continuous integration for the **Vim plugin** repository
[`ctags-difftastic-semantic-diff-vim`](https://github.com/rafaelrojasmiliani/ctags-difftastic-semantic-diff-vim).

## Inventory

| File | Goal | Methodology | Where used |
|------|------|-------------|------------|
| [`workflows/ci.yml`](workflows/ci.yml) | Verify Python library + Vim plugin on every merge candidate | Single `ubuntu-latest` job: checkout with submodules → install `git`/`ctags`/`vim` → `pytest` in submodule → headless `test/*.vim` | Triggered on **push** and **pull_request** to `main`; badge in root [`README.md`](../README.md) |
| [`workflows/README.md`](workflows/README.md) | Step-by-step reference for `ci.yml` | Documents each `S01`–`S04` block and failure modes | Maintainers editing CI |

## Relationship to submodule CI

The Python library lives in
[`submodules/semantic-ctags-diff`](https://github.com/rafaelrojasmiliani/semantic-ctags-diff)
and has **its own** workflow at
`submodules/semantic-ctags-diff/.github/workflows/ci.yml`.

| Repository | CI scope |
|------------|----------|
| **semantic-ctags-diff** (submodule) | `pytest` only — fast feedback when changing Python |
| **ctags-difftastic-semantic-diff-vim** (this repo) | `pytest` **plus** Vim self-checks — full integration gate |

When you bump the submodule pointer here, this workflow runs `pytest` against that
pinned commit and the Vim checks against the plugin tree at the same revision.

## Badge

Root README shows:

```markdown
[![CI](https://github.com/rafaelrojasmiliani/ctags-difftastic-semantic-diff-vim/actions/workflows/ci.yml/badge.svg)](https://github.com/rafaelrojasmiliani/ctags-difftastic-semantic-diff-vim/actions/workflows/ci.yml)
```

Green badge = last `main` workflow run succeeded.
