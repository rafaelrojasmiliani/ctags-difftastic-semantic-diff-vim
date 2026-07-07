" Self-check for semantic_ctags_diff#_target_at_cursor() markdown parsing.
" Run headless:  vim -N -u NONE -S test/nav_parse.vim
" Exits 0 on success, 1 on failure (via :cquit).

set nocompatible
let s:root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
runtime autoload/semantic_ctags_diff.vim

let s:report = [
      \ 'Semantic Ctags Diff',
      \ '===================',
      \ '',
      \ 'Repo: /tmp/repo',
      \ 'Base: main',
      \ 'Head: HEAD',
      \ 'Command: ...',
      \ '',
      \ 'Removed symbols',
      \ '===============',
      \ '',
      \ '* function ImFusion::old::gone',
      \ '  file: src/old.cpp',
      \ '  range: 40-52',
      \ '',
      \ 'Modified symbols',
      \ '----------------',
      \ '',
      \ 'src/robot.cpp',
      \ '',
      \ '* function RobotController::configure',
      \ '  old range: 10-20',
      \ '  new range: 12-25',
      \ '  changed new lines: 13, 14',
      \ '',
      \ 'File-scope changes',
      \ '------------------',
      \ '',
      \ 'src/misc.cpp',
      \ '',
      \ '* added lines: 5, 6, 7',
      \ '* deleted lines: 9',
      \ ]

enew
call setline(1, s:report)

function! s:target_at(lnum) abort
  call cursor(a:lnum, 1)
  return semantic_ctags_diff#_target_at_cursor()
endfunction

" Cursor on the removed symbol's range line.
call assert_equal(
      \ {'path': 'src/old.cpp', 'line': 40, 'classification': 'removed'},
      \ s:target_at(14))

" Cursor on the modified symbol marker line.
call assert_equal(
      \ {'path': 'src/robot.cpp', 'line': 12, 'classification': 'modified'},
      \ s:target_at(21))

" Cursor on the modified symbol's "new range" line.
call assert_equal(
      \ {'path': 'src/robot.cpp', 'line': 12, 'classification': 'modified'},
      \ s:target_at(23))

" Cursor on a file-scope "added lines" line.
call assert_equal(
      \ {'path': 'src/misc.cpp', 'line': 5, 'classification': 'file_scope'},
      \ s:target_at(32))

" Cursor in the header (no section) -> no target.
call assert_equal({}, s:target_at(4))

if empty(v:errors)
  echo 'nav_parse: OK'
  qall!
else
  for s:e in v:errors
    echom s:e
  endfor
  cquit
endif
