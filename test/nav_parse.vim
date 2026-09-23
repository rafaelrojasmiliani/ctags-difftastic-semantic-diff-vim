" Self-check for semantic_ctags_diff#_target_at_cursor() markdown parsing.
" Run headless:  vim -N -u NONE -S test/nav_parse.vim
" Exits 0 on success, 1 on failure (via :cquit).
"
" The report prints symbol names only, so path and line are resolved from the
" JSON result; the state is seeded here instead of shelling out to the CLI.

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
      \ 'Changed files',
      \ '=============',
      \ '',
      \ '  A src/new.cpp',
      \ '  M src/robot.cpp',
      \ '  D src/old.cpp',
      \ '',
      \ 'Added symbols',
      \ '=============',
      \ '',
      \ 'Functions:',
      \ '  + ImFusion::New::appeared',
      \ '',
      \ 'Members:',
      \ '  + ImFusion::New::Params::DeltaTime',
      \ '',
      \ 'Removed symbols',
      \ '===============',
      \ '',
      \ 'Functions:',
      \ '  - ImFusion::old::gone',
      \ '',
      \ 'Modified symbols',
      \ '----------------',
      \ '',
      \ 'Functions:',
      \ '  ~ RobotController::configure',
      \ '',
      \ ]

let s:json = {'files': [
      \ {'path': 'src/new.cpp',
      \  'added_symbols': [
      \     {'qualified_name': 'ImFusion::New::appeared', 'range': [30, 44]},
      \     {'qualified_name': 'ImFusion::New::Params::DeltaTime', 'range': [7, 7]}],
      \  'removed_symbols': [], 'modified_symbols': []},
      \ {'path': 'src/old.cpp',
      \  'added_symbols': [], 'modified_symbols': [],
      \  'removed_symbols': [{'qualified_name': 'ImFusion::old::gone', 'range': [40, 52]}]},
      \ {'path': 'src/robot.cpp',
      \  'added_symbols': [], 'removed_symbols': [],
      \  'modified_symbols': [{'qualified_name': 'RobotController::configure',
      \                        'old_range': [10, 20], 'new_range': [12, 25]}]},
      \ ]}

call semantic_ctags_diff#_seed_state('main', 'HEAD', '/tmp/repo', s:json)

enew
call setline(1, s:report)

" Locate a report line by pattern so the checks survive layout tweaks.
function! s:target_at(pattern) abort
  call cursor(1, 1)
  let l:lnum = search(a:pattern, 'cW')
  call assert_notequal(0, l:lnum, 'report line not found: ' . a:pattern)
  return semantic_ctags_diff#_target_at_cursor()
endfunction

" Added symbol: file and line come from the JSON, not from the report text.
let s:t = s:target_at('+ ImFusion::New::appeared')
call assert_equal('src/new.cpp', get(s:t, 'path', ''))
call assert_equal(30, get(s:t, 'line', -1))
call assert_equal('added', get(s:t, 'classification', ''))

" A member listed under its own heading resolves too.
let s:t = s:target_at('+ ImFusion::New::Params::DeltaTime')
call assert_equal(7, get(s:t, 'line', -1))

" Removed symbol: no file/range printed any more, and the line is the one it
" had in base, because that is the only revision containing it.
let s:t = s:target_at('- ImFusion::old::gone')
call assert_equal('src/old.cpp', get(s:t, 'path', ''))
call assert_equal(40, get(s:t, 'line', -1))
call assert_equal('removed', get(s:t, 'classification', ''))
call assert_equal(40, get(s:t, 'old_line', -1))

" Modified symbol: no file heading any more, so the path comes from the JSON,
" and the new-revision line wins.
let s:t = s:target_at('\~ RobotController::configure')
call assert_equal('src/robot.cpp', get(s:t, 'path', ''))
call assert_equal(12, get(s:t, 'line', -1))
call assert_equal('modified', get(s:t, 'classification', ''))
call assert_equal(10, get(s:t, 'old_line', -1))
call assert_equal(12, get(s:t, 'new_line', -1))

" "Changed files" entries carry git's status letter, parsed from the line.
call assert_equal(
      \ {'path': 'src/robot.cpp', 'line': 1, 'status': 'M', 'classification': 'file'},
      \ s:target_at('^  M src/robot.cpp'))
call assert_equal('D', get(s:target_at('^  D src/old.cpp'), 'status', ''))

" Cursor in the header (no section) -> no target.
call assert_equal({}, s:target_at('^Repo: '))

" A kind heading with no bullet above it inside the section -> no target.
call assert_equal({}, s:target_at('^Functions:'))

if empty(v:errors)
  echo 'nav_parse: OK'
  qall!
else
  for s:e in v:errors
    echom s:e
  endfor
  cquit
endif
