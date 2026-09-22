" Self-check for the Flog <CR> difftastic diff (needs git; difft optional).
" Run:  vim -N -u NONE -S test/flog_difftastic.vim

set nocompatible
let s:root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
runtime plugin/semantic_ctags_difftastic.vim
runtime autoload/semantic_ctags_diff/difftastic.vim

" --- fixture: repo with a root commit and a second commit touching 2 files ---
let s:repo = trim(system('mktemp -d'))
call system('git -C ' . shellescape(s:repo) . ' init -q')
call system('git -C ' . shellescape(s:repo) . ' config user.email t@e.com')
call system('git -C ' . shellescape(s:repo) . ' config user.name T')
call mkdir(s:repo . '/src', 'p')
call writefile(['int a(){return 1;}'], s:repo . '/src/a.cpp')
call writefile(['int b(){return 2;}'], s:repo . '/src/b.cpp')
call system('git -C ' . shellescape(s:repo) . ' add -A')
call system('git -C ' . shellescape(s:repo) . ' commit -qm root')
call writefile(['int a(){return 42;}'], s:repo . '/src/a.cpp')
call writefile(['int b(){return 99;}'], s:repo . '/src/b.cpp')
call system('git -C ' . shellescape(s:repo) . ' add -A')
call system('git -C ' . shellescape(s:repo) . ' commit -qm second')

let s:head = trim(system('git -C ' . shellescape(s:repo) . ' rev-parse HEAD'))
let s:rootc = trim(system('git -C ' . shellescape(s:repo) . ' rev-list --max-parents=0 HEAD'))

" A commit with a parent diffs as <sha>^! (parent..commit).
call assert_equal([s:head . '^!'],
      \ semantic_ctags_diff#difftastic#commit_revs(s:repo, s:head))

" A root commit has no parent: `git diff <sha>^!` would silently diff against
" the working tree, so it must diff against the empty tree instead.
let s:root_revs = semantic_ctags_diff#difftastic#commit_revs(s:repo, s:rootc)
call assert_equal(2, len(s:root_revs))
call assert_equal(s:rootc, s:root_revs[1])
call assert_notequal(s:rootc . '^!', s:root_revs[0])

" Each rev is escaped separately, so a 2-rev range stays 2 arguments.
let s:cmd = semantic_ctags_diff#difftastic#command(s:root_revs, 'src/a.cpp', s:repo)
call assert_match('src/a\.cpp', s:cmd)
call assert_notmatch('src/b\.cpp', s:cmd)

" The point of the feature: one commit, one file — b.cpp must not appear.
let s:out = system(semantic_ctags_diff#difftastic#command(
      \ [s:head . '^!'], 'src/a.cpp', s:repo))
call assert_match('a\.cpp', s:out)
call assert_notmatch('b\.cpp', s:out)

call system('rm -rf ' . shellescape(s:repo))

" --- buffer maps applied to a floggraph -------------------------------------
runtime autoload/semantic_ctags_diff/flog.vim

" Stand-ins for the plugs vim-flog defines; the guard must detect them.
" exists('<Plug>(..)') is always 0, so maparg() is what apply_file_maps uses.
nnoremap <Plug>(FlogVSplitCommitPathsRight) :echo "commit"<CR>
nnoremap <Plug>(FlogVDiffSplitPathsRight) :echo "vdiff"<CR>
nnoremap <Plug>(FlogVDiffSplitLastCommitPathsRight) :echo "last"<CR>

enew
let g:semantic_ctags_diff_flog_difftastic = 1
call semantic_ctags_diff#flog#apply_file_maps()

if executable(g:semantic_ctags_diff_difft)
  " <CR> shows this commit's diff for the graph's file only.
  call assert_match('difftastic_at_cursor', maparg('<CR>', 'n'))
  " Flog's whole-commit view moves to go, and stays reachable.
  call assert_equal('<Plug>(FlogVSplitCommitPathsRight)', maparg('go', 'n'))
endif
" Plug-backed maps must actually land (they silently did not before).
call assert_equal('<Plug>(FlogVDiffSplitPathsRight)', maparg('dd', 'n'))
call assert_equal('<Plug>(FlogVDiffSplitLastCommitPathsRight)', maparg('d!', 'n'))

" With difftastic disabled, <CR> falls back to Flog's path-scoped commit view.
enew
let g:semantic_ctags_diff_flog_difftastic = 0
call semantic_ctags_diff#flog#apply_file_maps()
call assert_equal('<Plug>(FlogVSplitCommitPathsRight)', maparg('<CR>', 'n'))

if empty(v:errors)
  echo 'flog_difftastic: OK'
  qall!
else
  for s:e in v:errors
    echom s:e
  endfor
  cquit
endif
