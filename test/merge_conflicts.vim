" :ShowMergeConflict — conflict list from the real CLI, report split below,
" <CR> opens ours|theirs as a vertical diff in a new tab.
"
" Run headless:  vim -N -u NONE -es -S test/merge_conflicts.vim
" Needs git and the Python CLI; the vertical diff part needs vim-fugitive.

set nocompatible
set hidden
let &runtimepath = expand('<sfile>:p:h:h') . ',' . &runtimepath
for s:dir in glob('~/.vim/bundle/vim-fugitive', 0, 1)
      \ + glob($SEMANTIC_CTAGS_TEST_FUGITIVE, 0, 1)
  let &runtimepath .= ',' . s:dir
endfor
runtime! plugin/*.vim
" Load before the stub below, or autoloading would overwrite it on first call.
runtime autoload/semantic_ctags_diff.vim

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
        \ . ' -c user.email=t@t -c user.name=tester ' . a:args)
endfunction

" The semantic report itself is covered by cache.vim / nav_parse.vim.
let g:scd_calls = []
function! semantic_ctags_diff#run_markdown(base, head, ...) abort
  call add(g:scd_calls, [a:base, a:head])
  execute g:semantic_ctags_diff_open_cmd
  setlocal buftype=nofile bufhidden=wipe noswapfile
  call setline(1, ['report ' . a:base . '..' . a:head])
endfunction

" --- master and feature both edit a.cpp line 1; b.cpp merges cleanly --------

let s:repo = resolve(tempname())
call mkdir(s:repo, 'p')
call s:git(s:repo, 'init -q')
call s:git(s:repo, 'symbolic-ref HEAD refs/heads/master')
call writefile(['int a() { return 0; }'], s:repo . '/a.cpp')
call writefile(['int b() { return 0; }', '', '', 'int c() { return 0; }'], s:repo . '/b.cpp')
call s:git(s:repo, 'add -A')
call s:git(s:repo, 'commit -qm base')
call s:git(s:repo, 'checkout -q -b feature')
call writefile(['int a() { return 1; }'], s:repo . '/a.cpp')
call writefile(['int b() { return 1; }', '', '', 'int c() { return 0; }'], s:repo . '/b.cpp')
call s:git(s:repo, 'commit -qam feature')
call s:git(s:repo, 'checkout -q master')
call writefile(['int a() { return 2; }'], s:repo . '/a.cpp')
call writefile(['int b() { return 0; }', '', '', 'int c() { return 2; }'], s:repo . '/b.cpp')
call s:git(s:repo, 'commit -qam master')

execute 'cd ' . fnameescape(s:repo)
let s:tabs = tabpagenr('$')
ShowMergeConflict feature

call s:ok(tabpagenr('$') == s:tabs + 1, 'opens a new tab')
call s:ok(winnr('$') == 2, 'list + report windows, got ' . winnr('$'))
call s:ok(winnr() == 1, 'cursor stays in the list (top) window')
call s:ok(getline('.') =~# 'content\s\+a\.cpp$', 'cursor on the conflicting file: ' . getline('.'))
call s:ok(join(getline(1, '$')) !~# 'b\.cpp', 'cleanly merging b.cpp is not listed')
call s:ok(g:scd_calls == [['HEAD', 'feature']],
      \ 'report is HEAD..feature: ' . string(g:scd_calls))

if exists('*FugitiveFind')
  execute "normal \<CR>"
  call s:ok(tabpagenr('$') == s:tabs + 2, '<CR> opens another tab')
  let s:diffs = filter(range(1, winnr('$')), 'getwinvar(v:val, "&diff")')
  call s:ok(len(s:diffs) == 2, 'two windows in diff mode, got ' . len(s:diffs))
  call s:ok(bufname(winbufnr(s:diffs[0])) =~# 'a\.cpp$', 'diff shows a.cpp: '
        \ . bufname(winbufnr(s:diffs[0])))
  if semantic_ctags_diff#difftastic#available()
    call s:ok(!empty(filter(range(1, winnr('$')),
          \ 'bufname(winbufnr(v:val)) =~# "^difftastic://"')), 'difftastic split below')
  endif
else
  call s:say('skip - vim-fugitive not found, <CR> diff not checked')
endif

if s:fail
  cquit
endif
qall!
