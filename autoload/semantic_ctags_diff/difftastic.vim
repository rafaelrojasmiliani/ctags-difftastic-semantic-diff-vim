" autoload/semantic_ctags_diff/difftastic.vim
" Difftastic (structural diff) ported into Vim: a Fugitive-style file diff that
" uses `difft` as git's external diff, rendered in a scratch buffer.
"
" No ctags, no Python — this is a pure Vim + git + difftastic integration and is
" independent of the semantic-branch-diff submodule.

scriptencoding utf-8

" Tolerate being called before plugin/semantic_ctags_difftastic.vim has run.
function! semantic_ctags_diff#difftastic#available() abort
  return executable(get(g:, 'semantic_ctags_diff_difft', 'difft'))
endfunction

" Scratch window setup shared by every difftastic view.
function! s:make_scratch(lines) abort
  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nobuflisted
  setlocal nowrap
  setlocal modifiable
  silent %delete _
  call setline(1, a:lines)
  setlocal nomodifiable
  setlocal filetype=
endfunction

function! s:open_scratch(title, lines, open_cmd) abort
  execute a:open_cmd
  call s:make_scratch(a:lines)
  execute 'file ' . fnameescape(a:title)
endfunction

" Open {lines} in the tab's tagged difftastic window, creating it if needed.
" Reuse matters for the Flog <CR> loop: without it every commit stacks a split.
function! s:open_or_reuse(title, lines, open_cmd) abort
  for l:win in range(1, winnr('$'))
    if getbufvar(winbufnr(l:win), 'semantic_ctags_diff_difftastic_view', 0)
      call win_gotoid(win_getid(l:win))
      call s:make_scratch(a:lines)
      return
    endif
  endfor

  execute a:open_cmd
  call s:make_scratch(a:lines)
  let b:semantic_ctags_diff_difftastic_view = 1
  " Name is cosmetic; a stale buffer from a closed tab may already hold it.
  try
    execute 'file ' . fnameescape(a:title)
  catch /^Vim\%((\a\+)\)\=:E95:/
  endtry
endfunction

" Run {cmd}, returning [stdout_lines, exit_code, stderr_lines].
function! s:run(cmd) abort
  let l:stdout_tmp = tempname()
  let l:stderr_tmp = tempname()
  call system(a:cmd . ' > ' . shellescape(l:stdout_tmp) . ' 2> ' . shellescape(l:stderr_tmp))
  let l:exit = v:shell_error
  let l:lines = filereadable(l:stdout_tmp) ? readfile(l:stdout_tmp) : []
  let l:errs = filereadable(l:stderr_tmp) ? readfile(l:stderr_tmp) : []
  if filereadable(l:stdout_tmp) | call delete(l:stdout_tmp) | endif
  if filereadable(l:stderr_tmp) | call delete(l:stderr_tmp) | endif
  return [l:lines, l:exit, l:errs]
endfunction

" Build: DFT_* env + `git -c diff.external=difft diff [revs] -- <path>`.
" difftastic gets old/new blobs straight from git, exactly like Fugitive's diff.
" {ref} may be a string (single rev) or a list of revs, each escaped separately.
function! semantic_ctags_diff#difftastic#command(ref, path, repo) abort
  let l:env = 'DFT_DISPLAY=' . shellescape(g:semantic_ctags_diff_difftastic_display)
        \ . ' DFT_COLOR=never'
        \ . ' DFT_SYNTAX_HIGHLIGHT=off'
        \ . ' DFT_CONTEXT=' . shellescape(string(g:semantic_ctags_diff_difftastic_context))
        \ . ' DFT_WIDTH=' . shellescape(string(&columns))

  let l:git = 'git -C ' . shellescape(a:repo)
        \ . ' -c ' . shellescape('diff.external=' . g:semantic_ctags_diff_difft)
        \ . ' --no-pager diff --ext-diff'

  let l:revs = type(a:ref) == v:t_list ? a:ref : (empty(a:ref) ? [] : [a:ref])
  for l:rev in l:revs
    let l:git .= ' ' . shellescape(l:rev)
  endfor

  let l:git .= ' -- ' . shellescape(a:path)
  return l:env . ' ' . l:git
endfunction

" Empty tree object id — the only valid left side for a root commit's diff.
function! s:empty_tree(repo) abort
  let l:out = systemlist('git -C ' . shellescape(a:repo) . ' hash-object -t tree /dev/null')
  if v:shell_error != 0 || empty(l:out)
    return '4b825dc642cb6eb9a060e54bf8d69288fbee4904'
  endif
  return trim(l:out[0])
endfunction

