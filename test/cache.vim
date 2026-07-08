" Self-check for /tmp result cache helpers.
" Run:  vim -N -u NONE -S test/cache.vim

set nocompatible
let s:root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
runtime plugin/semantic_ctags_diff.vim
runtime autoload/semantic_ctags_diff.vim

let g:semantic_ctags_diff_cache_dir = '/tmp/semantic_ctags_diff_test_' . getpid()

let s:fp = semantic_ctags_diff#_cache_fingerprint('/tmp/py')
let s:key = semantic_ctags_diff#_cache_key('/tmp/repo', 'aaa', 'bbb', s:fp)
call assert_equal(s:key, semantic_ctags_diff#_cache_key('/tmp/repo', 'aaa', 'bbb', s:fp))
call assert_notequal(s:key, semantic_ctags_diff#_cache_key('/tmp/repo', 'aaa', 'ccc', s:fp))

let s:lines = ['line one', 'line two']
call semantic_ctags_diff#_cache_write(s:key, 'markdown', s:lines)
call assert_equal(s:lines, semantic_ctags_diff#_cache_read(s:key, 'markdown'))
call assert_equal([], semantic_ctags_diff#_cache_read(s:key, 'json'))

call semantic_ctags_diff#clear_cache()

if empty(v:errors)
  echo 'cache: OK'
  qall!
else
  for s:e in v:errors
    echom s:e
  endfor
  cquit
endif
