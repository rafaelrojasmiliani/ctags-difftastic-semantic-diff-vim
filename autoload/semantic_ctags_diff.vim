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
let s:ref_cache = {}
let s:ref_cache_repo = ''

" Submodule relative paths (primary + typo fallback).
let s:submodule_paths = [
      \ 'submodules/semantic-ctags-diff',
      \ 'submodules/sematic-ctags-diff',
      \]

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
  if g:semantic_ctags_diff_use_fugitive_worktree && exists('*FugitiveWorkTree')
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

function! semantic_ctags_diff#python_project_root() abort
  if !empty(g:semantic_ctags_diff_root)
    let l:root = fnamemodify(g:semantic_ctags_diff_root, ':p')
    if !filereadable(l:root . '/pyproject.toml')
      throw 'semantic_ctags_diff: g:semantic_ctags_diff_root has no pyproject.toml: ' . l:root
    endif
    return l:root
  endif

  let l:found = semantic_ctags_diff#_find_python_root(semantic_ctags_diff#repo_root())
  if !empty(l:found)
    return l:found
  endif

  let l:found = semantic_ctags_diff#_find_python_root(semantic_ctags_diff#_start_dir())
  if !empty(l:found)
    return l:found
  endif

  throw 'semantic_ctags_diff: Python project not found. Expected submodules/semantic-ctags-diff. Install with: pip install -e submodules/semantic-ctags-diff'
endfunction

function! semantic_ctags_diff#_find_python_root(start) abort
  let l:dir = fnamemodify(a:start, ':p')
  while !empty(l:dir)
    for l:rel in s:submodule_paths
      let l:candidate = simplify(l:dir . '/' . l:rel)
      if filereadable(l:candidate . '/pyproject.toml')
        return l:candidate
      endif
    endfor
    let l:parent = fnamemodify(l:dir, ':h')
    if l:parent ==# l:dir
      break
    endif
    let l:dir = l:parent
  endwhile
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

function! semantic_ctags_diff#_cli_prefix(py_root) abort
  if !empty(g:semantic_ctags_diff_cli)
    return g:semantic_ctags_diff_cli
  endif

  let l:venv_bin = a:py_root . '/.venv/bin/semantic-branch-diff'
  if executable(l:venv_bin)
    return shellescape(l:venv_bin)
  endif

  if executable('semantic-branch-diff')
    return 'semantic-branch-diff'
  endif

  let l:python = shellescape(g:semantic_ctags_diff_python)
  let l:py_root_esc = shellescape(a:py_root)
  return 'PYTHONPATH=' . l:py_root_esc . ' ' . l:python . ' -m semantic_branch_diff.cli'
endfunction

" --- Execution --------------------------------------------------------------

function! semantic_ctags_diff#run(base, head, format) abort
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

  call semantic_ctags_diff#debug('--- run ' . a:format . ' ---')
  call semantic_ctags_diff#debug('repo_root: ' . l:repo)
  call semantic_ctags_diff#debug('python_root: ' . l:py_root)
  call semantic_ctags_diff#debug('command: ' . l:cmd)

  let l:stdout_tmp = tempname()
  let l:stderr_tmp = tempname()
  let l:shell_cmd = l:cmd
        \ . ' > ' . shellescape(l:stdout_tmp)
        \ . ' 2> ' . shellescape(l:stderr_tmp)

  call system(l:shell_cmd)
  let l:exit_code = v:shell_error
  let l:stdout_lines = filereadable(l:stdout_tmp) ? readfile(l:stdout_tmp) : []
  let l:stderr_lines = filereadable(l:stderr_tmp) ? readfile(l:stderr_tmp) : []

  if filereadable(l:stdout_tmp)
    call delete(l:stdout_tmp)
  endif
  if filereadable(l:stderr_tmp)
    call delete(l:stderr_tmp)
  endif

  call semantic_ctags_diff#debug('exit_code: ' . l:exit_code)
  call semantic_ctags_diff#debug('stdout lines: ' . len(l:stdout_lines))
  call semantic_ctags_diff#debug('stderr lines: ' . len(l:stderr_lines))

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

  let l:failed = l:exit_code != 0 || (empty(l:stdout_lines) && !empty(l:stderr_lines))
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

  if a:format ==# 'json'
    call semantic_ctags_diff#_store_json(l:stdout_lines)
    let l:title = 'SemanticCtagsDiff JSON'
    let l:ft = 'json'
    let l:body = l:stdout_lines
  else
    let l:title = 'SemanticCtagsDiff'
    let l:ft = 'markdown'
    let l:header = semantic_ctags_diff#_markdown_header(l:repo, a:base, a:head, l:cmd)
    let l:body = l:header + l:stdout_lines
    call semantic_ctags_diff#_fetch_json_for_cache(a:base, a:head)
  endif

  call semantic_ctags_diff#open_scratch(l:title, l:body, l:ft)
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
  call semantic_ctags_diff#run(s:last_base, s:last_head, s:last_format)
  if l:replace && s:last_scratch_bufnr != -1 && bufnr('%') != s:last_scratch_bufnr
    " run() opened a new buffer; close duplicate if needed
  endif
