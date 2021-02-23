if exists('g:loaded_pretty_search')
  finish
endif

let g:loaded_pretty_search = 1

let s:search_result_file = tempname()
let s:search_result_list = []
let s:search_result_cur_line = 0
let s:search_result_job = job_start(":")
let s:search_result_word = ''
let s:search_path = getcwd()
let s:rg_path = 'rg'

function! VpsResultStatusLine()
    if job_status(s:search_result_job) == 'run'
        return '[Search ' . s:search_result_word . '...]'
    else
        return ''
    endif
endfunction

function! s:SearchResultCurLineCheck(line)
    if a:line > len(s:search_result_list)
        return [0, []]
    endif
    let words = split(s:search_result_list[a:line - 1], ':')
    if len(words) <= 3 || words[1] < 1 || words[2] < 1
        return [0, []
    endif
    if filereadable(words[0])
        return [1, words]
    endif
    return [0, []]
endfunction

function! s:GotoResultLine(words)
    execute 'e ' . a:words[0]
    execute a:words[1]
    execute 'normal 0' . (a:words[2] - 1) . 'l'
endfunction

function! s:GotoResultFileCur()
    let s:search_result_list = getline(1, '$')
    let cur_pos = getpos('.')
    let s:search_result_cur_line = cur_pos[1]
    let check_result = s:SearchResultCurLineCheck(s:search_result_cur_line)
    if ! check_result[0]
        return
    endif
    call s:GotoResultLine(check_result[1])
endfunction

function! s:GotoResultFileNext()
    let old_line = s:search_result_cur_line
    if s:search_result_cur_line >= len(s:search_result_list)
        echo 'No next item !!!'
        return
    endif
    let s:search_result_cur_line = s:search_result_cur_line + 1
    let check_result = s:SearchResultCurLineCheck(s:search_result_cur_line)
    while ! check_result[0]
        if s:search_result_cur_line >= len(s:search_result_list)
            let s:search_result_cur_line = old_line
            echo 'No next item !!!'
            return
        endif
        let s:search_result_cur_line = s:search_result_cur_line + 1
        let check_result = s:SearchResultCurLineCheck(s:search_result_cur_line)
    endwhile

    call s:GotoResultLine(check_result[1])
endfunction

function! s:GotoResultFilePrev()
    let old_line = s:search_result_cur_line
    if s:search_result_cur_line <= 1
        echo 'No prev item !!!'
        return
    endif
    let s:search_result_cur_line = s:search_result_cur_line - 1
    let check_result = s:SearchResultCurLineCheck(s:search_result_cur_line)
    while ! check_result[0]
        if s:search_result_cur_line <= 1
            let s:search_result_cur_line = old_line
            echo 'No prev item !!!'
            return
        endif
        let s:search_result_cur_line = s:search_result_cur_line - 1
        let check_result = s:SearchResultCurLineCheck(s:search_result_cur_line)
    endwhile

    call s:GotoResultLine(check_result[1])
endfunction

function! RgAsyncFinishHandler(channel)
    let s:search_result_curr_line = 0

    if job_status(s:search_result_job) == "run"
        return
    endif

    execute 'view ' . s:search_result_file
    setlocal autoread
    execute "normal /\\%$/;?^>>?2\<cr>"

    let s:search_result_list = getline(1, '$')
    let cur_pos = getcurpos()
    let s:search_result_cur_line = cur_pos[1]
endfunction

function! s:RgAsyncRun(word, path)
    if a:word[0] == "'" || a:word[0] == '"'
        let cmd = s:rg_path . ' -L --no-ignore --column --line-number -H ' . a:word . ' ' . a:path . ' | dos2unix >>' . s:search_result_file
    else
        let cmd = s:rg_path . ' -L --no-ignore --column --line-number -H "\\b' . a:word . '\\b" ' . a:path . ' | dos2unix >>' . s:search_result_file
    endif
    if job_status(s:search_result_job) == "run"
        call job_stop(s:search_result_job)
    endif

    let s:search_result_word = a:word
    let s:search_result_job = job_start(['bash', '-c', cmd], {
        \'close_cb': 'RgAsyncFinishHandler'
        \})
endfunction

"word:
"    str
"    str path
function! s:RgWithLineNumber(word, path)
    if !executable("rg")
        echom "there is no rg!"
        return
    endif

    let title = ['------------------------------',
                \ '>> ' . a:word,
                \ '------------------------------']
    if !filereadable(s:search_result_file)
        call writefile(title, s:search_result_file, 's')
    else
        call writefile([''] + title, s:search_result_file, 'as')
    endif

    if a:path != ''
        call s:RgAsyncRun(a:word, a:path)
    elseif s:search_path != ''
        call s:RgAsyncRun(a:word, s:search_path)
    else
        echo 'Search path is null!!'
    endif
endfunction

function! s:ChangeSearchPath(path)
    let tmp_path = split(a:path)

    if len(tmp_path) > 0
        let s:search_path = tmp_path[0]
        echo 'Search path change to : ' . s:search_path
    else
        echo 'Current search path is : ' . s:search_path
    endif
endfunction

function! s:MapLeaderRecursiveSearch()
    call s:RgWithLineNumber(expand('<cword>'), '')
endfunction

function! s:MapLeaderCurrentFileSearch()
    call s:RgWithLineNumber(expand('<cword>'), expand('%'))
endfunction

function! s:MapLeaderStopSearch()
    if job_status(s:search_result_job) == "run"
        call job_stop(s:search_result_job)
    endif
endfunction

function! s:MapLeaderShowResult()
    if filereadable(s:search_result_file)
        execute 'e ' . s:search_result_file
    endif
endfunction

function! s:Autocmd_BufWinEnter()
    if expand("%") ==# s:search_result_file
        if s:search_result_cur_line != 0
            call setpos(".", [0, s:search_result_cur_line, 0, 0])
        endif
        nnoremap <buffer> <cr> :call <sid>GotoResultFileCur()<cr>
    endif
endfunction

function! s:Autocmd_VimLeave()
    if filereadable(s:search_result_file)
        call delete(s:search_result_file)
    endif
endfunction

augroup reg_search_autocmd
    autocmd!
    autocmd BufWinEnter * call <sid>Autocmd_BufWinEnter()
    autocmd VimLeave * call <sid>Autocmd_VimLeave()
augroup END

let g:vps_recursive_search_map = get( g:, 'vps_recursive_search_map', '<leader>s' )
let g:vps_current_file_search_map = get( g:, 'vps_current_file_search_map', '<leader>c' )
let g:vps_stop_search_map = get( g:, 'vps_stop_search_map', '<leader>S' )
let g:vps_show_search_result_map = get( g:, 'vps_show_search_result_map', '<leader>r' )
let g:vps_show_prev_result_map = get( g:, 'vps_show_prev_result_map', '[r' )
let g:vps_show_next_result_map = get( g:, 'vps_show_next_result_map', ']r' )

execute "nnoremap " . g:vps_recursive_search_map . " :call <sid>MapLeaderRecursiveSearch()<cr>"
execute "nnoremap " . g:vps_current_file_search_map . " :call <sid>MapLeaderCurrentFileSearch()<cr>"
execute "nnoremap " . g:vps_stop_search_map . " :call <sid>MapLeaderStopSearch()<cr>"
execute "nnoremap " . g:vps_show_search_result_map . " :call <sid>MapLeaderShowResult()<cr>"
execute "nnoremap " . g:vps_show_next_result_map . " :call <sid>GotoResultFileNext()<cr>"
execute "nnoremap " . g:vps_show_prev_result_map . " :call <sid>GotoResultFilePrev()<cr>"

command! -nargs=? -complete=dir VpsPath call s:ChangeSearchPath(<q-args>)
command! -nargs=1 VpsRg call s:RgWithLineNumber(<q-args>, "")

