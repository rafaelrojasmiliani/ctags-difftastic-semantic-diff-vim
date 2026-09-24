" :CompareBranchesForMerge — pane contents and merge direction.
"
" <CR> means "merge this commit into the OTHER branch's tip", so the base of
" the report is the opposite branch. Getting that backwards still produces a
" plausible-looking report, just for the wrong direction, so it is asserted
" here for both panes. Each pane must also stop at the merge base: showing the
" shared history would make every commit look like it needs merging.
"
" Run headless:  vim -N -u NONE -es -S test/merge_compare.vim

set nocompatible
set hidden
let &runtimepath = expand('<sfile>:p:h:h') . ',' . &runtimepath
runtime! plugin/*.vim
" Load before the stub below, or autoloading would overwrite it on first call.
runtime autoload/semantic_ctags_diff.vim

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
        \ . ' -c user.email=t@t -c user.name=tester ' . a:args)
endfunction

" Stands in for the CLI: this checks the panes and the report plumbing, not the
" semantic diff itself, which cache.vim and nav_parse.vim already cover.
let g:scd_calls = []
function! semantic_ctags_diff#run_markdown(base, head, ...) abort
  call add(g:scd_calls, [a:base, a:head])
  " Mirrors what open_scratch() does on the g:semantic_ctags_diff_open_cmd path.
  execute g:semantic_ctags_diff_open_cmd
  setlocal buftype=nofile bufhidden=wipe noswapfile modifiable
  call setline(1, ['report ' . a:base . '..' . a:head])
endfunction

" --- a repo whose branches diverge asymmetrically ---------------------------

let s:repo = resolve(tempname())
call mkdir(s:repo, 'p')
call s:git(s:repo, 'init -q')
" Name the default branch without relying on git >= 2.28 defaults.
call s:git(s:repo, 'symbolic-ref HEAD refs/heads/master')
call writefile(['int base() { return 0; }'], s:repo . '/a.cpp')
call s:git(s:repo, 'add -A')
call s:git(s:repo, 'commit -qm shared-base')
let s:fork = trim(s:git(s:repo, 'rev-parse HEAD'))

call s:git(s:repo, 'checkout -q -b devel')
call writefile(['int base() { return 0; }', 'int feature_one() { return 1; }'],
      \ s:repo . '/a.cpp')
call s:git(s:repo, 'commit -qam devel-one')
call writefile(['int base() { return 0; }', 'int feature_two() { return 2; }'],
      \ s:repo . '/a.cpp')
call s:git(s:repo, 'commit -qam devel-two')

call s:git(s:repo, 'checkout -q master')
call writefile(['int base() { return 42; }'], s:repo . '/a.cpp')
call s:git(s:repo, 'commit -qam master-hotfix')

execute 'cd ' . fnameescape(s:repo)
CompareBranchesForMerge master devel

" --- layout -----------------------------------------------------------------

call s:ok(winnr('$') == 2, 'opens two panes, got ' . winnr('$'))
call s:ok(winnr() == 1, 'cursor starts in the left pane')

let s:a = join(getline(1, '$'), "\n")
call s:ok(s:a =~# '^A  master', 'left pane is branch A: ' . getline(1))
call s:ok(s:a =~# 'master-hotfix', 'left pane lists its own commit')
call s:ok(s:a !~# 'devel-one', 'left pane does not list the other branch')
" The merge base belongs in the footer, never as a selectable commit row.
call s:ok(empty(filter(getline(1, '$'),
      \ "v:val =~# '^\\x\\{7,40}\\>' && v:val =~# 'shared-base'")),
      \ 'left pane lists no commit from before the fork')
call s:ok(s:a =~# 'merge base  \x\{7,}.*shared-base',
      \ 'left pane names the merge base in its footer')
call s:ok(s:a =~# 'merging that commit into devel',
      \ 'left pane states the direction <CR> takes')

wincmd l
let s:b = join(getline(1, '$'), "\n")
call s:ok(s:b =~# '^B  devel', 'right pane is branch B: ' . getline(1))
call s:ok(s:b =~# 'devel-one' && s:b =~# 'devel-two',
      \ 'right pane lists both of its commits')
call s:ok(s:b !~# 'master-hotfix', 'right pane does not list the other branch')

" --- direction: base is always the OPPOSITE branch --------------------------

wincmd h
call cursor(4, 1)
let s:t = semantic_ctags_diff#merge#_target_at_cursor()
call s:ok(get(s:t, 'base', '') ==# 'devel',
      \ 'A: merges into devel, got base ' . string(get(s:t, 'base', '')))
call s:ok(get(s:t, 'head', '') ==# matchstr(getline(4), '^\x\+'),
      \ 'A: head is the commit under the cursor')
call s:ok(resolve(get(s:t, 'repo', '')) ==# resolve(s:repo),
      \ 'A: target carries the analysed repo')

wincmd l
call cursor(4, 1)
let s:t = semantic_ctags_diff#merge#_target_at_cursor()
call s:ok(get(s:t, 'base', '') ==# 'master',
      \ 'B: merges into master, got base ' . string(get(s:t, 'base', '')))

" Header, blank and footer lines carry no commit, so <CR> there is a no-op.
call cursor(1, 1)
call s:ok(semantic_ctags_diff#merge#_target_at_cursor() == {},
      \ 'header line selects no commit')
call cursor(line('$'), 1)
call s:ok(semantic_ctags_diff#merge#_target_at_cursor() == {},
      \ 'merge-base footer selects no commit')

" --- the report window is created once and then reused ----------------------

wincmd h
call cursor(4, 1)
let s:open_cmd = g:semantic_ctags_diff_open_cmd
call semantic_ctags_diff#merge#show_at_cursor()

call s:ok(len(g:scd_calls) == 1 && g:scd_calls[0][0] ==# 'devel',
      \ 'A: <CR> asks for a diff based on devel: ' . string(g:scd_calls))
call s:ok(winnr('$') == 3, 'report opens a third window, got ' . winnr('$'))
call s:ok(g:semantic_ctags_diff_open_cmd ==# s:open_cmd,
      \ 'g:semantic_ctags_diff_open_cmd is restored')
call s:ok(getline(1) =~# '^A  master',
      \ 'cursor returns to the history pane, on ' . getline(1))

wincmd l
call cursor(4, 1)
call semantic_ctags_diff#merge#show_at_cursor()
call s:ok(len(g:scd_calls) == 2 && g:scd_calls[1][0] ==# 'master',
      \ 'B: <CR> asks for a diff based on master: ' . string(g:scd_calls))
call s:ok(winnr('$') == 3,
      \ 'second <CR> reuses the report window, got ' . winnr('$'))

if s:fail
  cquit
endif
qall!
