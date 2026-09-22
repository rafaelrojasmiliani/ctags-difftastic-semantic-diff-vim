" Flog file-scoped history and #include resolution.
" Requires vim-flog. Uses -path= and remaps <CR>/dd to path-filtered side windows.

scriptencoding utf-8

" Set before :Flog/-path= opens; consumed by FileType floggraph autocmd below.
let g:semantic_ctags_diff_flog_file_pending = 0
let g:semantic_ctags_diff_flog_file_pending_path = ''

function! semantic_ctags_diff#flog#git_relative_path(file) abort
  if empty(a:file)
    return ''
  endif
  let l:abs = fnamemodify(a:file, ':p')
  if !filereadable(l:abs)
    return ''
  endif
  try
    let l:repo = semantic_ctags_diff#repo_root()
  catch /.*/
    return ''
  endtry
  let l:root = substitute(fnamemodify(l:repo, ':p'), '[\/]\+$', '', '') . '/'
  if stridx(l:abs, l:root) == 0
    return strpart(l:abs, strlen(l:root))
  endif
  return ''
endfunction

function! semantic_ctags_diff#flog#current_file_path() abort
  let l:rel = semantic_ctags_diff#current_git_relative_path()
  if !empty(l:rel)
    return l:rel
  endif
  return semantic_ctags_diff#flog#git_relative_path(expand('%:p'))
endfunction

