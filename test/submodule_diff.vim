" Submodule support. The analysed repo is a submodule of a superproject, so:
"   - its .git is a FILE pointing at <super>/.git/modules/<name>
"   - the report buffer lives outside it, in the superproject
" Fugitive resolves :G* commands from the current buffer, so without an
" explicit git dir every rev and path is looked up in the superproject, which
" is what produced "Not a valid object name <super-HEAD>:<sub/path>".
set nocompatible
set hidden
let &runtimepath = expand('<sfile>:p:h:h') . ',' . &runtimepath
for s:d in ['/etc/vim/bundle/vim-fugitive', expand('~/.vim/bundle/vim-fugitive')]
  if isdirectory(s:d)
    let &runtimepath = s:d . ',' . &runtimepath
  endif
endfor
runtime! plugin/*.vim
filetype plugin indent on

" Vim swallows :echo under -es, so results go to a file as well.
let s:fail = 0
let s:log = []
let s:out = $SEMANTIC_CTAGS_TEST_LOG
function! s:say(line) abort
  echo a:line
  call add(s:log, a:line)
  if !empty(s:out)
    call writefile(s:log, s:out)
  endif
endfunction
function! s:ok(cond, what) abort
  call s:say((a:cond ? 'ok   - ' : 'FAIL - ') . a:what)
  if !a:cond
    let s:fail = 1
  endif
endfunction

function! s:git(dir, args) abort
  return system('git -C ' . shellescape(a:dir)
        \ . ' -c user.email=t@t -c user.name=t -c protocol.file.allow=always '
        \ . a:args)
endfunction

if !exists('*FugitiveFind')
  call s:say('skip - vim-fugitive not installed')
  qall!
endif

let s:root = resolve(tempname())
call mkdir(s:root . '/origin/src', 'p')
call mkdir(s:root . '/super', 'p')

" Upstream for the submodule.
call s:git(s:root . '/origin', 'init -q')
call writefile(['int gone() { return 1; }'], s:root . '/origin/src/a.cpp')
call s:git(s:root . '/origin', 'add -A')
call s:git(s:root . '/origin', 'commit -qm base')

" Superproject with the submodule checked out at super/sub.
call s:git(s:root . '/super', 'init -q')
call writefile(['super'], s:root . '/super/README')
call s:git(s:root . '/super', 'add -A')
call s:git(s:root . '/super', 'commit -qm super')
call s:git(s:root . '/super', 'submodule add -q ' . shellescape(s:root . '/origin') . ' sub')
call s:git(s:root . '/super', 'commit -qm add-sub')

let s:sub = s:root . '/super/sub'
call s:ok(filereadable(s:sub . '/.git'),
      \ 'submodule .git is a file, not a directory')

let s:base = trim(s:git(s:sub, 'rev-parse HEAD'))
call writefile(['int kept() { return 2; }'], s:sub . '/src/a.cpp')
call s:git(s:sub, 'commit -qam head')
let s:head = trim(s:git(s:sub, 'rev-parse HEAD'))
let s:super_head = trim(s:git(s:root . '/super', 'rev-parse HEAD'))

let s:gitdir = FugitiveExtractGitDir(s:sub)
call s:ok(s:gitdir =~# 'modules[/\\]sub',
      \ 'git dir resolves to <super>/.git/modules/sub: ' . s:gitdir)

let s:json = {'files': [{'path': 'src/a.cpp',
      \ 'removed_symbols': [{'qualified_name': 'gone', 'old_range': [1, 1]}],
      \ 'added_symbols': [{'qualified_name': 'kept', 'new_range': [1, 1]}],
      \ 'modified_symbols': []}]}

" The report buffer sits in the SUPERPROJECT, outside the submodule.
function! s:report(lines) abort
  call semantic_ctags_diff#_seed_state(s:base, s:head, s:sub, s:json)
  silent! %bwipeout!
  execute 'edit ' . s:root . '/super/SemanticCtagsDiff'
  call setline(1, a:lines)
  setlocal nomodified
  " semantic_ctags_diff#run() pins this on the real report buffer.
  let b:semantic_ctags_diff_repo = s:sub
  call cursor(len(a:lines), 1)
endfunction

" --- removed symbol: resolved in the submodule, at the base revision --------
call s:report(['Removed symbols', '===============', '', 'Functions:', '  - gone'])
let s:t = semantic_ctags_diff#_target_at_cursor()
call s:ok(get(s:t, 'path', '') ==# 'src/a.cpp', 'removed target path resolved')

call semantic_ctags_diff#open_symbol_under_cursor('edit')
let s:name = bufname('%')
call s:ok(s:name =~# 'modules[/\\]sub', 'opened from the submodule: ' . s:name)
call s:ok(s:name =~# s:base, 'opened at the base revision')
call s:ok(s:name !~# s:super_head, 'did not use the superproject HEAD')

" --- added symbol: <CR> jumps to the submodule working file, no diff --------
call s:report(['Added symbols', '=============', '', 'Functions:', '  + kept'])
call semantic_ctags_diff#open_diff_under_cursor()
let s:name = bufname('%')
call s:ok(s:name !~# '^fugitive:', '<CR> on added does not open a diff object')
call s:ok(resolve(fnamemodify(s:name, ':p')) ==# resolve(s:sub . '/src/a.cpp'),
      \ '<CR> on added jumps to the working file: ' . s:name)
call s:ok(winnr('$') == 1, 'added jump does not split into a diff')

" --- cache is per repository, so a submodule never shares the superproject's -
let g:semantic_ctags_diff_cache_dir = s:root . '/cache'
let s:sub_dir = semantic_ctags_diff#_repo_cache_dir(s:sub . '/')
let s:super_dir = semantic_ctags_diff#_repo_cache_dir(s:root . '/super/')
call s:ok(s:sub_dir !=# s:super_dir,
      \ 'submodule and superproject get separate cache dirs')
call s:ok(fnamemodify(s:sub_dir, ':t') ==# 'sub',
      \ 'trailing slash does not collapse the name to "repo": ' . s:sub_dir)

" --- the report pins its repo, so nothing can drift to the superproject -----
call s:report(['Added symbols', '=============', '', 'Functions:', '  + kept'])
call s:ok(get(b:, 'semantic_ctags_diff_repo', '') !=# '',
      \ 'report buffer records its repo')
call s:ok(resolve(semantic_ctags_diff#repo_root()) ==# resolve(s:sub),
      \ 'repo_root() in the report returns the submodule, not the superproject')

if s:fail
  cquit
endif
qall!
