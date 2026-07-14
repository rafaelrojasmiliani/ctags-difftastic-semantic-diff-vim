" vim-semantic-ctags-diff: semantic branch diffs via ctags + PyDriller
" Vim 8 compatible. No default mappings.

if exists('g:loaded_semantic_ctags_diff')
  finish
endif
let g:loaded_semantic_ctags_diff = 1

let g:semantic_ctags_diff_python = get(g:, 'semantic_ctags_diff_python', 'python3')
let g:semantic_ctags_diff_root = get(g:, 'semantic_ctags_diff_root', '')
let g:semantic_ctags_diff_cli = get(g:, 'semantic_ctags_diff_cli', '')
let g:semantic_ctags_diff_default_base = get(g:, 'semantic_ctags_diff_default_base', 'main')
let g:semantic_ctags_diff_default_head = get(g:, 'semantic_ctags_diff_default_head', 'HEAD')
" ctags executable (classic tags file; JSON output format is NOT used)
let g:semantic_ctags_diff_ctags = get(g:, 'semantic_ctags_diff_ctags', 'ctags')
let g:semantic_ctags_diff_format = get(g:, 'semantic_ctags_diff_format', 'markdown')
let g:semantic_ctags_diff_include = get(g:, 'semantic_ctags_diff_include',
      \ '.c,.cc,.cpp,.cxx,.h,.hh,.hpp,.hxx')
let g:semantic_ctags_diff_open_cmd = get(g:, 'semantic_ctags_diff_open_cmd', 'botright new')
let g:semantic_ctags_diff_debug = get(g:, 'semantic_ctags_diff_debug', 0)
let g:semantic_ctags_diff_use_fugitive_worktree = get(g:, 'semantic_ctags_diff_use_fugitive_worktree', 1)
let g:semantic_ctags_diff_extra_args = get(g:, 'semantic_ctags_diff_extra_args', [])
let g:semantic_ctags_diff_cache = get(g:, 'semantic_ctags_diff_cache', 1)
let g:semantic_ctags_diff_cache_dir = get(g:, 'semantic_ctags_diff_cache_dir', '/tmp/semantic_ctags_diff')

command! -nargs=* -complete=customlist,semantic_ctags_diff#complete SemanticCtagsDiff
      \ call semantic_ctags_diff#cmd_diff(<q-args>)
command! -nargs=* -complete=customlist,semantic_ctags_diff#complete SemanticCtagsDiffJson
      \ call semantic_ctags_diff#cmd_diff_json(<q-args>)
command! -nargs=* -complete=customlist,semantic_ctags_diff#complete SemanticCtagsDiffFile
      \ call semantic_ctags_diff#cmd_diff_file(<q-args>)
command! -nargs=* -complete=customlist,semantic_ctags_diff#complete SemanticCtagsDiffFileJson
      \ call semantic_ctags_diff#cmd_diff_file_json(<q-args>)
command! -nargs=0 SemanticCtagsDiffCurrent
      \ call semantic_ctags_diff#run_current()
command! -nargs=0 SemanticCtagsDiffMain
      \ call semantic_ctags_diff#run_markdown('main', 'HEAD')
command! -nargs=0 SemanticCtagsDiffOriginMain
      \ call semantic_ctags_diff#run_markdown('origin/main', 'HEAD')
command! -nargs=0 SemanticCtagsDiffRefresh
      \ call semantic_ctags_diff#refresh()
command! -nargs=0 SemanticCtagsDiffCopyCommand
      \ call semantic_ctags_diff#copy_command()
command! -nargs=0 SemanticCtagsDiffDebugLog
      \ call semantic_ctags_diff#debug_log()
command! -nargs=0 SemanticCtagsDiffClearCache
      \ call semantic_ctags_diff#clear_cache()
command! -nargs=0 SemanticCtagsDiffClearDebugLog
      \ call semantic_ctags_diff#clear_debug_log()

if exists(':Flog') == 2
  command! -nargs=* -complete=customlist,semantic_ctags_diff#complete SemanticCtagsDiffFlog
        \ call semantic_ctags_diff#cmd_flog(<q-args>)
  command! -nargs=0 SemanticCtagsDiffFlogSymbol
        \ call semantic_ctags_diff#flog_symbol()
endif
