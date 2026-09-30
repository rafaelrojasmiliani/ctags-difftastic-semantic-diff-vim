" autoload/semantic_ctags_diff/conflicts.vim
" :ShowMergeConflict — files that would conflict merging branch B into A (the
" current commit by default), with the semantic report of A..B split below.
"
" Conflict detection is the Python CLI's job (--merge-conflicts); this file only
" draws the list and opens windows.

scriptencoding utf-8

function! s:render(repo, data) abort
  let l:lines = [
        \ 'Merge conflicts: ' . a:data.theirs . ' into ' . a:data.ours
        \   . '  —  ' . len(a:data.conflicts) . ' file(s)',
        \ 'merge base ' . a:data.merge_base[:9]
        \   . '   <CR>: vertical diff + difftastic of that file',
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
    let l:cmd = semantic_ctags_diff#_cli_prefix(semantic_ctags_diff#python_project_root())
          \ . ' --merge-conflicts --repo ' . shellescape(l:repo)
          \ . ' --base ' . shellescape(l:ours) . ' --head ' . shellescape(l:theirs)
  catch /.*/
    echoerr v:exception
    return
  endtry

  let [l:out, l:err, l:exit] = semantic_ctags_diff#_run_shell(l:cmd)
  if l:exit != 0
    call semantic_ctags_diff#_open_error(l:err + ['', 'Command: ' . l:cmd])
    echoerr 'semantic_ctags_diff: merge-conflict check failed'
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
  call semantic_ctags_diff#open_revs_diff(b:semantic_ctags_diff_repo,
        \ b:scd_conflict_ours, b:scd_conflict_theirs, l:path)
endfunction
