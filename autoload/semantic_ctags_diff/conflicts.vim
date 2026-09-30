" autoload/semantic_ctags_diff/conflicts.vim
" :ShowMergeConflict — files that would conflict merging branch B into A (the
" current commit by default), with the semantic report of A..B split below.
"
" Conflict detection is the Python CLI's job (--merge-conflicts); this file only
" draws the list and opens windows.

scriptencoding utf-8

" `<cli> --merge-conflicts` stdout lines, or v:null after reporting a failure.
function! s:cli(repo, ours, theirs, extra) abort
  let l:cmd = semantic_ctags_diff#_cli_prefix(semantic_ctags_diff#python_project_root())
        \ . ' --merge-conflicts --repo ' . shellescape(a:repo)
        \ . ' --base ' . shellescape(a:ours) . ' --head ' . shellescape(a:theirs)
        \ . join(map(copy(a:extra), '" " . shellescape(v:val)'), '')
  let [l:out, l:err, l:exit] = semantic_ctags_diff#_run_shell(l:cmd)
  if l:exit != 0
    call semantic_ctags_diff#_open_error(l:err + ['', 'Command: ' . l:cmd])
    echoerr 'semantic_ctags_diff: merge-conflict command failed'
    return v:null
  endif
  return l:out
endfunction

function! s:render(repo, data) abort
  let l:lines = [
        \ 'Merge conflicts: ' . a:data.theirs . ' into ' . a:data.ours
        \   . '  —  ' . len(a:data.conflicts) . ' file(s)',
        \ 'merge base ' . a:data.merge_base[:9]
        \   . '   <CR>: ours | merged with conflict markers | theirs',
        \ '',
        \ ]
  " Line number -> path, so <CR> never has to parse the display format.
  let b:scd_conflict_paths = {}
  for l:c in a:data.conflicts
    call add(l:lines, printf('  %-14s %s', l:c.kind, l:c.path))
    let b:scd_conflict_paths[len(l:lines)] = l:c.path
  endfor
  if empty(a:data.conflicts)
    call add(l:lines, '  (no conflicting files)')
  endif

  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nowrap nonumber cursorline modifiable
  silent %delete _
  call setline(1, l:lines)
  setlocal nomodifiable
  syntax match scdConflictHead '\%<3l.*'
  syntax match scdConflictKind '^\s\+\zs\S\+'
  highlight default link scdConflictHead Title
  highlight default link scdConflictKind WarningMsg

  " Pin the repo (submodules) and the shas, so <CR> keeps working after the
  " branches move or another report changes the plugin's state.
  let b:semantic_ctags_diff_repo = a:repo
  let b:scd_conflict_ours = a:data.ours_commit
  let b:scd_conflict_theirs = a:data.theirs_commit
  let b:scd_conflict_names = [a:data.ours, a:data.theirs]
  try
    execute 'file ' . fnameescape('conflicts://' . a:data.ours . '...' . a:data.theirs)
  catch /^Vim\%((\a\+)\)\=:E95:/
  endtry

  nnoremap <buffer><silent> <CR>
        \ :<C-u>call semantic_ctags_diff#conflicts#open_at_cursor()<CR>
  call cursor(4, 3)
endfunction

function! semantic_ctags_diff#conflicts#show(args) abort
  let l:parts = split(a:args)
  if empty(l:parts) || len(l:parts) > 2
    echoerr 'Usage: :ShowMergeConflict [branch-a] <branch-b>'
    return
  endif
  let l:ours = len(l:parts) == 2 ? l:parts[0] : 'HEAD'
  let l:theirs = l:parts[-1]

  try
    let l:repo = semantic_ctags_diff#repo_root()
  catch /.*/
    echoerr v:exception
    return
  endtry
  let l:out = s:cli(l:repo, l:ours, l:theirs, [])
  if l:out is v:null
    return
  endif

  tabnew
  call s:render(l:repo, json_decode(join(l:out, "\n")))
  let l:list = win_getid()

  " run() opens its scratch with g:semantic_ctags_diff_open_cmd and resolves the
  " repo from this buffer's b:semantic_ctags_diff_repo.
  let l:saved = g:semantic_ctags_diff_open_cmd
  try
    let g:semantic_ctags_diff_open_cmd = semantic_ctags_diff#difftastic#split_cmd(
          \ get(g:, 'semantic_ctags_diff_conflicts_report_split', 'botright'),
          \ get(g:, 'semantic_ctags_diff_conflicts_report_height', 20))
    call semantic_ctags_diff#run_markdown(l:ours, l:theirs)
  finally
    let g:semantic_ctags_diff_open_cmd = l:saved
    call win_gotoid(l:list)
  endtry
endfunction

function! semantic_ctags_diff#conflicts#open_at_cursor() abort
  let l:path = get(get(b:, 'scd_conflict_paths', {}), line('.'), '')
  if empty(l:path)
    echo 'semantic_ctags_diff: no file on this line'
    return
  endif
  let l:repo = b:semantic_ctags_diff_repo
  " Branch names, not shas, so the markers read '<<<<<<< HEAD' / '>>>>>>> devel'.
  let l:merged = s:cli(l:repo, b:scd_conflict_names[0], b:scd_conflict_names[1],
        \ ['--path', l:path])
  if l:merged is v:null
    return
  endif
  call semantic_ctags_diff#open_revs_diff(l:repo,
        \ b:scd_conflict_ours, b:scd_conflict_theirs, l:path)
  call s:merged_pane(l:path, l:merged)
endfunction

let s:marker = '^\%(<<<<<<<\|||||||\|=======\|>>>>>>>\)\%( .*\)\=$'

" ours | merged | theirs: window 1 is ours (top-left), so the merged file opens
" to its right, and difftastic stays full width below all three.
function! s:merged_pane(path, lines) abort
  let l:ft = getbufvar(winbufnr(1), '&filetype')
  1wincmd w
  rightbelow vnew
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  call setline(1, a:lines)
  setlocal nomodifiable
  let &l:filetype = l:ft
  try
    execute 'file ' . fnameescape('merged://' . tabpagenr() . '/' . a:path)
  catch /^Vim\%((\a\+)\)\=:E95:/
  endtry
  diffthis
  call matchadd('ErrorMsg', s:marker)
  call cursor(1, 1)
  if !search('^<<<<<<<', 'cW')
    echo 'semantic_ctags_diff: ' . a:path . ' has no conflict markers (modify/delete?)'
  endif
  normal! zz
endfunction
