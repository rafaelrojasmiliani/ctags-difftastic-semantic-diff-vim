" Difftastic-in-Vim: Fugitive-style file diff rendered with difftastic (difft).
" Independent of the Python submodule; requires git + difftastic.

if exists('g:loaded_semantic_ctags_difftastic')
  finish
endif
let g:loaded_semantic_ctags_difftastic = 1

let g:semantic_ctags_diff_difft = get(g:, 'semantic_ctags_diff_difft', 'difft')
let g:semantic_ctags_diff_difftastic_display =
      \ get(g:, 'semantic_ctags_diff_difftastic_display', 'side-by-side')
let g:semantic_ctags_diff_difftastic_context =
      \ get(g:, 'semantic_ctags_diff_difftastic_context', 3)
" Colourise the diff: red removals, green additions, down to sub-word spans.
let g:semantic_ctags_diff_difftastic_color =
      \ get(g:, 'semantic_ctags_diff_difftastic_color', 1)
" difftastic's own language syntax colouring; off keeps red/green the only signal.
let g:semantic_ctags_diff_difftastic_syntax =
      \ get(g:, 'semantic_ctags_diff_difftastic_syntax', 'off')

" :highlight default so a colorscheme or user setting wins over these.
function! s:difftastic_colors() abort
  highlight default SemanticCtagsDiffRemoved ctermfg=Red      guifg=#ff5f5f
  highlight default SemanticCtagsDiffAdded   ctermfg=Green    guifg=#00d75f
  highlight default SemanticCtagsDiffFile    ctermfg=Yellow   guifg=#ffd75f
  highlight default SemanticCtagsDiffDim     ctermfg=DarkGray guifg=#808080
endfunction

augroup SemanticCtagsDifftasticColors
  autocmd!
  " Loading a colorscheme clears highlight groups; put them back.
  autocmd ColorScheme * call s:difftastic_colors()
augroup END

call s:difftastic_colors()

" :Gdifftastic [ref]   — horizontal split (default ref: HEAD)
" :Gvdifftastic [ref]  — vertical split
if !exists(':Gdifftastic')
  command! -nargs=? -complete=customlist,semantic_ctags_diff#complete Gdifftastic
        \ call semantic_ctags_diff#difftastic#diff('botright new', <q-args>)
endif
if !exists(':Gvdifftastic')
  command! -nargs=? -complete=customlist,semantic_ctags_diff#complete Gvdifftastic
        \ call semantic_ctags_diff#difftastic#diff('botright vnew', <q-args>)
endif
