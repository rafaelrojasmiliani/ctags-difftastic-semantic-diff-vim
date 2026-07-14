" Self-check for command-line completion arg indexing.
" Run:  vim -N -u NONE -S test/complete.vim

set nocompatible
let s:root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
runtime autoload/semantic_ctags_diff.vim

function! s:arg_index(arglead, cmdline, cursorpos) abort
  return semantic_ctags_diff#_complete_arg_index(a:arglead, a:cmdline, a:cursorpos)
endfunction

" cursorpos is 1-based (Vim customlist convention).
call assert_equal(0, s:arg_index('', 'SemanticCtagsDiff', 18))
call assert_equal(0, s:arg_index('', 'SemanticCtagsDiff ', 19))
call assert_equal(1, s:arg_index('', 'SemanticCtagsDiff main ', 24))
call assert_equal(1, s:arg_index('', 'SemanticCtagsDiff main', 23))
call assert_equal(2, s:arg_index('', 'SemanticCtagsDiff main HEAD ', 29))

call assert_equal(0, semantic_ctags_diff#_complete_wants_file('', 'SemanticCtagsDiff main ', 24))
call assert_equal(1, semantic_ctags_diff#_complete_wants_file('', 'SemanticCtagsDiff main HEAD ', 29))
call assert_equal(0, semantic_ctags_diff#_complete_wants_file('', 'SemanticCtagsDiffFile main ', 28))

let s:refs = ['origin/main', 'main', 'feature/foo']
call assert_equal(['main'], semantic_ctags_diff#_filter_candidates(s:refs, 'main', 'prefix'))
call assert_equal(['origin/main'], semantic_ctags_diff#_filter_candidates(s:refs, 'origin', 'prefix'))

if empty(v:errors)
  echo 'complete: OK'
  qall!
else
  for s:e in v:errors
    echom s:e
  endfor
  cquit
endif
