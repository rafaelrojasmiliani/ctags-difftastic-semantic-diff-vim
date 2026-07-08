" Self-check for #include parsing (no flog/git required).
" Run:  vim -N -u NONE -S test/flog_include.vim

set nocompatible
let s:root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
runtime autoload/semantic_ctags_diff/flog.vim

enew
call setline(1, [
      \ '#include "robotics/RobotController.h"',
      \ '#include <vector>',
      \ '#include "missing',
      \ '#include "foo.h"  // trailing comment',
      \ ])

call assert_equal(['robotics/RobotController.h', 0], semantic_ctags_diff#flog#parse_include_line(1))
call assert_equal(['vector', 1], semantic_ctags_diff#flog#parse_include_line(2))
call assert_equal(['', 0], semantic_ctags_diff#flog#parse_include_line(3))
call assert_equal(['foo.h', 0], semantic_ctags_diff#flog#parse_include_line(4))

if empty(v:errors)
  echo 'flog_include: OK'
  qall!
else
  for s:e in v:errors
    echom s:e
  endfor
  cquit
endif
