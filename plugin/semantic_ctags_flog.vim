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

" Flog command used by the :SemanticCtagsDiffFlogSymbol picker.
" 'Flog' opens a NEW TAB (commit graph + diff), like plain :Flog.
" 'Flogsplit' opens a split instead.
let g:semantic_ctags_diff_flog_open =
      \ get(g:, 'semantic_ctags_diff_flog_open', 'Flog')
let g:semantic_ctags_diff_flog_file_maps =
      \ get(g:, 'semantic_ctags_diff_flog_file_maps', 1)

" In a :FlogFile graph, <CR> opens a horizontal split below showing the
" difftastic diff of the commit under the cursor for that one file.
let g:semantic_ctags_diff_flog_difftastic =
      \ get(g:, 'semantic_ctags_diff_flog_difftastic', 1)
" Height of that split; 0 splits evenly.
let g:semantic_ctags_diff_flog_difftastic_height =
      \ get(g:, 'semantic_ctags_diff_flog_difftastic_height', 20)
" Split modifier: 'botright' (full width, below) or 'belowright'.
let g:semantic_ctags_diff_flog_difftastic_split =
      \ get(g:, 'semantic_ctags_diff_flog_difftastic_split', 'botright')
" 1 moves the cursor into the diff; 0 keeps it in the graph to keep browsing.
let g:semantic_ctags_diff_flog_difftastic_focus =
      \ get(g:, 'semantic_ctags_diff_flog_difftastic_focus', 0)

function! s:flog_symbol(open_cmd, kind_filter) abort
  call semantic_ctags_diff#flog_current_symbol(a:open_cmd, a:kind_filter)
endfunction

function! s:flog_file(open_cmd) abort
  call semantic_ctags_diff#flog#open_current_file(a:open_cmd)
endfunction

function! s:flog_include(open_cmd) abort
  call semantic_ctags_diff#flog#open_include(a:open_cmd)
endfunction

" Two families for the symbol under the cursor:
"   :Flog*      -> open history in a NEW TAB (commit graph + diff), like :Flog
"   :Flogsplit* -> open history in a split of the current window

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

" File history: log filtered to one path; <CR>/dd in the graph show that file only.
if exists(':FlogFile') != 2
  command! -bar FlogFile call s:flog_file('Flog')
endif
if exists(':FlogsplitFile') != 2
  command! -bar FlogsplitFile call s:flog_file('Flogsplit')
endif

" Difftastic diff of the commit under the cursor, for the graph's file only.
" <CR> is mapped to this in :FlogFile graphs; the command allows manual use.
if exists(':FlogDifftastic') != 2
  command! -bar FlogDifftastic call semantic_ctags_diff#flog#difftastic_at_cursor()
endif
nnoremap <silent> <Plug>(SemanticCtagsFlogDifftastic)
      \ :<C-u>call semantic_ctags_diff#flog#difftastic_at_cursor()<CR>

" #include under cursor -> Flog history of the resolved header (repo-relative).
if exists(':FlogInclude') != 2
  command! -bar FlogInclude call s:flog_include('Flog')
endif
if exists(':FlogsplitInclude') != 2
  command! -bar FlogsplitInclude call s:flog_include('Flogsplit')
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