" Extract #include "local" or #include <system> on line {lnum}; return [path, system].
function! semantic_ctags_diff#flog#parse_include_line(lnum) abort
  let l:text = substitute(getline(a:lnum), '\s*//.*$', '', '')
  if l:text =~# '#\s*include\s*"[^"]\+"'
    return [matchstr(l:text, '#\s*include\s*"\zs[^"]\+\ze"'), 0]
  endif
  if l:text =~# '#\s*include\s*<[^>]\+>'
    return [matchstr(l:text, '#\s*include\s*<\zs[^>]\+\ze>'), 1]
  endif
  " Fallback: cursor on the path token inside an #include line.
  if l:text =~# '#\s*include'
    let l:cf = expand('<cfile>')
    if !empty(l:cf) && l:cf !~# '^#\?include$' && (l:cf =~# '[./\\]' || l:cf =~# '\.[A-Za-z]\+$')
      return [l:cf, l:text =~# '#\s*include\s*<']
    endif
  endif
  return ['', 0]
endfunction

function! semantic_ctags_diff#flog#_normalize_inc(path) abort
  return substitute(a:path, '\\', '/', 'g')
endfunction

" Find a repo-relative include path via git ls-files (handles include/ subtrees).
function! semantic_ctags_diff#flog#_find_via_git(repo, inc) abort
  let l:inc = semantic_ctags_diff#flog#_normalize_inc(a:inc)
  let l:lines = systemlist('git -C ' . shellescape(a:repo) . ' ls-files 2>/dev/null')
  if v:shell_error != 0 || empty(l:lines)
    return ''
  endif

  let l:matches = []
  for l:f in l:lines
    if l:f ==# l:inc || l:f =~# '/'.escape(l:inc, '/').'$'
      call add(l:matches, l:f)
    endif
  endfor
  if len(l:matches) == 1
    return simplify(a:repo . '/' . l:matches[0])
  endif
  if len(l:matches) > 1
    let l:best = l:matches[0]
    for l:f in l:matches
      if len(l:f) < len(l:best)
        let l:best = l:f
      endif
    endfor
    return simplify(a:repo . '/' . l:best)
  endif

  let l:base = fnamemodify(l:inc, ':t')
  let l:base_matches = filter(copy(l:lines), {_, v -> fnamemodify(v, ':t') ==# l:base})
  if len(l:base_matches) == 1
    return simplify(a:repo . '/' . l:base_matches[0])
  endif
  return ''
endfunction

" Resolve include path string to absolute file (no ctags — filesystem + git index).
function! semantic_ctags_diff#flog#resolve_include_path(inc, is_system) abort
  if empty(a:inc)
    return ''
  endif

  let l:inc = semantic_ctags_diff#flog#_normalize_inc(a:inc)
  let l:cur = expand('%:p')
  let l:repo = ''
  try
    let l:repo = semantic_ctags_diff#repo_root()
  catch /.*/
  endtry

  let l:candidates = []
  if !empty(l:cur)
    call add(l:candidates, simplify(fnamemodify(l:cur, ':h') . '/' . l:inc))
  endif
  if !empty(l:repo)
    call add(l:candidates, simplify(l:repo . '/' . l:inc))
    for l:prefix in ['include/', 'src/', 'Inc/', 'public/', 'headers/']
      call add(l:candidates, simplify(l:repo . '/' . l:prefix . l:inc))
    endfor
    let l:git_hit = semantic_ctags_diff#flog#_find_via_git(l:repo, l:inc)
    if !empty(l:git_hit)
      return l:git_hit
    endif
  endif
  if !empty(l:cur)
    let l:found = findfile(l:inc, fnamemodify(l:cur, ':h'))
    if !empty(l:found)
      call add(l:candidates, fnamemodify(l:found, ':p'))
    endif
  endif
  let l:found = findfile(l:inc, getcwd())
  if !empty(l:found)
    call add(l:candidates, fnamemodify(l:found, ':p'))
  endif

  for l:extra in get(g:, 'semantic_ctags_diff_include_search_dirs', [])
    call add(l:candidates, simplify(fnamemodify(l:extra, ':p') . '/' . l:inc))
  endfor

  for l:path in l:candidates
    if filereadable(l:path)
      call semantic_ctags_diff#_dbg('flog include resolved: ' . l:path)
      return fnamemodify(l:path, ':p')
    endif
  endfor
  call semantic_ctags_diff#_dbg('flog include not found: ' . l:inc . ' (system=' . a:is_system . ')')
  return ''
endfunction

" Resolve an #include on line {lnum} to an absolute path.
function! semantic_ctags_diff#flog#resolve_include(lnum) abort
  let l:parsed = semantic_ctags_diff#flog#parse_include_line(a:lnum)
  return semantic_ctags_diff#flog#resolve_include_path(l:parsed[0], l:parsed[1])
endfunction

" --- Commit under the cursor ------------------------------------------------

" Hash of the commit on the current floggraph line, as Flog reports it.
" Flog's API moved between major versions, so try each form and fall back to
" scraping the line. Callers must validate the result against git.
function! semantic_ctags_diff#flog#commit_at_cursor() abort
  " Flog v3+.
  if exists('*flog#floggraph#commit#GetAtLine')
    try
      let l:commit = flog#floggraph#commit#GetAtLine('.')
      if type(l:commit) == v:t_dict && !empty(get(l:commit, 'hash', ''))
        return l:commit.hash
      endif
    catch /.*/
    endtry
  endif

  " Flog v1/v2.
  if exists('*flog#get_commit_at_line')
    try
      let l:commit = flog#get_commit_at_line()
      if type(l:commit) == v:t_dict && !empty(get(l:commit, 'hash', ''))
        return l:commit.hash
      endif
    catch /.*/
    endtry
  endif

  " Last resort: first hash-shaped token on the graph line.
  return matchstr(getline('.'), '\<\x\{7,40}\>')
endfunction

" Resolve {hash} in {repo}; returns {'hash': full, 'subject': ...} or {}.
" Doubles as validation for the scraped-hash fallback above.
function! semantic_ctags_diff#flog#commit_info(repo, hash) abort
  if empty(a:hash)
    return {}
  endif
  let l:out = systemlist('git -C ' . shellescape(a:repo)
        \ . ' log -1 --format=%H%n%s ' . shellescape(a:hash . '^{commit}') . ' 2>/dev/null')
  if v:shell_error != 0 || empty(l:out)
    return {}
  endif
  return {'hash': trim(l:out[0]), 'subject': len(l:out) > 1 ? l:out[1] : ''}
endfunction

" The single path this floggraph is filtered to, or '' when unfiltered.
function! semantic_ctags_diff#flog#buffer_path() abort
  " Set by :FlogFile / :FlogInclude when they opened this graph.
  let l:own = get(b:, 'semantic_ctags_diff_flog_path', '')
  if !empty(l:own)
    return l:own
  endif

  " Plain `:Flog -path=...` — read the option back out of Flog's own state.
  let l:opts = {}
  if exists('*flog#floggraph#buf#GetState')
    try
      let l:opts = get(flog#floggraph#buf#GetState(), 'opts', {})
    catch /.*/
    endtry
  endif
  if empty(l:opts)
    let l:opts = get(get(b:, 'flog_state', {}), 'opts', {})
  endif

  let l:paths = get(l:opts, 'path', [])
  if type(l:paths) == v:t_list
    return empty(l:paths) ? '' : l:paths[0]
  endif
  return l:paths
endfunction

" --- <CR> action: difftastic diff of this commit, this file only ------------

function! s:difftastic_open_cmd() abort
  let l:height = get(g:, 'semantic_ctags_diff_flog_difftastic_height', 20)
  " Leave room for the graph above; 0 means "let Vim split evenly".
  let l:height = l:height > 0 ? min([l:height, &lines - 6]) : 0
  return get(g:, 'semantic_ctags_diff_flog_difftastic_split', 'botright')
        \ . ' ' . (l:height > 0 ? l:height : '') . 'new'
endfunction

" Show the difftastic diff for the commit under the cursor, restricted to the
" path this graph was opened with. Bound to <CR> in :FlogFile graphs.
function! semantic_ctags_diff#flog#difftastic_at_cursor() abort
  try
    let l:repo = semantic_ctags_diff#repo_root()
  catch /.*/
    echoerr v:exception
    return
  endtry

  let l:path = semantic_ctags_diff#flog#buffer_path()
  if empty(l:path)
    echoerr 'semantic_ctags_diff: this graph is not filtered to one file — open it with :FlogFile'
    return
  endif

  let l:info = semantic_ctags_diff#flog#commit_info(
        \ l:repo, semantic_ctags_diff#flog#commit_at_cursor())
  if empty(l:info)
    echoerr 'semantic_ctags_diff: no commit under the cursor'
    return
  endif

  call semantic_ctags_diff#difftastic#commit_file(l:info.hash, l:path, l:repo, {
        \ 'open_cmd': s:difftastic_open_cmd(),
        \ 'title': 'difftastic://flog/' . tabpagenr() . '/' . l:path,
        \ 'subject': l:info.subject,
        \ 'focus': get(g:, 'semantic_ctags_diff_flog_difftastic_focus', 0),
        \ })
endfunction

" True when <CR> should open a difftastic diff instead of Flog's commit view.
function! s:use_difftastic() abort
  if !get(g:, 'semantic_ctags_diff_flog_difftastic', 1)
    return 0
  endif
  return semantic_ctags_diff#difftastic#available()
endfunction

" Whether vim-flog defines {plug}.
" NOTE: exists('<Plug>(Name)') is always 0 — exists() has no <Plug> form — so
" every map guarded by it silently did nothing. maparg() is the real test.
function! s:has_plug(plug) abort
  return !empty(maparg(a:plug, 'n'))
endfunction

" Map {lhs} to {plug} in this buffer, if flog provides it.
function! s:map_plug(lhs, plug) abort
  if s:has_plug(a:plug)
    execute 'nmap <buffer><silent> ' . a:lhs . ' ' . a:plug
  endif
endfunction

" In a floggraph buffer opened with -path=, <CR> and dd show only that file.
function! semantic_ctags_diff#flog#apply_file_maps() abort
  if !get(g:, 'semantic_ctags_diff_flog_file_maps', 1)
    return
  endif

  if s:use_difftastic()
    " <CR> -> horizontal split below with this commit's difftastic diff.
    nnoremap <buffer><silent> <CR>
          \ :<C-u>call semantic_ctags_diff#flog#difftastic_at_cursor()<CR>
    " Flog's own path-scoped commit view stays one key away.
    call s:map_plug('go', '<Plug>(FlogVSplitCommitPathsRight)')
  else
    call s:map_plug('<CR>', '<Plug>(FlogVSplitCommitPathsRight)')
  endif

  call s:map_plug('dd', '<Plug>(FlogVDiffSplitPathsRight)')
  call s:map_plug('dv', '<Plug>(FlogVDiffSplitPathsRight)')
  call s:map_plug('d!', '<Plug>(FlogVDiffSplitLastCommitPathsRight)')
endfunction

function! semantic_ctags_diff#flog#open_path(open_cmd, git_path) abort
  if exists(':Flog') != 2 && exists(':Flogsplit') != 2
    echoerr 'semantic_ctags_diff: vim-flog is not installed'
    return
  endif
  if empty(a:git_path)
    echoerr 'semantic_ctags_diff: not a git-tracked path'
    return
  endif

  let l:open = a:open_cmd
  if exists(':' . l:open) != 2
    if exists(':Flog') == 2
      let l:open = 'Flog'
    else
      let l:open = 'Flogsplit'
    endif
  endif

  let g:semantic_ctags_diff_flog_file_pending = 1
  let g:semantic_ctags_diff_flog_file_pending_path = a:git_path
  call semantic_ctags_diff#_dbg('flog file: ' . l:open . ' -path=' . a:git_path)
  echo 'Flog file history: ' . a:git_path . ' (<CR> and dd = this file only)'
  execute l:open . ' -path=' . fnameescape(a:git_path)
endfunction

function! semantic_ctags_diff#flog#open_current_file(open_cmd) abort
  let l:path = semantic_ctags_diff#flog#current_file_path()
  if empty(l:path)
    echoerr 'semantic_ctags_diff: current buffer is not in the git repo'
    return
  endif
  call semantic_ctags_diff#flog#open_path(a:open_cmd, l:path)
endfunction

function! semantic_ctags_diff#flog#open_include(open_cmd) abort
  let l:parsed = semantic_ctags_diff#flog#parse_include_line(line('.'))
  if empty(l:parsed[0])
    echoerr 'semantic_ctags_diff: not an #include line — put cursor on #include "path" or <path>'
    return
  endif

  let l:abs = semantic_ctags_diff#flog#resolve_include_path(l:parsed[0], l:parsed[1])
  if empty(l:abs)
    echoerr 'semantic_ctags_diff: include file not found: ' . l:parsed[0]
    return
  endif

  let l:rel = semantic_ctags_diff#flog#git_relative_path(l:abs)
  if empty(l:rel)
    echoerr 'semantic_ctags_diff: include is outside the repo: ' . l:abs
    return
  endif
  call semantic_ctags_diff#flog#open_path(a:open_cmd, l:rel)
endfunction

augroup SemanticCtagsFlogFileMode
  autocmd!
  autocmd FileType floggraph call semantic_ctags_diff#flog#_on_floggraph()
augroup END

function! semantic_ctags_diff#flog#_on_floggraph() abort
  if !get(g:, 'semantic_ctags_diff_flog_file_pending', 0)
    return
  endif
  let g:semantic_ctags_diff_flog_file_pending = 0
  " Remember the -path= we opened with: reading it back out of Flog's internal
  " state is version-dependent, this is not.
  let b:semantic_ctags_diff_flog_path = g:semantic_ctags_diff_flog_file_pending_path
  let g:semantic_ctags_diff_flog_file_pending_path = ''
  call semantic_ctags_diff#flog#apply_file_maps()
endfunction
