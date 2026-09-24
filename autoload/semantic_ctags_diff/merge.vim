" autoload/semantic_ctags_diff/merge.vim
" :CompareBranchesForMerge — two first-parent histories side by side, and the
" semantic diff of merging the commit under the cursor into the opposite tip.
"
" The history is drawn from `git log` here rather than by vim-flog: with
" --first-parent the history is a straight line, so flog's graph column would
" be one '*' per row and buy nothing, while owning the buffer keeps <CR> ours
" instead of flog's commit view.

scriptencoding utf-8

" Short hash first: s:commit_at_cursor() only has to read column 1, and the
" header and merge-base footer are unselectable precisely because they do not
" start with one.
let s:log_format = '%h %ad %<(16,trunc)%an %s'

function! s:git(repo, args) abort
  let l:out = systemlist('git -C ' . shellescape(a:repo) . ' ' . a:args . ' 2>/dev/null')
  return v:shell_error == 0 ? l:out : []
endfunction

" Full sha of {ref}, or '' when it does not name a commit in {repo}.
function! s:verify(repo, ref) abort
  let l:out = s:git(a:repo, 'rev-parse --verify --quiet '
        \ . shellescape(a:ref . '^{commit}'))
  return empty(l:out) ? '' : trim(l:out[0])
endfunction

function! s:current_branch(repo) abort
  let l:out = s:git(a:repo, 'rev-parse --abbrev-ref HEAD')
  return empty(l:out) ? 'HEAD' : trim(l:out[0])
endfunction

function! s:describe(repo, rev) abort
  let l:out = s:git(a:repo, 'log -1 --date=short --format='
        \ . shellescape(s:log_format) . ' ' . shellescape(a:rev))
  return empty(l:out) ? a:rev : l:out[0]
endfunction

" --- history panes ----------------------------------------------------------

function! s:highlight_pane() abort
  syntax match scdMergeHash '^\x\{7,40}\>'
  syntax match scdMergeDate '\<\d\{4}-\d\d-\d\d\>'
  syntax match scdMergeMeta '^\%(<CR>:\|merge base\).*'
  syntax match scdMergeHead '\%1l.*'
  highlight default link scdMergeHash Identifier
  highlight default link scdMergeDate Comment
  highlight default link scdMergeMeta Comment
  highlight default link scdMergeHead Title
endfunction

" Turn the current window into one history pane.
"
" {mine} is the branch it lists; {other} is the tip those commits would be
" merged into. Keeping both on the buffer is what makes <CR> directional: the
" same key means "into devel" on the left and "into master" on the right.
function! s:render_pane(repo, side, mine, other, mergebase) abort
  let l:log = s:git(a:repo, 'log --first-parent --date=short --format='
        \ . shellescape(s:log_format) . ' '
        \ . shellescape(a:mergebase . '..' . a:mine))

  let l:lines = [
        \ a:side . '  ' . a:mine . '  —  ' . len(l:log) . ' commit(s) since the fork',
        \ '<CR>: semantic diff of merging that commit into ' . a:other,
        \ '',
        \ ]
  call extend(l:lines, empty(l:log) ? ['(nothing since the fork)'] : l:log)
  call extend(l:lines, ['', 'merge base  ' . s:describe(a:repo, a:mergebase)])

  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nowrap nonumber cursorline modifiable
  silent %delete _
  call setline(1, l:lines)
  setlocal nomodifiable
  call s:highlight_pane()

  " Pin the analysed repo so a submodule comparison cannot drift to the
  " superproject, exactly as the report and flog buffers do.
  let b:semantic_ctags_diff_repo = a:repo
  let b:scd_merge_mine = a:mine
  let b:scd_merge_other = a:other

  " A pane left over from an earlier run may still hold the name.
  try
    execute 'file ' . fnameescape('merge://' . a:side . '/' . a:mine)
  catch /^Vim\%((\a\+)\)\=:E95:/
  endtry

  nnoremap <buffer><silent> <CR>
        \ :<C-u>call semantic_ctags_diff#merge#show_at_cursor()<CR>

  " First commit row, so <CR> works without moving first.
  call cursor(4, 1)
