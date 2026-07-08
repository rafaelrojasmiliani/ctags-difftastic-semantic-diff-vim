" autoload/semantic_ctags_diff.vim
" Semantic branch diff integration for Vim 8.

scriptencoding utf-8

let s:last_base = ''
let s:last_head = ''
let s:last_format = ''
let s:last_repo = ''
let s:last_command = ''
let s:last_scratch_bufnr = -1
let s:last_json = {}
let s:debug_log = []
let s:ref_cache = []
let s:ref_cache_repo = ''

" Submodule relative paths (primary + typo fallback).
let s:submodule_paths = [
      \ 'submodules/semantic-ctags-diff',
      \ 'submodules/sematic-ctags-diff',
      \]

" Absolute plugin root, captured at script load time.
" NOTE: <sfile> must be expanded here (script scope), NOT inside a function —
" inside a :function it expands to the function name, not the script path.
" autoload/semantic_ctags_diff.vim -> :h (autoload) -> :h (plugin root).
let s:plugin_root = fnamemodify(expand('<sfile>:p'), ':h:h')

" --- Command entry points ---------------------------------------------------

function! semantic_ctags_diff#cmd_diff(args) abort
  let l:parsed = semantic_ctags_diff#parse_args(a:args)
  call semantic_ctags_diff#run_markdown(l:parsed.base, l:parsed.head)
endfunction

function! semantic_ctags_diff#cmd_diff_json(args) abort
  let l:parsed = semantic_ctags_diff#parse_args(a:args)
  call semantic_ctags_diff#run_json(l:parsed.base, l:parsed.head)
endfunction

function! semantic_ctags_diff#run_current() abort
  call semantic_ctags_diff#run_markdown(
        \ g:semantic_ctags_diff_default_base,
        \ g:semantic_ctags_diff_default_head)
endfunction

function! semantic_ctags_diff#cmd_flog(args) abort
  let l:parsed = semantic_ctags_diff#parse_args(a:args)
  call semantic_ctags_diff#flog(l:parsed.base, l:parsed.head)
endfunction

" --- Argument parsing -------------------------------------------------------

function! semantic_ctags_diff#parse_args(args) abort
  let l:parts = split(a:args)
  if empty(l:parts)
    return {
          \ 'base': g:semantic_ctags_diff_default_base,
          \ 'head': g:semantic_ctags_diff_default_head,
          \ }
  elseif len(l:parts) == 1
    return {'base': l:parts[0], 'head': 'HEAD'}
  else
    return {'base': l:parts[0], 'head': l:parts[1]}
  endif
endfunction

" --- Repo and Python project discovery --------------------------------------

function! semantic_ctags_diff#repo_root() abort
  if get(g:, 'semantic_ctags_diff_use_fugitive_worktree', 1) && exists('*FugitiveWorkTree')
    let l:worktree = FugitiveWorkTree()
    if !empty(l:worktree)
      return fnamemodify(l:worktree, ':p')
    endif
  endif

  let l:start_dir = semantic_ctags_diff#_start_dir()
  let l:cmd = 'git -C ' . shellescape(l:start_dir) . ' rev-parse --show-toplevel 2>/dev/null'
  let l:lines = systemlist(l:cmd)
  if v:shell_error != 0 || empty(l:lines)
    throw 'semantic_ctags_diff: could not determine Git repository root from ' . l:start_dir
  endif
  return fnamemodify(l:lines[0], ':p')
endfunction

function! semantic_ctags_diff#_dbg(msg) abort
  if get(g:, 'semantic_ctags_diff_debug', 0)
    call semantic_ctags_diff#debug(a:msg)
  endif
endfunction

function! semantic_ctags_diff#_plugin_root() abort
  return s:plugin_root
endfunction

function! semantic_ctags_diff#python_project_root() abort
  if !empty(g:semantic_ctags_diff_root)
    let l:root = fnamemodify(g:semantic_ctags_diff_root, ':p')
    call semantic_ctags_diff#_dbg('python_project_root: g:semantic_ctags_diff_root = ' . l:root)
    if !filereadable(l:root . '/pyproject.toml')
      throw 'semantic_ctags_diff: g:semantic_ctags_diff_root has no pyproject.toml: ' . l:root
    endif
    return l:root
  endif

  " Search order: plugin checkout (submodules/ next to plugin/), then the Git
  " repo of the current file, then upward from the current file directory.
  let l:plugin_root = semantic_ctags_diff#_plugin_root()
  call semantic_ctags_diff#_dbg('python_project_root: plugin_root = ' . l:plugin_root)
  let l:found = semantic_ctags_diff#_find_python_root(l:plugin_root)
  if !empty(l:found)
    call semantic_ctags_diff#_dbg('python_project_root: found via plugin_root -> ' . l:found)
    return l:found
  endif

  let l:repo = ''
  try
    let l:repo = semantic_ctags_diff#repo_root()
  catch /.*/
    call semantic_ctags_diff#_dbg('python_project_root: repo_root() failed: ' . v:exception)
  endtry
  if !empty(l:repo)
    call semantic_ctags_diff#_dbg('python_project_root: repo_root = ' . l:repo)
    let l:found = semantic_ctags_diff#_find_python_root(l:repo)
    if !empty(l:found)
      call semantic_ctags_diff#_dbg('python_project_root: found via repo_root -> ' . l:found)
      return l:found
    endif
  endif

  let l:start = semantic_ctags_diff#_start_dir()
  call semantic_ctags_diff#_dbg('python_project_root: start_dir = ' . l:start)
  let l:found = semantic_ctags_diff#_find_python_root(l:start)
  if !empty(l:found)
    call semantic_ctags_diff#_dbg('python_project_root: found via start_dir -> ' . l:found)
    return l:found
  endif

  call semantic_ctags_diff#_dbg('python_project_root: NOT FOUND (checked plugin_root, repo_root, start_dir)')
  throw 'semantic_ctags_diff: Python sources not found (expected submodules/semantic-ctags-diff under ' . l:plugin_root . '). Run: git submodule update --init --recursive'