endfunction

function! semantic_ctags_diff#_markdown_header(repo, base, head, cmd) abort
  return [
        \ 'Semantic Ctags Diff',
        \ '===================',
        \ '',
        \ 'Repo: ' . a:repo,
        \ 'Base: ' . a:base,
        \ 'Head: ' . a:head,
        \ 'Command: ' . a:cmd,
        \ '',
        \ ]
endfunction

function! semantic_ctags_diff#_fetch_json_for_cache(base, head) abort
  " Silently fetch JSON for FlogSymbol picker without opening a buffer.
  try
    let l:cmd = semantic_ctags_diff#build_command(a:base, a:head, 'json')
    let l:stdout_tmp = tempname()
    let l:stderr_tmp = tempname()
    let l:shell_cmd = l:cmd
          \ . ' > ' . shellescape(l:stdout_tmp)
          \ . ' 2> ' . shellescape(l:stderr_tmp)
    call system(l:shell_cmd)
    if filereadable(l:stdout_tmp)
      call semantic_ctags_diff#_store_json(readfile(l:stdout_tmp))
      call delete(l:stdout_tmp)
    endif
    if filereadable(l:stderr_tmp)
      call delete(l:stderr_tmp)
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
  try
    let l:repo = semantic_ctags_diff#repo_root()
  catch /.*/
    return []
  endtry

  if s:ref_cache_repo !=# l:repo
    let s:ref_cache_repo = l:repo
    let l:cmd = 'git -C ' . shellescape(l:repo)
          \ . ' for-each-ref --format=%(refname:short) refs/heads refs/remotes 2>/dev/null'
    let s:ref_cache = systemlist(l:cmd)
  endif

  if empty(a:arglead)
    return s:ref_cache
  endif
  return filter(copy(s:ref_cache), 'v:val =~# ''^'' . escape(a:arglead, ''\'')')
endfunction

" --- Flog integration (optional) --------------------------------------------

function! semantic_ctags_diff#flog(base, head) abort
  if exists(':Flog') != 2
    echoerr 'semantic_ctags_diff: vim-flog is not installed'
    return
  endif
  let l:range = a:base . '..' . a:head
  execute 'Flog --raw=' . shellescape(l:range)
endfunction

function! semantic_ctags_diff#flog_symbol() abort
  if exists(':Flog') != 2
    echoerr 'semantic_ctags_diff: vim-flog is not installed'
    return
  endif

  if empty(s:last_json)
    if !empty(s:last_base) && !empty(s:last_head)
      call semantic_ctags_diff#_fetch_json_for_cache(s:last_base, s:last_head)
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
      call add(l:choices, {
            \ 'label': l:path . ': ' . l:name . ' (' . l:kind . ')',
            \ 'path': l:path,
            \ 'name': l:name,
            \ 'kind': l:kind,
            \ 'line': l:line,
            \ })
    endfor
  endfor
  return l:choices
endfunction

function! semantic_ctags_diff#_open_symbol_in_flog(choice) abort
  let l:repo = !empty(s:last_repo) ? s:last_repo : semantic_ctags_diff#repo_root()
  let l:abs_path = simplify(l:repo . '/' . a:choice.path)

  if !filereadable(l:abs_path)
    echoerr 'semantic_ctags_diff: file not found: ' . l:abs_path
    return
  endif

  execute 'edit ' . fnameescape(l:abs_path)
  call cursor(a:choice.line, 1)

  let l:kind = tolower(a:choice.kind)
  if exists(':FlogsplitClass') == 2 && l:kind ==# 'class'
    FlogsplitClass
  elseif exists(':FlogsplitFunction') == 2 && (l:kind ==# 'function' || l:kind ==# 'method' || l:kind ==# 'member')
    FlogsplitFunction
  elseif exists(':FlogsplitNamespace') == 2 && l:kind ==# 'namespace'
    FlogsplitNamespace
  elseif exists(':FlogsplitSymbol') == 2
    FlogsplitSymbol
  else
    echo 'semantic_ctags_diff: opened ' . a:choice.path . ' at line ' . a:choice.line
    echo 'Define :FlogsplitSymbol (or kind-specific commands) for line-range history.'
  endif
endfunction
