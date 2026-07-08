" Flog file-scoped history and #include resolution.
" Requires vim-flog. Uses -path= and remaps <CR>/dd to path-filtered side windows.

scriptencoding utf-8

" Set before :Flog/-path= opens; consumed by FileType floggraph autocmd below.
let g:semantic_ctags_diff_flog_file_pending = 0

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

" In a floggraph buffer opened with -path=, <CR> and dd show only that file.
function! semantic_ctags_diff#flog#apply_file_maps() abort
  if !get(g:, 'semantic_ctags_diff_flog_file_maps', 1)
    return
  endif
  if exists('<Plug>(FlogVSplitCommitPathsRight)')
    execute 'nnoremap <buffer><silent> <CR> <Plug>(FlogVSplitCommitPathsRight)'
  endif
  if exists('<Plug>(FlogVDiffSplitPathsRight)')
    execute 'nnoremap <buffer><silent> dd <Plug>(FlogVDiffSplitPathsRight)'
    execute 'nnoremap <buffer><silent> dv <Plug>(FlogVDiffSplitPathsRight)'
  endif
  if exists('<Plug>(FlogVDiffSplitLastCommitPathsRight)')
    execute 'nnoremap <buffer><silent> d! <Plug>(FlogVDiffSplitLastCommitPathsRight)'
  endif
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
  call semantic_ctags_diff#flog#apply_file_maps()
endfunction
