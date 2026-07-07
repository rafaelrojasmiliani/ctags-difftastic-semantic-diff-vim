" autoload/semantic_ctags_diff/difftastic.vim
" Difftastic (structural diff) ported into Vim: a Fugitive-style file diff that
" uses `difft` as git's external diff, rendered in a scratch buffer.
"
" No ctags, no Python — this is a pure Vim + git + difftastic integration and is
" independent of the semantic-branch-diff submodule.

scriptencoding utf-8

function! semantic_ctags_diff#difftastic#available() abort
  return executable(g:semantic_ctags_diff_difft)
endfunction

function! s:open_scratch(title, lines, open_cmd) abort
  execute a:open_cmd
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
  execute 'file ' . fnameescape(a:title)
endfunction

" Build: DFT_* env + `git -c diff.external=difft diff [ref] -- <path>`.
" difftastic gets old/new blobs straight from git, exactly like Fugitive's diff.
function! semantic_ctags_diff#difftastic#command(ref, path, repo) abort
  let l:env = 'DFT_DISPLAY=' . shellescape(g:semantic_ctags_diff_difftastic_display)
        \ . ' DFT_COLOR=never'
        \ . ' DFT_SYNTAX_HIGHLIGHT=off'
        \ . ' DFT_CONTEXT=' . shellescape(string(g:semantic_ctags_diff_difftastic_context))
        \ . ' DFT_WIDTH=' . shellescape(string(&columns))

  let l:git = 'git -C ' . shellescape(a:repo)
        \ . ' -c ' . shellescape('diff.external=' . g:semantic_ctags_diff_difft)
        \ . ' --no-pager diff --ext-diff'

  if !empty(a:ref)
    let l:git .= ' ' . shellescape(a:ref)
  endif

  let l:git .= ' -- ' . shellescape(a:path)
  return l:env . ' ' . l:git
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

  let l:stdout_tmp = tempname()
  let l:stderr_tmp = tempname()
  call system(l:cmd . ' > ' . shellescape(l:stdout_tmp) . ' 2> ' . shellescape(l:stderr_tmp))
  let l:exit = v:shell_error
  let l:lines = filereadable(l:stdout_tmp) ? readfile(l:stdout_tmp) : []
  let l:errs = filereadable(l:stderr_tmp) ? readfile(l:stderr_tmp) : []
  if filereadable(l:stdout_tmp) | call delete(l:stdout_tmp) | endif
  if filereadable(l:stderr_tmp) | call delete(l:stderr_tmp) | endif

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