" Revs selecting exactly the change introduced by {commit}.
"
" Normal commit -> ['<sha>^!'], which git expands to parent..commit.
" A root commit has no parent, and `git diff <sha>^!` then silently degrades to
" `git diff <sha>` (commit vs working tree) instead of failing — so root commits
" must diff against the empty tree explicitly.
function! semantic_ctags_diff#difftastic#commit_revs(repo, commit) abort
  let l:parents = systemlist('git -C ' . shellescape(a:repo)
        \ . ' rev-list --parents -n 1 ' . shellescape(a:commit))
  if v:shell_error == 0 && !empty(l:parents) && len(split(l:parents[0])) <= 1
    return [s:empty_tree(a:repo), a:commit]
  endif
  return [a:commit . '^!']
endfunction

" Difftastic diff of a single {commit} restricted to a single {path}.
"
" Used by the Flog <CR> mapping: the graph is already filtered to one file, so
" the diff window must show that file only, never the rest of the commit.
"
" {opts} keys:
"   open_cmd  window command when no difftastic window exists (default 'botright new')
"   title     buffer name on creation (default 'difftastic://<path>')
"   subject   commit subject shown in the header
"   focus     1 to leave the cursor in the diff window (default 0)
function! semantic_ctags_diff#difftastic#commit_file(commit, path, repo, ...) abort
  if !semantic_ctags_diff#difftastic#available()
    echoerr 'semantic_ctags_diff: difftastic (' . g:semantic_ctags_diff_difft
          \ . ') not found in PATH. Install difftastic or set g:semantic_ctags_diff_difft'
    return 0
  endif

  let l:opts = a:0 ? a:1 : {}
  let l:open_cmd = get(l:opts, 'open_cmd', 'botright new')
  let l:revs = semantic_ctags_diff#difftastic#commit_revs(a:repo, a:commit)
  let l:cmd = semantic_ctags_diff#difftastic#command(l:revs, a:path, a:repo)

  call semantic_ctags_diff#_dbg('difftastic commit_file: ' . l:cmd)
  let [l:lines, l:exit, l:errs] = s:run(l:cmd)

  if l:exit != 0 && empty(l:lines)
    echoerr 'semantic_ctags_diff: difftastic diff failed: ' . join(l:errs, ' ')
    return 0
  endif

  let l:short = strpart(a:commit, 0, 10)
  if empty(filter(copy(l:lines), '!empty(trim(v:val))'))
    let l:lines = [a:path . ' is unchanged in ' . l:short . '.']
  endif

  let l:header = [
        \ 'Difftastic — ' . a:path,
        \ 'Commit:  ' . l:short . (empty(get(l:opts, 'subject', '')) ? '' : '  ' . l:opts.subject),
        \ 'Range:   ' . join(l:revs, ' '),
        \ 'Command: ' . l:cmd,
        \ '',
        \ ]

  let l:origin = win_getid()
  call s:open_or_reuse(get(l:opts, 'title', 'difftastic://' . a:path), l:header + l:lines, l:open_cmd)
  if !get(l:opts, 'focus', 0)
    call win_gotoid(l:origin)
  endif
  return 1
endfunction

function! semantic_ctags_diff#difftastic#diff(open_cmd, ref) abort
  if !semantic_ctags_diff#difftastic#available()
    echoerr 'semantic_ctags_diff: difftastic (' . g:semantic_ctags_diff_difft
          \ . ') not found in PATH. Install difftastic or set g:semantic_ctags_diff_difft'
    return
  endif

  try
    let l:repo = semantic_ctags_diff#repo_root()
    let l:rel = semantic_ctags_diff#current_git_relative_path()
  catch /.*/
    echoerr v:exception
    return
  endtry

  if empty(l:rel)
    echoerr 'semantic_ctags_diff: current buffer is not a file inside the Git worktree'
    return
  endif

  let l:ref = empty(a:ref) ? 'HEAD' : a:ref
  let l:cmd = semantic_ctags_diff#difftastic#command(l:ref, l:rel, l:repo)

  let [l:lines, l:exit, l:errs] = s:run(l:cmd)

  if l:exit != 0 && empty(l:lines)
    echoerr 'semantic_ctags_diff: difftastic diff failed: ' . join(l:errs, ' ')
    return
  endif

  if empty(filter(copy(l:lines), '!empty(trim(v:val))'))
    let l:lines = ['No differences for ' . l:rel . ' against ' . l:ref . '.']
  endif

  let l:header = [
        \ 'Difftastic diff',
        \ '===============',
        \ '',
        \ 'File: ' . l:rel,
        \ 'Ref:  ' . l:ref,
        \ 'Repo: ' . l:repo,
        \ 'Command: ' . l:cmd,
        \ '',
        \ ]

  call s:open_scratch('Difftastic ' . l:rel, l:header + l:lines, a:open_cmd)
endfunction