endfunction

function! semantic_ctags_diff#_find_python_root(start) abort
  let l:dir = fnamemodify(a:start, ':p')
  while !empty(l:dir)
    for l:rel in s:submodule_paths
      let l:candidate = simplify(l:dir . '/' . l:rel)
      if filereadable(l:candidate . '/pyproject.toml')
        call semantic_ctags_diff#_dbg('_find_python_root: matched ' . l:candidate)
        return l:candidate
      endif
    endfor
    let l:parent = fnamemodify(l:dir, ':h')
    if l:parent ==# l:dir
      break
    endif
    let l:dir = l:parent
  endwhile
  call semantic_ctags_diff#_dbg('_find_python_root: no submodule under ' . a:start)
  return ''
endfunction

function! semantic_ctags_diff#_start_dir() abort
  if expand('%') !=# '' && filereadable(expand('%:p'))
    return fnamemodify(expand('%:p'), ':h')
  endif
  return getcwd()
endfunction

" --- CLI construction -------------------------------------------------------

function! semantic_ctags_diff#build_command(base, head, format) abort
  let l:repo = semantic_ctags_diff#repo_root()
  let l:py_root = semantic_ctags_diff#python_project_root()
  let l:prefix = semantic_ctags_diff#_cli_prefix(l:py_root)

  let l:args = [
        \ '--repo', l:repo,
        \ '--base', a:base,
        \ '--head', a:head,
        \ '--format', a:format,
        \ '--ctags', g:semantic_ctags_diff_ctags,
        \ '--include', g:semantic_ctags_diff_include,
        \ ]

  if g:semantic_ctags_diff_debug
    call add(l:args, '--debug')
  endif

  for l:extra in g:semantic_ctags_diff_extra_args
    call add(l:args, l:extra)
  endfor

  let l:escaped_args = []
  for l:arg in l:args
    call add(l:escaped_args, shellescape(l:arg))
  endfor

  return l:prefix . ' ' . join(l:escaped_args, ' ')
endfunction

function! semantic_ctags_diff#_python_executable(py_root) abort
  " Optional submodule venv (deps only — package itself is not pip-installed).
  for l:candidate in [
        \ a:py_root . '/.venv/bin/python3',
        \ a:py_root . '/.venv/bin/python',
        \ ]
    if executable(l:candidate)
      return l:candidate
    endif
  endfor
  return g:semantic_ctags_diff_python
endfunction

