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
" Needs difftastic; git aborts with exit 128 when the external diff is missing.
if executable(g:semantic_ctags_diff_difft)
  let s:out = system(semantic_ctags_diff#difftastic#command(
        \ [s:head . '^!'], 'src/a.cpp', s:repo))
  call assert_match('a\.cpp', s:out)
  call assert_notmatch('b\.cpp', s:out)
endif

call system('rm -rf ' . shellescape(s:repo))

" --- ANSI colour parsing ----------------------------------------------------
" difftastic signals add/remove ONLY through colour, so this parser is the
" whole feature. Checked against canned output so it runs without difftastic.

" Collect {group: [highlighted text, ...]} from a parsed line.
function! s:spans(line) abort
  let [l:clean, l:groups] = semantic_ctags_diff#difftastic#strip_ansi([a:line], 0)
  let l:out = {}
  for [l:group, l:positions] in items(l:groups)
    let l:out[l:group] = map(copy(l:positions),
          \ {_, p -> strpart(l:clean[p[0] - 1], p[1] - 1, p[2])})
  endfor
  return [l:clean[0], l:out]
endfunction

" A real difftastic side-by-side line: red left half, green right half, with
" sub-word spans (91 = removed, 92 = added, 2 = dim gutter).
let s:line = "\e[91;1m3 \e[0mint \e[91mremoveMe\e[0m() { return \e[91m1\e[0m; }"
      \ . "    \e[92;1m3 \e[0mint \e[92mmodify\e[0m() { return \e[92m4242\e[0m; }"
let [s:clean, s:got] = s:spans(s:line)

" Escapes must not survive into the buffer text.
call assert_notmatch("\e", s:clean)
call assert_match('int removeMe() { return 1; }', s:clean)

call assert_equal(['3 ', 'removeMe', '1'], get(s:got, 'SemanticCtagsDiffRemoved', []))
call assert_equal(['3 ', 'modify', '4242'], get(s:got, 'SemanticCtagsDiffAdded', []))

" Unchanged lines are dim, and the file header is yellow.
let [s:clean, s:got] = s:spans("\e[2m7 \e[0mint keep() { return 0; }")
call assert_equal(['7 '], get(s:got, 'SemanticCtagsDiffDim', []))
call assert_equal([], get(s:got, 'SemanticCtagsDiffAdded', []))
let [s:clean, s:got] = s:spans("\e[1m\e[93msrc/x.cpp\e[39m\e[0m\e[2m --- C++\e[0m")
call assert_equal(['src/x.cpp'], get(s:got, 'SemanticCtagsDiffFile', []))

" Line numbers are offset by the buffer header, and plain text stays unmarked.
let [s:clean, s:groups] = semantic_ctags_diff#difftastic#strip_ansi(
      \ ['plain', "\e[92madded\e[0m"], 5)
call assert_equal(['plain', 'added'], s:clean)
call assert_equal([[7, 1, 5]], s:groups['SemanticCtagsDiffAdded'])

" Colour off must leave DFT_COLOR=never so nothing needs stripping.
let g:semantic_ctags_diff_difftastic_color = 0
call assert_match('DFT_COLOR=never', semantic_ctags_diff#difftastic#command('HEAD', 'f.c', '/tmp'))
let g:semantic_ctags_diff_difftastic_color = 1
call assert_match('DFT_COLOR=always', semantic_ctags_diff#difftastic#command('HEAD', 'f.c', '/tmp'))

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
