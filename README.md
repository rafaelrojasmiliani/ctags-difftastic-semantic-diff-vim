# vim-semantic-ctags-diff

[![CI](https://github.com/rafaelrojasmiliani/ctags-difftastic-semantic-diff-vim/actions/workflows/ci.yml/badge.svg)](https://github.com/rafaelrojasmiliani/ctags-difftastic-semantic-diff-vim/actions/workflows/ci.yml)

Vim 8 plugin with two complementary features:

1. **Semantic branch diffs** — calls the
   [semantic-branch-diff](https://github.com/rafaelrojasmiliani/semantic-ctags-diff)
   Python tool (PyDriller + ctags) and opens the result in Markdown/JSON scratch
   buffers.
2. **Difftastic in Vim** — a Fugitive-style file diff rendered with
   [difftastic](https://github.com/Wilfred/difftastic) (`difft`) via
   `:Gdifftastic` / `:Gvdifftastic`. This ports difftastic's structural diff into
   a Vim scratch window.

Works with **vim-fugitive** worktree detection (submodules) and optional
**vim-flog** log navigation. The two features are independent: difftastic needs
only `git` + `difft`, and the Python module gracefully handles difftastic being
absent.

**Ctags note:** This plugin does **not** require ctags built with JSON output
(`--output-format=json`). The Python tool runs ordinary ctags (`-f tags`) and
reads the classic tags file via `python-ctags3`. Universal Ctags is recommended;
Exuberant Ctags works with reduced C++ metadata. `:SemanticCtagsDiffJson` refers
to the semantic **report** format, not ctags JSON.

## How it works: ctags line ranges

Everything this plugin shows in a semantic diff comes from **ctags symbol line
ranges** plus **Git line changes**:

| Layer | Role |
|-------|------|
| Git | Which files/lines changed between `base` and `head` |
| ctags | Each symbol’s start/end line, kind, and qualified name |
| Python | Map changed lines → symbols; classify added/removed/modified |

The Vim plugin does **not** parse ctags itself. It calls
`semantic-branch-diff`, which runs ctags on file snapshots and matches Git diff
lines to enclosing symbols (function, method, class, …).

### Example

You change line 13 inside a method body:

```cpp
void RobotController::configure(double x) {  // ctags: lines 12–15
  m_gain = x;   // ← you edit this line (line 13)
}
```

- **Plain git diff:** `@@ … +13,1 @@` — one line changed.
- **Semantic diff:** `modified function ImFusion::Robotics::RobotController::configure`
  because line 13 falls inside ctags range 12–15.

From Vim:

```vim
:SemanticCtagsDiff main HEAD
```

The Markdown scratch buffer lists **symbols**, not just hunks. JSON output
includes `new_range: [12, 15]` and `flog_limit: "12,15:src/RobotController.cpp"`
for Flog navigation.

Run the bundled example (no Git repo needed):

```bash
cd submodules/semantic-ctags-diff
semantic-branch-diff \
  --old-dir examples/01_added_methods/old \
  --new-dir examples/01_added_methods/new \
  --format markdown
```

See the Python library README for the full model and limitations (file-scope
changes, untagged regions, estimated end lines on Exuberant ctags).

## Overview

```
:SemanticCtagsDiff main HEAD
        │
        ▼
  semantic-branch-diff (Python)
        │
        ▼
  Markdown scratch buffer
  (symbols added / removed / modified)
```

### Screenshot placeholders

<!-- ![Markdown semantic diff](docs/screenshots/markdown-diff.png) -->
<!-- ![JSON output](docs/screenshots/json-diff.png) -->
<!-- ![Debug log](docs/screenshots/debug-log.png) -->

_Text placeholders — add screenshots under `docs/screenshots/` when available._

## Requirements

| Tool | Required |
|------|----------|
| Vim 8+ | Yes |
| Git | Yes |
| Python 3 + PyDriller + python-ctags3 | For semantic diff (importable; no pip install of this repo) |
| Universal Ctags (or Exuberant) | For semantic diff — classic tags file, **not** JSON output |
| difftastic (`difft`) | For `:Gdifftastic` / `:Gvdifftastic` only |
| vim-fugitive | Recommended |
| vim-flog | Optional |

The semantic diff and difftastic features are independent — you can use
`:Gdifftastic` with only `git` + `difft`, even without Python or ctags.

## Installation

### Plugin manager (vim-plug)

```vim
Plug 'rafaelrojasmiliani/ctags-difftastic-semantic-diff-vim'
```

Then:

```bash
git submodule update --init --recursive
```

Inside Vim:

```vim
:helptags /path/to/plugin/doc
:help semantic-ctags-diff
```

No `pip install` of `semantic-branch-diff` is required. The plugin runs the
submodule source directly:

```bash
PYTHONPATH=submodules/semantic-ctags-diff python3 -m semantic_branch_diff.cli ...
```

Python still needs importable **PyDriller** and **python-ctags3** (system packages,
your own venv, or `submodules/semantic-ctags-diff/.venv/` if you create one for
deps only).

### Pathogen / native package

Clone into your bundle path and run the same submodule + pip steps.

## Configuration

```vim
let g:semantic_ctags_diff_default_base = 'main'
let g:semantic_ctags_diff_python = 'python3'
let g:semantic_ctags_diff_ctags = 'ctags'
let g:semantic_ctags_diff_use_fugitive_worktree = 1
let g:semantic_ctags_diff_debug = 0
let g:semantic_ctags_diff_open_cmd = 'botright new'
let g:semantic_ctags_diff_cache = 1
let g:semantic_ctags_diff_cache_dir = '/tmp/semantic_ctags_diff'

" Optional: explicit Python source tree (default: auto-detect submodules/semantic-ctags-diff)
" let g:semantic_ctags_diff_root = '/path/to/semantic-ctags-diff'

" Optional: Python with PyDriller + python-ctags3 (or submodule .venv/bin/python3)
" let g:semantic_ctags_diff_python = '/path/to/submodules/semantic-ctags-diff/.venv/bin/python3'

" Optional: extra CLI flags
" let g:semantic_ctags_diff_extra_args = ['--no-pydriller-methods']

" Difftastic (:Gdifftastic / :Gvdifftastic)
let g:semantic_ctags_diff_difft = 'difft'
let g:semantic_ctags_diff_difftastic_display = 'side-by-side'  " or 'inline'
let g:semantic_ctags_diff_difftastic_context = 3
```

Python project auto-detection looks for:

- `submodules/semantic-ctags-diff/pyproject.toml`
- `submodules/sematic-ctags-diff/pyproject.toml` (typo fallback)

## Result cache

`:SemanticCtagsDiff` can be slow on large repos. Successful results are cached
under `/tmp/semantic_ctags_diff/<repo-name>/` (never in your workspace), named
after the **resolved commits** being compared:

```
/tmp/semantic_ctags_diff/my-project/a1b2c3d4..e5f6g7h8.markdown
/tmp/semantic_ctags_diff/my-project/a1b2c3d4..e5f6g7h8.json
```

When `main` or `HEAD` moves to a new commit, the filename changes and the diff
is recomputed automatically. Same commit pair → instant reload.

- Repeat runs echo `using cached result`.
- `:SemanticCtagsDiffRefresh` always bypasses the cache and re-runs Python.
- `:SemanticCtagsDiffClearCache` deletes all cached files.
- Disable with `let g:semantic_ctags_diff_cache = 0`.

## Commands

| Command | Description |
|---------|-------------|
| `:SemanticCtagsDiff [base] [head] [file]` | Markdown scratch buffer (optional file scope) |
| `:SemanticCtagsDiffJson [base] [head] [file]` | JSON scratch buffer (optional file scope) |
| `:SemanticCtagsDiffFile [base] [head]` | Markdown diff for **current buffer** file |
| `:SemanticCtagsDiffFileJson [base] [head]` | JSON diff for **current buffer** file |
| `:SemanticCtagsDiffCurrent` | Use configured defaults |
| `:SemanticCtagsDiffMain` | `main` vs `HEAD` |
| `:SemanticCtagsDiffOriginMain` | `origin/main` vs `HEAD` |
| `:SemanticCtagsDiffRefresh` | Re-run last query (bypasses cache) |
| `:SemanticCtagsDiffClearCache` | Delete cached results from `/tmp` |
| `:SemanticCtagsDiffCopyCommand` | Copy shell command to `+` register |
| `:SemanticCtagsDiffDebugLog` | Open debug log |
| `:SemanticCtagsDiffClearDebugLog` | Clear debug log |
| `:SemanticCtagsDiffFlog` | Flog companion (if flog installed) |
| `:SemanticCtagsDiffFlogSymbol` | Pick symbol → Flog history in a new tab (if flog installed) |
| `:FlogSymbol` / `:FlogFunction` / `:FlogClass` / `:FlogNamespace` | Cursor symbol history in a **new tab** |
| `:FlogsplitSymbol` / `:FlogsplitFunction` / ... | Cursor symbol history in a split |
| `:FlogFile` / `:FlogsplitFile` | **Single-file** history (`-path=`); `<CR>` = difftastic diff of that commit, that file only |
| `:FlogDifftastic` | Same as `<CR>` above, by name |
| `:FlogInclude` / `:FlogsplitInclude` | `#include` under cursor → history of the resolved header |
| `:Gdifftastic [ref]` | Difftastic diff of current file vs `ref` (default `HEAD`), horizontal split |
| `:Gvdifftastic [ref]` | Same, vertical split |

### Tab completion

`:SemanticCtagsDiff`, `:SemanticCtagsDiffJson`, and related commands complete
**branches and refs** on the first two arguments (`<Tab>` after base or head).
When vim-fugitive is installed, completion uses `fugitive#CompleteObject`.

On the **third argument** of `:SemanticCtagsDiff` / `:SemanticCtagsDiffJson`,
completion offers tracked repo files (filtered by `g:semantic_ctags_diff_include`),
using `fugitive#CompletePath` when available.

`:SemanticCtagsDiffFile` uses the current buffer path — no file argument needed.

### Suggested mappings (not installed by default)

```vim
nnoremap <leader>sd :SemanticCtagsDiff<CR>
nnoremap <leader>sj :SemanticCtagsDiffJson<CR>
nnoremap <leader>sr :SemanticCtagsDiffRefresh<CR>
nnoremap <leader>sl :SemanticCtagsDiffDebugLog<CR>
nnoremap <leader>dt :Gvdifftastic<CR>
```

## Difftastic in Vim

This plugin also **ports difftastic into Vim** as a Fugitive-style file diff.
`difft` is a structural (syntax-aware) diff tool; these commands run it as git's
external diff and render the result in a scratch buffer.

| Command | Effect |
|---------|--------|
| `:Gdifftastic` | Difftastic diff of the current file vs `HEAD`, horizontal split |
| `:Gdifftastic origin/main` | vs any ref (branch, tag, commit) |
| `:Gvdifftastic [ref]` | Same, vertical split |

Under the hood it runs, for the current file:

```bash
DFT_DISPLAY=side-by-side DFT_COLOR=always \
  git -C <worktree> -c diff.external=difft --no-pager diff --ext-diff <ref> -- <file>
```

So difftastic receives the old/new blobs straight from git, exactly like
`:Gdiffsplit` does for a normal diff. Output is a read-only scratch buffer with a
header (file, ref, repo, exact command).

### Colours

Removals are **red**, additions are **green**, down to the sub-word spans
difftastic identifies — in `int modify() { return 4242; }` only `4242` lights up,
not the whole line.

This needs `DFT_COLOR=always` rather than Vim syntax rules, because difftastic
signals additions and removals **only** through colour: its plain output has no
`+`/`-` gutter, and in side-by-side mode a changed line is structurally
identical to an unchanged one. The plugin therefore strips the ANSI escapes out
of the buffer text and re-applies them as `matchaddpos()` highlights.

Override the groups in your colorscheme:

```vim
highlight SemanticCtagsDiffRemoved ctermfg=Red      guifg=#ff5f5f
highlight SemanticCtagsDiffAdded   ctermfg=Green    guifg=#00d75f
highlight SemanticCtagsDiffFile    ctermfg=Yellow   guifg=#ffd75f
highlight SemanticCtagsDiffDim     ctermfg=DarkGray guifg=#808080
```

| Setting | Default | Meaning |
|---------|---------|---------|
| `g:semantic_ctags_diff_difftastic_color` | `1` | `0` renders plain text |
| `g:semantic_ctags_diff_difftastic_syntax` | `'off'` | `'on'` adds difftastic's language syntax colours, which compete with red/green |
| `g:semantic_ctags_diff_difftastic_max_highlights` | `2000` | Spans per diff before colouring stops (Vim redraw slows as matches grow) |

Notes:

- Requires `difft` on `PATH` (or set `g:semantic_ctags_diff_difft`).
- Independent of the Python module and ctags — works with only `git` + `difft`.
- The commands are defined only if not already present, so they won't clobber
  your own `:Gdifftastic` mapping.
- Configure via `g:semantic_ctags_diff_difftastic_display` (`side-by-side` or
  `inline`) and `g:semantic_ctags_diff_difftastic_context`.

## Jump to a symbol from the report

The report lists **symbol names only**. Press a key on any symbol line to see or
open it:

| Key | Action |
|-----|--------|
| `<CR>` | Depends on the section — see below |
| `gd` | Open the source in the current window |
| `o` | Open the source in a horizontal split |
| `gO` | Open the source in a vertical split |
| `O` | Open the source in a new tab |

`<CR>` does whatever is most useful for the section it is pressed in:

| Section | `<CR>` opens |
|---------|--------------|
| **Changed files** | The file in a **new tab**, with a [difftastic](#difftastic-in-vim) diff of the whole `base..head` change **split below** it. A file git reports as deleted (`D`) does nothing — there is nothing left to open. |
| **Added symbols** | Jumps straight to the symbol. It exists in the working tree, so there is nothing to compare. |
| **Removed / Modified** | A **fugitive vertical diff in a new tab**, cursor on the changed line. |

The vertical diff shows `base:<path>` and `head:<path>` side by side, older
revision on the left. For a **removed** symbol the cursor lands in the *base*
pane, because that is the only revision still containing it; modified symbols
land in *head*. A file that exists in just one revision still opens, undiffed.

| Setting | Default | Meaning |
|---------|---------|---------|
| `g:semantic_ctags_diff_file_difftastic_height` | `20` | Height of the difftastic split |
| `g:semantic_ctags_diff_file_difftastic_split` | `'botright'` | Or `'belowright'` |
| `g:semantic_ctags_diff_file_difftastic_focus` | `0` | `1` jumps into the diff window |

Because the report prints no file or line numbers, every jump resolves its
target from the cached JSON by qualified name. That JSON is fetched
automatically — if you only ran the Markdown report, the first jump fetches it.
All of this requires **vim-fugitive**.

### What the report leaves out

`ctags` tags far more than is useful for reviewing a branch, so the Markdown
report filters and deduplicates (the JSON keeps everything):

| Dropped | Why |
|---------|-----|
| Local variables and free/namespace-scope variables | Too granular to be a reviewable API change |
| Anything under an anonymous namespace (`__anon37a8102f0111`) | The name is generated and differs between the two revisions |
| Repeats of the same `(kind, name)` | A namespace reopened in twenty files is one fact, not twenty |
| File-scope line changes | Line numbers without a symbol are not reviewable; the file list covers "what changed where" |
| Per-file headings in Modified | The same namespace is modified in many files; the name is the fact |

The report instead opens with **Changed files**, a `git --name-status` style
list covering every file git reports — including ones no symbols came out of,
such as binaries or extensions outside `--include`:

```
Changed files
=============

  A Test/General/ControlStreamUtils.cpp
  M Source/Control/RuckigMotionGenerators.cpp
  D Source/Control/OldGenerator.cpp
```

**Class members are kept.** ctags' kind `m` means "class, struct, and union
members" — a *data field*, not a method — so fields now appear under `Members:`
rather than being listed as methods. A member whose container is a namespace
rather than a class is a plain variable and is dropped.

> ponytail: added/modified jumps assume your checkout is at `head`. On a
> different checkout the working file opens but the line may be slightly off;
> use `:Gedit <head>:<path>` for the exact head version.

## Vim / Fugitive / Flog integration

### Fugitive

When vim-fugitive is loaded, repo root uses `FugitiveWorkTree()` so semantic
diffs target the correct worktree inside **submodules** and **nested
submodules**.

Without fugitive, the plugin falls back to:

```bash
git -C <current-file-dir-or-cwd> rev-parse --show-toplevel
```

### Flog

`:SemanticCtagsDiffFlog` opens a raw `base..head` log view as a navigation
companion (less semantic than the Python report).

`:SemanticCtagsDiffFlogSymbol` lists **modified symbols** from the cached JSON
result (using the Python `navigation` list when available), then opens Flog with
`flog_limit` from the JSON. By default it opens a **new tab** (commit graph +
diff), exactly like plain `:Flog`. Set `g:semantic_ctags_diff_flog_open` to
`'Flogsplit'` to open a split instead:

```vim
let g:semantic_ctags_diff_flog_open = 'Flogsplit'  " default: 'Flog' (new tab)
```

### Cursor symbol history: new tab vs split

When vim-flog is installed, `plugin/semantic_ctags_flog.vim` defines two
families for the symbol under the cursor, **only if you have not already
defined them** (e.g. in a legacy `files` script):

| Command | Opens |
|---------|-------|
| `:FlogSymbol`, `:FlogFunction`, `:FlogClass`, `:FlogNamespace` | **New tab** (commit graph + diff), like `:Flog` |
| `:FlogsplitSymbol`, `:FlogsplitFunction`, `:FlogsplitClass`, `:FlogsplitNamespace` | Split of the current window |

Use the `:Flog*` (tab) family when you want the commits and diffs in a separate
view, the same way plain `:Flog` opens a dedicated tab. Both families call
Python `symbol-at` mode — **no Vim ctags parsing**, and **no ctags JSON output**
required:

```bash
semantic-branch-diff --symbol-at --file path.cpp --line 42 --kind function
```

### Single-file Flog (`:FlogFile`, `:FlogInclude`)

Plain `:Flog -path=file.cpp` filters the **commit list** to that file, but the
default flog keys still open the **whole commit** (`<CR>`) or diff all files
(`dd`). These commands fix that:

| Command | Opens |
|---------|-------|
| `:FlogFile` | File history in a **new tab**; `<CR>` and `dd` scoped to that file |
| `:FlogsplitFile` | Same, in a split |
| `:FlogInclude` | Resolve `#include` on cursor → header file history (new tab) |
| `:FlogsplitInclude` | Same, in a split |

Implementation: `Flog -path=<git-relative-path>` plus buffer-local remaps to
vim-flog's path-scoped plugs (`FlogVSplitCommitPathsRight`, `FlogVDiffSplitPathsRight`).
Disable remaps with `let g:semantic_ctags_diff_flog_file_maps = 0`.

#### `<CR>` → difftastic diff of one commit, one file

In a `:FlogFile` graph, pressing `<CR>` on a commit opens a **horizontal split
below** showing the [difftastic](#difftastic-in-vim) diff of **that commit for
that file only** — never the other files in the commit:

```
┌────────────────────────────────┐
│ Flog graph (-path=Source/X.cpp)│   <- cursor stays here
│ * a1b2c3 Fix approx tolerance  │
│ * d4e5f6 Add reset()           │
├────────────────────────────────┤
│ Difftastic — Source/X.cpp      │   <- <CR> fills this, reusing the window
│ Commit: a1b2c3  Fix approx …   │
│ 12  bool isApprox(…)  12 bool… │
└────────────────────────────────┘
```

Pressing `<CR>` on another commit **reuses the same window** instead of stacking
splits, and the cursor stays in the graph so you can keep browsing. `go` still
opens Flog's own whole-commit view. Removals show red and additions green — see
[Colours](#colours).

| Setting | Default | Meaning |
|---------|---------|---------|
| `g:semantic_ctags_diff_flog_difftastic` | `1` | `0` restores Flog's commit view on `<CR>` |
| `g:semantic_ctags_diff_flog_difftastic_height` | `20` | Split height; `0` = even split |
| `g:semantic_ctags_diff_flog_difftastic_split` | `'botright'` | Or `'belowright'` |
| `g:semantic_ctags_diff_flog_difftastic_focus` | `0` | `1` jumps into the diff window |

The diff runs `git -c diff.external=difft diff <sha>^! -- <path>`, so difftastic
receives the blobs straight from git. Root commits have no parent, so they are
diffed against the empty tree instead (`git diff <sha>^!` would otherwise
silently show a working-tree diff).

`#include` resolution searches: directory of the current file → repo root →
common prefixes (`include/`, `src/`, …) → **`git ls-files`** (suffix match) →
`findfile()`. This is **not ctags** — whole-file `Flog -path=`, not symbol
line ranges. System SDK headers outside the repo cannot be opened.

Optional extra search roots:

```vim
let g:semantic_ctags_diff_include_search_dirs = ['/path/to/extra/includes']
```

### Responsibility split (Python vs Vim)

| Concern | Python (`semantic-branch-diff`) | Vim plugin |
|---------|--------------------------------|------------|
| Branch semantic diff | Yes | Invokes CLI, scratch buffers |
| ctags execution + parsing | Yes (`python-ctags3`, classic tags) | No |
| Symbol priority / kind inference | Yes (`symbols.py`) | No |
| `flog_limit` strings | Yes (`navigation.py`) | Uses JSON field |
| Repo worktree detection | — | Yes (Fugitive / git) |
| Flog UI / colors | — | Yes |
| Difftastic file diff (`:Gdifftastic`) | — | Yes (git external diff → scratch) |
| Fugitive commit-prompt difftastic context | — | Not included (see `files` reference) |

This plugin does **not** define Flogsplit commands if you already have custom ones.

## Architecture

```mermaid
flowchart LR
  VimCmd[Vim command] --> Autoload[autoload/semantic_ctags_diff.vim]
  Autoload --> RepoRoot[repo_root]
  Autoload --> PyRoot[python_project_root]
  Autoload --> CLI[build_command]
  CLI --> Shell[system + temp files]
  Shell --> Scratch[open_scratch]
```

## Limitations

- **Synchronous** execution (`system()`); large branches may block Vim.
- Default file extensions target **C/C++**; configure `g:semantic_ctags_diff_include`.
- Does **not** need ctags JSON output; any standard Universal or Exuberant build works.
- **Vim 8 only** — no Neovim-only APIs, no Lua, no `jobstart()`.
- No default mappings.
- `:SemanticCtagsDiffFlogSymbol` requires a prior diff (JSON cache is fetched
  automatically after Markdown runs).
- `:Gdifftastic` renders difftastic's **plain-text** output in a scratch buffer
  (no ANSI colors, not true `vimdiff` mode); it needs `difft` installed.

## Troubleshooting

See `:help semantic-ctags-diff-troubleshooting` for:

- ctags not found
- PyDriller / python-ctags3 import errors (not a missing pip install of this repo)
- Submodule path missing
- Wrong repo root in submodules
- Empty results
- Slow runs

Quick debug:

```vim
let g:semantic_ctags_diff_debug = 1
:SemanticCtagsDiff main HEAD
:SemanticCtagsDiffDebugLog
:SemanticCtagsDiffCopyCommand
```

## License

Same as the parent repository.
