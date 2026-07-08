" Self-check for /tmp result cache helpers.
" Run:  vim -N -u NONE -S test/cache.vim

set nocompatible
let s:root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
runtime plugin/semantic_ctags_diff.vim
runtime autoload/semantic_ctags_diff.vim

let g:semantic_ctags_diff_cache_dir = '/tmp/semantic_ctags_diff_test_' . getpid()

let s:cache = semantic_ctags_diff#_cache_id('/tmp/myrepo', 'aaa111', 'bbb222')
call assert_equal('aaa111..bbb222', semantic_ctags_diff#_cache_stem(s:cache))
call assert_equal(
      \ g:semantic_ctags_diff_cache_dir . '/myrepo/aaa111..bbb222.markdown',
      \ semantic_ctags_diff#_cache_path(s:cache, 'markdown'))

let s:lines = ['line one', 'line two']
call semantic_ctags_diff#_cache_write(s:cache, 'markdown', s:lines)
call assert_equal(s:lines, semantic_ctags_diff#_cache_read(s:cache, 'markdown'))
call assert_equal([], semantic_ctags_diff#_cache_read(s:cache, 'json'))

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