function! semantic_ctags_diff#_cli_prefix(py_root) abort
  if !empty(g:semantic_ctags_diff_cli)
    return g:semantic_ctags_diff_cli
  endif

  " Run from source tree: PYTHONPATH=<submodule> python -m semantic_branch_diff.cli
  " No pip install of semantic-branch-diff required.
  let l:py_root_esc = shellescape(a:py_root)
  let l:python = shellescape(semantic_ctags_diff#_python_executable(a:py_root))
  return 'PYTHONPATH=' . l:py_root_esc . ' ' . l:python . ' -m semantic_branch_diff.cli'
endfunction

" --- Result cache (/tmp, never in the workspace) ----------------------------

function! semantic_ctags_diff#_cache_dir() abort
  let l:dir = get(g:, 'semantic_ctags_diff_cache_dir', '/tmp/semantic_ctags_diff')
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p', 0700)
  endif
  return l:dir
endfunction

function! semantic_ctags_diff#_resolve_refs(repo, base, head) abort
  let l:cmd = 'git -C ' . shellescape(a:repo)
        \ . ' rev-parse ' . shellescape(a:base) . ' ' . shellescape(a:head)
        \ . ' 2>/dev/null'
  let l:lines = systemlist(l:cmd)
  if v:shell_error != 0 || len(l:lines) < 2
    return ['', '']
  endif
  return [l:lines[0], l:lines[1]]
endfunction

function! semantic_ctags_diff#_sanitize_cache_name(name) abort
  let l:name = substitute(a:name, '[\/]\+$', '', 'g')
  return substitute(l:name, '[^A-Za-z0-9._-]', '_', 'g')
endfunction

" Per-repo cache folder under /tmp; files named <base_sha>..<head_sha>.<format>.
function! semantic_ctags_diff#_repo_cache_dir(repo) abort
  let l:name = semantic_ctags_diff#_sanitize_cache_name(fnamemodify(a:repo, ':t'))
  if empty(l:name)
    let l:name = 'repo'
  endif
  let l:dir = semantic_ctags_diff#_cache_dir() . '/' . l:name
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p', 0700)
  endif
  return l:dir
endfunction

" cache: {'repo': ..., 'base': <sha>, 'head': <sha>}
function! semantic_ctags_diff#_cache_id(repo, base_sha, head_sha) abort
  return {'repo': a:repo, 'base': a:base_sha, 'head': a:head_sha}
endfunction

function! semantic_ctags_diff#_cache_stem(cache) abort
  return a:cache.base . '..' . a:cache.head
endfunction

function! semantic_ctags_diff#_cache_path(cache, format) abort
  return semantic_ctags_diff#_repo_cache_dir(a:cache.repo) . '/'
        \ . semantic_ctags_diff#_cache_stem(a:cache) . '.' . a:format
endfunction

function! semantic_ctags_diff#_cache_read(cache, format) abort
  let l:path = semantic_ctags_diff#_cache_path(a:cache, a:format)
  if filereadable(l:path)
    return readfile(l:path)
  endif
  return []
endfunction

function! semantic_ctags_diff#_cache_write(cache, format, lines) abort
  if empty(a:lines)
    return
  endif
  call writefile(a:lines, semantic_ctags_diff#_cache_path(a:cache, a:format))
endfunction

function! semantic_ctags_diff#clear_cache() abort
  let l:dir = get(g:, 'semantic_ctags_diff_cache_dir', '/tmp/semantic_ctags_diff')
  if !isdirectory(l:dir)
    echo 'semantic_ctags_diff: cache directory does not exist: ' . l:dir
    return
  endif
  let l:removed = 0
  for l:path in glob(l:dir . '/*', 0, 1)
    if isdirectory(l:path)
      for l:file in glob(l:path . '/*', 0, 1)
        if filereadable(l:file)
          call delete(l:file)
          let l:removed += 1
        endif
      endfor
      call delete(l:path, 'd')
    elseif filereadable(l:path)
      call delete(l:path)
      let l:removed += 1
    endif
  endfor
  echo 'semantic_ctags_diff: cleared ' . l:removed . ' cached file(s) from ' . l:dir
endfunction

function! semantic_ctags_diff#_run_shell(cmd) abort
  let l:stdout_tmp = tempname()
  let l:stderr_tmp = tempname()
  let l:shell_cmd = a:cmd
        \ . ' > ' . shellescape(l:stdout_tmp)
        \ . ' 2> ' . shellescape(l:stderr_tmp)
  call system(l:shell_cmd)
  let l:exit = v:shell_error
  let l:stdout = filereadable(l:stdout_tmp) ? readfile(l:stdout_tmp) : []
  let l:stderr = filereadable(l:stderr_tmp) ? readfile(l:stderr_tmp) : []
  if filereadable(l:stdout_tmp) | call delete(l:stdout_tmp) | endif
  if filereadable(l:stderr_tmp) | call delete(l:stderr_tmp) | endif
  return [l:stdout, l:stderr, l:exit]
endfunction

" --- Execution --------------------------------------------------------------

function! semantic_ctags_diff#run(base, head, format, ...) abort
  try
    let l:repo = semantic_ctags_diff#repo_root()
    let l:py_root = semantic_ctags_diff#python_project_root()
    let l:cmd = semantic_ctags_diff#build_command(a:base, a:head, a:format)
  catch /.*/
    call semantic_ctags_diff#debug('ERROR: ' . v:exception)
    call semantic_ctags_diff#_open_error([v:exception])
    echoerr v:exception
    return
  endtry

  let s:last_base = a:base
  let s:last_head = a:head
  let s:last_format = a:format
  let s:last_repo = l:repo
  let s:last_command = l:cmd

  let l:force = get(a:000, 0, 0)
  let l:use_cache = get(g:, 'semantic_ctags_diff_cache', 1) && !l:force
  let l:cache = {}
  if l:use_cache
    let l:refs = semantic_ctags_diff#_resolve_refs(l:repo, a:base, a:head)
    if !empty(l:refs[0]) && !empty(l:refs[1])
      let l:cache = semantic_ctags_diff#_cache_id(l:repo, l:refs[0], l:refs[1])
    else
      call semantic_ctags_diff#_dbg('cache: could not resolve refs, skipping cache')
    endif
  endif

  call semantic_ctags_diff#debug('--- run ' . a:format . (l:force ? ' (force)' : '') . ' ---')
  call semantic_ctags_diff#debug('repo_root: ' . l:repo)
  call semantic_ctags_diff#debug('python_root: ' . l:py_root)
  call semantic_ctags_diff#debug('command: ' . l:cmd)
  if !empty(l:cache)
    call semantic_ctags_diff#_dbg('cache file: ' . semantic_ctags_diff#_cache_path(l:cache, a:format))
  endif

  let l:stdout_lines = []
  let l:stderr_lines = []
  let l:exit_code = 0
  let l:from_cache = 0

  if !empty(l:cache)
    let l:stdout_lines = semantic_ctags_diff#_cache_read(l:cache, a:format)
    if !empty(l:stdout_lines)
      let l:from_cache = 1
      call semantic_ctags_diff#_dbg('cache hit: ' . a:format)
    endif
  endif

  if !l:from_cache
    let l:result = semantic_ctags_diff#_run_shell(l:cmd)
    let l:stdout_lines = l:result[0]
    let l:stderr_lines = l:result[1]
    let l:exit_code = l:result[2]
  endif

  call semantic_ctags_diff#debug('exit_code: ' . l:exit_code)
  call semantic_ctags_diff#debug('stdout lines: ' . len(l:stdout_lines))
  call semantic_ctags_diff#debug('stderr lines: ' . len(l:stderr_lines))
  if l:from_cache
    call semantic_ctags_diff#debug('source: cache')
  endif

  let l:preview_n = 5
  if !empty(l:stdout_lines)
    call semantic_ctags_diff#debug('stdout preview:')
    for l:line in l:stdout_lines[0 : l:preview_n - 1]
      call semantic_ctags_diff#debug('  ' . l:line)
    endfor
  endif
  if !empty(l:stderr_lines)
    call semantic_ctags_diff#debug('stderr preview:')
    for l:line in l:stderr_lines[0 : l:preview_n - 1]
      call semantic_ctags_diff#debug('  ' . l:line)
    endfor
  endif

  let l:failed = !l:from_cache && (l:exit_code != 0 || (empty(l:stdout_lines) && !empty(l:stderr_lines)))
  if l:failed
    let l:error_lines = ['Semantic Ctags Diff — Error', '']
    call extend(l:error_lines, l:stderr_lines)
    if empty(l:stderr_lines)
      call add(l:error_lines, 'Command failed with exit code ' . l:exit_code)
    endif
    call add(l:error_lines, '')
    call add(l:error_lines, 'Command: ' . l:cmd)
    call semantic_ctags_diff#_open_error(l:error_lines)
    echoerr 'semantic_ctags_diff: command failed (see error buffer or :SemanticCtagsDiffDebugLog)'
    return
  endif

  if !l:from_cache && !empty(l:cache)
    call semantic_ctags_diff#_cache_write(l:cache, a:format, l:stdout_lines)
    call semantic_ctags_diff#_dbg('cache write: ' . a:format)
  endif

  if a:format ==# 'json'
    call semantic_ctags_diff#_store_json(l:stdout_lines)
    let l:title = 'SemanticCtagsDiff JSON'
    let l:ft = 'json'
    let l:body = l:stdout_lines
  else
    let l:title = 'SemanticCtagsDiff'
    let l:ft = 'markdown'
    let l:header = semantic_ctags_diff#_markdown_header(l:repo, a:base, a:head, l:cmd, l:from_cache, l:cache)
    let l:body = l:header + l:stdout_lines
    call semantic_ctags_diff#_fetch_json_for_cache(a:base, a:head, l:cache, l:force)
  endif

  if l:from_cache
    echo 'semantic_ctags_diff: using cached result'
  endif

  call semantic_ctags_diff#open_scratch(l:title, l:body, l:ft)
  if a:format !=# 'json'
    call semantic_ctags_diff#_setup_nav_maps()
  endif
endfunction

" Buffer-local maps to jump from a symbol to its source, mirroring vim-fugitive
" conventions (<CR> same window, o split, gO vsplit, O tab).
function! semantic_ctags_diff#_setup_nav_maps() abort
  nnoremap <buffer><silent> <CR> :call semantic_ctags_diff#open_symbol_under_cursor('edit')<CR>
  nnoremap <buffer><silent> o    :call semantic_ctags_diff#open_symbol_under_cursor('split')<CR>
  nnoremap <buffer><silent> gO   :call semantic_ctags_diff#open_symbol_under_cursor('vsplit')<CR>
  nnoremap <buffer><silent> O    :call semantic_ctags_diff#open_symbol_under_cursor('tab')<CR>
endfunction

function! semantic_ctags_diff#run_markdown(base, head) abort
  call semantic_ctags_diff#run(a:base, a:head, 'markdown')
endfunction

function! semantic_ctags_diff#run_json(base, head) abort
  call semantic_ctags_diff#run(a:base, a:head, 'json')
endfunction

function! semantic_ctags_diff#refresh() abort
  if empty(s:last_base) && empty(s:last_command)
    echoerr 'semantic_ctags_diff: no previous semantic diff to refresh'
    return
  endif
  let l:replace = bufnr('%') == s:last_scratch_bufnr
  call semantic_ctags_diff#run(s:last_base, s:last_head, s:last_format, 1)
  if l:replace && s:last_scratch_bufnr != -1 && bufnr('%') != s:last_scratch_bufnr
    " run() opened a new buffer; close duplicate if needed
  endif
endfunction

function! semantic_ctags_diff#_markdown_header(repo, base, head, cmd, ...) abort
  let l:from_cache = get(a:000, 0, 0)
  let l:cache = get(a:000, 1, {})
  let l:lines = [
        \ 'Semantic Ctags Diff',
        \ '===================',
        \ '',
        \ 'Repo: ' . a:repo,
        \ 'Base: ' . a:base,
        \ 'Head: ' . a:head,
        \ 'Command: ' . a:cmd,
        \ ]
  if l:from_cache && !empty(l:cache)
    call add(l:lines, 'Source: cached (' . semantic_ctags_diff#_cache_path(l:cache, 'markdown') . ')')
  endif
  call add(l:lines, '')
  return l:lines
endfunction

function! semantic_ctags_diff#_json_cache_id_for(base, head) abort
  if !get(g:, 'semantic_ctags_diff_cache', 1)
    return {}
  endif
  try
    let l:repo = !empty(s:last_repo) ? s:last_repo : semantic_ctags_diff#repo_root()
    let l:refs = semantic_ctags_diff#_resolve_refs(l:repo, a:base, a:head)
    if empty(l:refs[0]) || empty(l:refs[1])
      return {}
    endif
    return semantic_ctags_diff#_cache_id(l:repo, l:refs[0], l:refs[1])
  catch /.*/
    return {}
  endtry
endfunction

function! semantic_ctags_diff#_fetch_json_for_cache(base, head, cache, force) abort
  " Silently fetch JSON for FlogSymbol picker / added-symbol navigation.
  try
    let l:use_cache = get(g:, 'semantic_ctags_diff_cache', 1) && !a:force && !empty(a:cache)
    if l:use_cache
      let l:cached = semantic_ctags_diff#_cache_read(a:cache, 'json')
      if !empty(l:cached)
        call semantic_ctags_diff#_store_json(l:cached)
        call semantic_ctags_diff#_dbg('cache hit: json (navigation)')
        return
      endif
    endif

    let l:cmd = semantic_ctags_diff#build_command(a:base, a:head, 'json')
    let l:result = semantic_ctags_diff#_run_shell(l:cmd)
    if l:result[2] == 0 && !empty(l:result[0])
      call semantic_ctags_diff#_store_json(l:result[0])
      if l:use_cache
        call semantic_ctags_diff#_cache_write(a:cache, 'json', l:result[0])
        call semantic_ctags_diff#_dbg('cache write: json')
      endif
    endif
  catch /.*/
    " Cache fetch is best-effort.
  endtry
endfunction

function! semantic_ctags_diff#_store_json(lines) abort
  if !exists('*json_decode')
    let s:last_json = {}
    return
  endif
  let l:text = join(a:lines, "\n")
  try
    let s:last_json = json_decode(l:text)
  catch /.*/
    let s:last_json = {}
  endtry
endfunction

function! semantic_ctags_diff#_open_error(lines) abort
  call semantic_ctags_diff#open_scratch('SemanticCtagsDiff Error', a:lines, 'log')
endfunction

" --- Scratch buffers --------------------------------------------------------

function! semantic_ctags_diff#open_scratch(title, lines, filetype) abort
  let l:reuse = bufnr('%') == s:last_scratch_bufnr && s:last_scratch_bufnr != -1
  if l:reuse
    setlocal modifiable
    silent %delete _
  else
    execute g:semantic_ctags_diff_open_cmd
    let s:last_scratch_bufnr = bufnr('%')
  endif

  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nowrap
  setlocal modifiable

  call setline(1, a:lines)
  setlocal nomodifiable
  execute 'setlocal filetype=' . a:filetype
  execute 'file ' . fnameescape(a:title)
endfunction

" --- Debug log --------------------------------------------------------------

function! semantic_ctags_diff#debug(msg) abort
  let l:ts = strftime('%Y-%m-%d %H:%M:%S')
  call add(s:debug_log, l:ts . ' ' . a:msg)
endfunction

function! semantic_ctags_diff#debug_log() abort
  if empty(s:debug_log)
    call semantic_ctags_diff#open_scratch('SemanticCtagsDiff Debug', ['(empty debug log)'], 'log')
    return
  endif
  call semantic_ctags_diff#open_scratch('SemanticCtagsDiff Debug', s:debug_log, 'log')
endfunction

function! semantic_ctags_diff#clear_debug_log() abort
  let s:debug_log = []
  echo 'semantic_ctags_diff: debug log cleared'
endfunction

function! semantic_ctags_diff#copy_command() abort
  if empty(s:last_command)
    echoerr 'semantic_ctags_diff: no command recorded yet'
    return
  endif
  let @+ = s:last_command
  echo 'Copied to clipboard: ' . s:last_command
endfunction

" --- Ref completion ---------------------------------------------------------

function! semantic_ctags_diff#complete_ref(arglead, cmdline, cursorpos) abort
  " A customlist completion function MUST always return a List; any thrown
  " error (e.g. E282 if Vim's temp dir is missing) would otherwise make Vim
  " substitute 0 and raise E1303. Wrap everything and degrade to no matches.
  try
    let l:repo = semantic_ctags_diff#repo_root()

    if s:ref_cache_repo !=# l:repo
      let l:cmd = 'git -C ' . shellescape(l:repo)
            \ . ' for-each-ref --format=%(refname:short) refs/heads refs/remotes 2>/dev/null'
      let l:refs = systemlist(l:cmd)
      let s:ref_cache = type(l:refs) == v:t_list ? l:refs : []
      " Mark cached only after a successful populate, so a transient failure
      " (e.g. E282 temp-dir error) does not poison the cache with stale data.
      let s:ref_cache_repo = l:repo
    endif

    if empty(a:arglead)
      return s:ref_cache
    endif
    return filter(copy(s:ref_cache), 'v:val =~# ''^'' . escape(a:arglead, ''\'')')
  catch /.*/
    call semantic_ctags_diff#_dbg('complete_ref failed: ' . v:exception)
    return []
  endtry
endfunction

" --- Flog integration (optional) --------------------------------------------

function! semantic_ctags_diff#flog(base, head) abort
  if exists(':Flog') != 2
    echoerr 'semantic_ctags_diff: vim-flog is not installed'
    return
  endif
  " vim-flog uses single-dash args parsed by splitting on spaces; -rev= runs
  " `git log <range>`. Do NOT shellescape (quotes would reach git literally).
  let l:range = a:base . '..' . a:head
  call semantic_ctags_diff#_dbg('flog: Flog -rev=' . l:range)
  execute 'Flog -rev=' . fnameescape(l:range)
endfunction

function! semantic_ctags_diff#flog_symbol() abort
  if exists(':Flog') != 2
    echoerr 'semantic_ctags_diff: vim-flog is not installed'
    return
  endif

  if empty(s:last_json)
    if !empty(s:last_base) && !empty(s:last_head)
      let l:cache = semantic_ctags_diff#_json_cache_id_for(s:last_base, s:last_head)
      call semantic_ctags_diff#_fetch_json_for_cache(s:last_base, s:last_head, l:cache, 0)
    endif
  endif

  if empty(s:last_json) || type(s:last_json) != v:t_dict
    echoerr 'semantic_ctags_diff: no JSON result available; run :SemanticCtagsDiffJson first'
    return
  endif

  let l:choices = semantic_ctags_diff#_collect_symbol_choices(s:last_json)
  if empty(l:choices)
    echo 'semantic_ctags_diff: no modified symbols in last diff'
    return
  endif

  let l:labels = map(copy(l:choices), {_, v -> v.label})
  let l:idx = inputlist(l:labels)
  if l:idx < 1
    return
  endif

  let l:choice = l:choices[l:idx - 1]
  call semantic_ctags_diff#_open_symbol_in_flog(l:choice)
endfunction

function! semantic_ctags_diff#_collect_symbol_choices(json) abort
  " Prefer Python-built navigation list (semantic_branch_diff.navigation).
  if type(a:json) == v:t_dict && has_key(a:json, 'navigation') && !empty(a:json.navigation)
    return map(copy(a:json.navigation), {_, v -> {
          \ 'label': get(v, 'label', ''),
          \ 'path': get(v, 'path', get(v, 'file', '')),
          \ 'name': get(v, 'qualified_name', get(v, 'name', '')),
          \ 'kind': get(v, 'kind', 'symbol'),
          \ 'line': get(v, 'line', 1),
          \ 'flog_limit': get(v, 'flog_limit', ''),
          \ }})
  endif

  let l:choices = []
  if !has_key(a:json, 'files')
    return l:choices
  endif
  for l:file in a:json.files
    if !has_key(l:file, 'modified_symbols')
      continue
    endif
    for l:sym in l:file.modified_symbols
      let l:path = has_key(l:file, 'path') ? l:file.path : ''
      let l:name = has_key(l:sym, 'qualified_name') ? l:sym.qualified_name : get(l:sym, 'name', '')
      let l:kind = get(l:sym, 'kind', 'symbol')
      let l:range = has_key(l:sym, 'new_range') ? l:sym.new_range : []
      let l:line = !empty(l:range) ? l:range[0] : 1
      let l:end = !empty(l:range) && len(l:range) >= 2 ? l:range[1] : l:line
      let l:flog = get(l:sym, 'flog_limit', l:line . ',' . l:end . ':' . l:path)
      let l:label = get(l:sym, 'label', l:path . ': ' . l:kind . ' ' . l:name)
      call add(l:choices, {
            \ 'label': l:label,
            \ 'path': l:path,
            \ 'name': l:name,
            \ 'kind': l:kind,
            \ 'line': l:line,
            \ 'flog_limit': l:flog,
            \ })
    endfor
  endfor
  return l:choices
endfunction

" Resolve the flog command used to open history. Defaults to :Flog, which opens
" a new tab (commit graph + diff), matching plain :Flog. Configurable via
" g:semantic_ctags_diff_flog_open ('Flog' = tab, 'Flogsplit' = split, ...).
" Falls back to whichever flog command actually exists.
function! semantic_ctags_diff#_flog_open_cmd() abort
  let l:pref = get(g:, 'semantic_ctags_diff_flog_open', 'Flog')
  if exists(':' . l:pref) == 2
    return l:pref
  endif
  if exists(':Flog') == 2
    return 'Flog'
  endif
  if exists(':Flogsplit') == 2
    return 'Flogsplit'
  endif
  return ''
endfunction

function! semantic_ctags_diff#_open_symbol_in_flog(choice) abort
  let l:open = semantic_ctags_diff#_flog_open_cmd()
  if !empty(a:choice.flog_limit) && !empty(l:open)
    echo 'Flog history for ' . get(a:choice, 'label', a:choice.name) . ' [' . a:choice.flog_limit . ']'
    call semantic_ctags_diff#_dbg('flog picker: ' . l:open . ' -limit=' . a:choice.flog_limit)
    execute l:open . ' -limit=' . fnameescape(a:choice.flog_limit)
    return
  endif

  let l:repo = !empty(s:last_repo) ? s:last_repo : semantic_ctags_diff#repo_root()
  let l:abs_path = simplify(l:repo . '/' . a:choice.path)

  if !filereadable(l:abs_path)
    echoerr 'semantic_ctags_diff: file not found: ' . l:abs_path
    return
  endif

  execute 'edit ' . fnameescape(l:abs_path)
  call cursor(a:choice.line, 1)
  echo 'semantic_ctags_diff: opened ' . a:choice.path . ' at line ' . a:choice.line
  echo 'Install vim-flog for line-range history in a new tab.'
endfunction

" --- Symbol-at-line via Python (replaces Vim ctags parsing) -----------------

function! semantic_ctags_diff#current_git_relative_path() abort
  let l:repo = semantic_ctags_diff#repo_root()
  let l:file = fnamemodify(expand('%:p'), ':p')
  let l:root = substitute(fnamemodify(l:repo, ':p'), '[\/]\+$', '', '') . '/'
  if stridx(l:file, l:root) != 0
    return ''
  endif
  return strpart(l:file, strlen(l:root))
endfunction

function! semantic_ctags_diff#build_symbol_at_command(file, line, kind_filter) abort
  let l:py_root = semantic_ctags_diff#python_project_root()
  let l:prefix = semantic_ctags_diff#_cli_prefix(l:py_root)
  let l:args = [
        \ '--symbol-at',
        \ '--file', a:file,
        \ '--line', string(a:line),
        \ '--ctags', g:semantic_ctags_diff_ctags,
        \ ]
  if !empty(a:kind_filter)
    call extend(l:args, ['--kind', a:kind_filter])
  endif
  let l:escaped = map(copy(l:args), 'shellescape(v:val)')
  return l:prefix . ' ' . join(l:escaped, ' ')
endfunction

function! semantic_ctags_diff#symbol_at(line, kind_filter) abort
  let l:rel = semantic_ctags_diff#current_git_relative_path()
  let l:abs = expand('%:p')
  if empty(l:abs) || !filereadable(l:abs)
    throw 'semantic_ctags_diff: current buffer is not a readable file in the repo'
  endif

  let l:cmd = semantic_ctags_diff#build_symbol_at_command(l:abs, a:line, a:kind_filter)
  let l:stdout_tmp = tempname()
  let l:stderr_tmp = tempname()
  call system(l:cmd . ' > ' . shellescape(l:stdout_tmp) . ' 2> ' . shellescape(l:stderr_tmp))
  let l:exit = v:shell_error
  let l:lines = filereadable(l:stdout_tmp) ? readfile(l:stdout_tmp) : []
  let l:err = filereadable(l:stderr_tmp) ? readfile(l:stderr_tmp) : []
  if filereadable(l:stdout_tmp) | call delete(l:stdout_tmp) | endif
  if filereadable(l:stderr_tmp) | call delete(l:stderr_tmp) | endif

  if l:exit != 0
    throw 'semantic_ctags_diff: symbol-at failed: ' . join(l:err, ' ')
  endif
  if !exists('*json_decode')
    throw 'semantic_ctags_diff: json_decode() required for symbol-at'
  endif
  let l:result = json_decode(join(l:lines, "\n"))
  if !empty(l:rel)
    let l:result.file = l:rel
    if !empty(get(l:result, 'flog_limit', ''))
      let l:parts = split(l:result.flog_limit, ':')
      if len(l:parts) == 2
        let l:result.flog_limit = l:parts[0] . ':' . l:rel
      endif
    endif
  endif
  return l:result
endfunction

function! semantic_ctags_diff#flog_current_symbol(open_cmd, kind_filter) abort
  if exists(':Flog') != 2 && exists(':Flogsplit') != 2
    echoerr 'semantic_ctags_diff: vim-flog is not installed'
    return
  endif

  try
    let l:result = semantic_ctags_diff#symbol_at(line('.'), a:kind_filter)
  catch /.*/
    echoerr v:exception
    return
  endtry

  if empty(get(l:result, 'symbol', {}))
    echoerr 'semantic_ctags_diff: no matching symbol under cursor'
    return
  endif

  let l:limit = get(l:result, 'flog_limit', '')
  if empty(l:limit)
    echoerr 'semantic_ctags_diff: symbol has no flog line range'
    return
  endif

  echo 'Flog history for ' . get(l:result, 'label', '') . ' [' . l:limit . ']'
  call semantic_ctags_diff#_dbg('flog symbol: ' . a:open_cmd . ' -limit=' . l:limit)
  execute a:open_cmd . ' -limit=' . fnameescape(l:limit)
endfunction

" --- Jump to symbol source from the markdown report -------------------------

" Find which section header (added/removed/modified/file_scope) encloses lnum.
function! s:section_for_line(lnum) abort
  let l:l = a:lnum
  while l:l >= 1
    let l:t = getline(l:l)
    if l:t ==# 'Added symbols'
      return 'added'
    elseif l:t ==# 'Removed symbols'
      return 'removed'
    elseif l:t ==# 'Modified symbols'
      return 'modified'
    elseif l:t ==# 'File-scope changes'
      return 'file_scope'
    endif
    let l:l -= 1
  endwhile
  return ''
endfunction

" First integer in a "range: 10-34" / "new range: 10-34" / "added lines: 1, 2".
function! s:first_int(text) abort
  let l:m = matchstr(a:text, '\d\+')
  return empty(l:m) ? 1 : str2nr(l:m)
endfunction

" Nearest bare file-path header above lnum (a non-blank line that is not a
" symbol marker, indented field, or section underline).
function! s:file_header_above(lnum) abort
  let l:l = a:lnum
  while l:l >= 1
    let l:t = getline(l:l)
    if l:t =~# '^\S' && l:t !~# '^\*' && l:t !~# '^[-=]\+$'
          \ && l:t !~# '^\%(Added\|Removed\|Modified\|File-scope\) '
          \ && index(['Added symbols', 'Removed symbols', 'Modified symbols', 'File-scope changes'], l:t) < 0
      return l:t
    endif
    let l:l -= 1
  endwhile
  return ''
endfunction

" Look up an added symbol's path/line from the cached JSON by qualified name.
function! s:lookup_added(qname) abort
  if type(s:last_json) != v:t_dict || !has_key(s:last_json, 'files')
    return {}
  endif
  for l:f in s:last_json.files
    for l:s in get(l:f, 'added_symbols', [])
      if get(l:s, 'qualified_name', get(l:s, 'name', '')) ==# a:qname
        let l:rng = get(l:s, 'range', [get(l:s, 'line', 1)])
        return {
              \ 'path': get(l:s, 'path', get(l:f, 'path', '')),
              \ 'line': empty(l:rng) ? 1 : l:rng[0],
              \ 'classification': 'added',
              \ }
      endif
    endfor
  endfor
  return {}
endfunction

" Resolve {path, line, classification} for the symbol under the cursor, or {}.
function! semantic_ctags_diff#_target_at_cursor() abort
  let l:section = s:section_for_line(line('.'))
  if empty(l:section)
    return {}
  endif

  if l:section ==# 'added'
    " Added symbols are grouped by kind as "  + qualified_name" with no path
    " in the Markdown, so resolve the path/line from the cached JSON.
    let l:l = line('.')
    while l:l >= 1 && getline(l:l) !~# '^\s*+ '
      let l:l -= 1
    endwhile
    let l:qname = matchstr(getline(l:l), '^\s*+ \zs.*$')
    if empty(l:qname)
      return {}
    endif
    return s:lookup_added(l:qname)
  endif

  if l:section ==# 'file_scope'
    let l:path = s:file_header_above(line('.'))
    if empty(l:path)
      return {}
    endif
    let l:line = 1
    let l:added = search('^\* added lines:', 'bcnW')
    if l:added > 0 && s:file_header_above(l:added) ==# l:path
      let l:line = s:first_int(getline(l:added))
    endif
    return {'path': l:path, 'line': l:line, 'classification': 'file_scope'}
  endif

  " removed / modified: find the enclosing "* kind name" block.
  let l:start = line('.')
  while l:start >= 1 && getline(l:start) !~# '^\* '
    let l:start -= 1
  endwhile
  if l:start < 1 || getline(l:start) !~# '^\* '
    return {}
  endif

  if l:section ==# 'removed'
    let l:path = ''
    let l:line = 1
    let l:l = l:start + 1
    while l:l <= line('$') && getline(l:l) =~# '^  '
      let l:t = getline(l:l)
      if l:t =~# '^  file: '
        let l:path = matchstr(l:t, '^  file: \zs.*$')
      elseif l:t =~# '^  range: '
        let l:line = s:first_int(l:t)
      endif
      let l:l += 1
    endwhile
    if empty(l:path)
      return {}
    endif
    return {'path': l:path, 'line': l:line, 'classification': 'removed'}
  endif

  " modified
  let l:path = s:file_header_above(l:start)
  if empty(l:path)
    return {}
  endif
  let l:line = 1
  let l:l = l:start + 1
  while l:l <= line('$') && getline(l:l) =~# '^  '
    if getline(l:l) =~# '^  new range: '
      let l:line = s:first_int(getline(l:l))
      break
    endif
    let l:l += 1
  endwhile
  return {'path': l:path, 'line': l:line, 'classification': 'modified'}
endfunction

function! s:open_working(abs, line, mode) abort
  let l:cmds = {'edit': 'edit', 'split': 'split', 'vsplit': 'vsplit', 'tab': 'tabedit'}
  execute get(l:cmds, a:mode, 'edit') . ' ' . fnameescape(a:abs)
  call cursor(a:line, 1)
  normal! zz
endfunction

function! s:open_fugitive(rev, path, line, mode) abort
  if exists(':Gedit') != 2
    echoerr 'semantic_ctags_diff: vim-fugitive required to open ' . a:rev . ':' . a:path
    return
  endif
  let l:cmds = {'edit': 'Gedit', 'split': 'Gsplit', 'vsplit': 'Gvsplit', 'tab': 'Gtabedit'}
  let l:obj = a:rev . ':' . a:path
  call semantic_ctags_diff#_dbg('open fugitive object: ' . l:obj)
  execute get(l:cmds, a:mode, 'Gedit') . ' ' . fnameescape(l:obj)
  call cursor(a:line, 1)
  normal! zz
endfunction

function! semantic_ctags_diff#open_symbol_under_cursor(mode) abort
  let l:target = semantic_ctags_diff#_target_at_cursor()
  if empty(l:target)
    echo 'semantic_ctags_diff: no symbol under cursor'
    return
  endif

  let l:repo = !empty(s:last_repo) ? s:last_repo : semantic_ctags_diff#repo_root()
  let l:abs = simplify(l:repo . '/' . l:target.path)

  " Removed symbols no longer exist in the working tree: open them from the
  " base commit via fugitive. Added/modified symbols live in head, so prefer
  " the on-disk working file and fall back to the head commit when the current
  " checkout does not have it.
  if l:target.classification ==# 'removed'
    if empty(s:last_base)
      echoerr 'semantic_ctags_diff: no base ref recorded; run a diff first'
      return
    endif
    call s:open_fugitive(s:last_base, l:target.path, l:target.line, a:mode)
  elseif filereadable(l:abs)
    call s:open_working(l:abs, l:target.line, a:mode)
  elseif !empty(s:last_head)
    call s:open_fugitive(s:last_head, l:target.path, l:target.line, a:mode)
  else
    echoerr 'semantic_ctags_diff: file not found in working tree: ' . l:abs
  endif
endfunction
