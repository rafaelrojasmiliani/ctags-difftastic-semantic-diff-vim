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