endfunction

" --- :CompareBranchesForMerge -----------------------------------------------

function! semantic_ctags_diff#merge#compare(args) abort
  let l:parts = split(a:args)
  if empty(l:parts) || len(l:parts) > 2
    echoerr 'Usage: :CompareBranchesForMerge [branch-a] <branch-b>'
    return
  endif

  try
    let l:repo = semantic_ctags_diff#repo_root()
  catch /.*/
    echoerr v:exception
    return
  endtry

  let l:a = len(l:parts) == 2 ? l:parts[0] : s:current_branch(l:repo)
  let l:b = l:parts[-1]

  for l:ref in [l:a, l:b]
    if empty(s:verify(l:repo, l:ref))
      echoerr 'semantic_ctags_diff: not a commit in ' . l:repo . ': ' . l:ref
      return
    endif
  endfor

  let l:mb = s:git(l:repo, 'merge-base ' . shellescape(l:a) . ' ' . shellescape(l:b))
  if empty(l:mb)
    echoerr 'semantic_ctags_diff: ' . l:a . ' and ' . l:b
          \ . ' have no common ancestor'
    return
  endif
  let l:mb = trim(l:mb[0])

  tabnew
  call s:render_pane(l:repo, 'A', l:a, l:b, l:mb)
  rightbelow vnew
  call s:render_pane(l:repo, 'B', l:b, l:a, l:mb)
  wincmd h
endfunction

" --- <CR>: semantic diff for the commit under the cursor --------------------

" {repo, base, head} for the commit under the cursor, or {} off a commit line.
"
" head is that commit and base is the *opposite* branch's tip, so the report
" answers "what would merging this commit into the other branch bring": the
" engine diffs merge-base(base, head)..head, which is the fork point for any
" commit on either side.
function! semantic_ctags_diff#merge#_target_at_cursor() abort
  let l:commit = matchstr(getline('.'), '^\x\{7,40}\>')
  if empty(l:commit) || empty(get(b:, 'scd_merge_other', ''))
    return {}
  endif
  return {
        \ 'repo': get(b:, 'semantic_ctags_diff_repo', ''),
        \ 'base': b:scd_merge_other,
        \ 'head': l:commit,
        \ }
endfunction

function! s:report_win() abort
  for l:nr in range(1, winnr('$'))
    if getwinvar(l:nr, 'scd_merge_report', 0)
      return win_getid(l:nr)
    endif
  endfor
  return 0
endfunction

function! semantic_ctags_diff#merge#show_at_cursor() abort
  let l:target = semantic_ctags_diff#merge#_target_at_cursor()
  if empty(l:target)
    echo 'semantic_ctags_diff: no commit on this line'
    return
  endif

  let l:origin = win_getid()
  let l:win = s:report_win()
  if l:win
    call win_gotoid(l:win)
  else
    execute semantic_ctags_diff#difftastic#split_cmd(
          \ get(g:, 'semantic_ctags_diff_merge_report_split', 'botright'),
          \ get(g:, 'semantic_ctags_diff_merge_report_height', 20))
    " Window-local, so it survives the :enew below and marks this window as the
    " one every later <CR> reuses.
    let w:scd_merge_report = 1
  endif

  echo 'semantic_ctags_diff: merging ' . l:target.head . ' into '
        \ . l:target.base . ' …'

  " run() resolves the repo from the current buffer and opens its scratch with
  " g:semantic_ctags_diff_open_cmd; pin the first and neutralise the second so
  " the report replaces this window instead of stacking another split.
  let b:semantic_ctags_diff_repo = l:target.repo
  let l:saved = g:semantic_ctags_diff_open_cmd
  try
    let g:semantic_ctags_diff_open_cmd = 'enew'
    call semantic_ctags_diff#run_markdown(l:target.base, l:target.head)
  finally
    let g:semantic_ctags_diff_open_cmd = l:saved
    call win_gotoid(l:origin)
  endtry
endfunction
