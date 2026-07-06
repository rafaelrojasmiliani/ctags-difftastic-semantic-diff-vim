" Flog + ctags integration via Python (no Vim ctags parsing, no JSON ctags).
" Replaces duplicated logic from legacy files/ scripts.

if exists('g:loaded_semantic_ctags_flog')
  finish
endif
let g:loaded_semantic_ctags_flog = 1

" Only define when vim-flog is present and user has not defined custom commands.
if exists(':Flog') != 2 && exists(':Flogsplit') != 2
  finish
endif

function! s:flog_symbol(open_cmd, kind_filter) abort
  call semantic_ctags_diff#flog_current_symbol(a:open_cmd, a:kind_filter)
endfunction

if exists(':FlogsplitSymbol') != 2
  command! -bar FlogsplitSymbol call s:flog_symbol('Flogsplit', '')
endif
if exists(':FlogSymbol') != 2
  command! -bar FlogSymbol call s:flog_symbol('Flog', '')
endif
if exists(':FlogsplitFunction') != 2
  command! -bar FlogsplitFunction call s:flog_symbol('Flogsplit', 'function')
endif
if exists(':FlogFunction') != 2
  command! -bar FlogFunction call s:flog_symbol('Flog', 'function')
endif
if exists(':FlogsplitClass') != 2
  command! -bar FlogsplitClass call s:flog_symbol('Flogsplit', 'class')
endif
if exists(':FlogClass') != 2
  command! -bar FlogClass call s:flog_symbol('Flog', 'class')
endif
if exists(':FlogsplitNamespace') != 2
  command! -bar FlogsplitNamespace call s:flog_symbol('Flogsplit', 'namespace')
endif
if exists(':FlogNamespace') != 2
  command! -bar FlogNamespace call s:flog_symbol('Flog', 'namespace')
endif

" Optional Flog diff highlight groups (UI only — stays in Vim).
function! s:flog_diff_colors() abort
  highlight diffAdded   ctermfg=Green guifg=#00d75f
  highlight diffRemoved ctermfg=Red   guifg=#ff5f5f
  highlight flogDiffAdded   ctermfg=Green guifg=#00d75f
  highlight flogDiffRemoved ctermfg=Red   guifg=#ff5f5f
  highlight flogDiffLine      ctermfg=Cyan   guifg=#5fd7ff
  highlight flogDiffFile      ctermfg=Yellow guifg=#ffd75f
  highlight flogDiffOldFile   ctermfg=Red    guifg=#ff8787
  highlight flogDiffNewFile   ctermfg=Green  guifg=#87ff87
  highlight flogDiffIndexLine ctermfg=DarkGray guifg=#808080
endfunction

augroup SemanticCtagsFlogColors
  autocmd!
  autocmd ColorScheme * call s:flog_diff_colors()
  autocmd Syntax floggraph call s:flog_diff_colors()
augroup END

call s:flog_diff_colors()
