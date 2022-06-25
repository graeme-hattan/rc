function s:PrintError(msg) abort
    echohl ErrorMsg
    echomsg a:msg
    echohl None
endfunction

function s:FindProjectFiles() abort
    " Start in the directory of the current file
    let l:search_path = expand('%:p:h')
    let l:ewp_path = ''
    let l:argvars_path = ''

    " Search finishes when we can't remove any more from the path
    let l:last_dir = ''
    while (l:last_dir != l:search_path) &&
                \ (l:ewp_path is '' || l:argvars_path is '')
        if l:ewp_path is ''
            let l:matches = globpath(l:search_path, '*.ewp', 0, 1)
            if len(l:matches) > 0
                let l:ewp_path = l:matches[0]
            endif
        endif

        if l:argvars_path is ''
            let l:matches = globpath(l:search_path, '*.custom_argvars', 0, 1)
            if len(l:matches) > 0
                let l:argvars_path = l:matches[0]
            endif
        endif

        let l:last_dir = l:search_path

        " Remove the last directory in the path
        let l:search_path = fnamemodify(l:search_path, ':h')
    endwhile

    return #{ewp_path: l:ewp_path, argvars_path: l:argvars_path}
endfunction


function IarBuild() abort
    if !executable('IarBuild')
        call s:PrintError("Cannot find 'IarBuild' executable")
        return
    endif

    let l:project_files = s:FindProjectFiles()
    if l:project_files.ewp_path is ''
        call s:PrintError('Could not find a .ewp file')
        return
    endif

    let l:cmd = '!IarBuild ' .. project_files.ewp_path .. ' -build Debug'
    if l:project_files.argvars_path is ''
        let l:cmd ..= '  -varfile ' .. l:project_files.argvars_path
    endif

    " Using ! along with shellpipe allows us to see the build progress, if
    " supported by the OS
    let l:temp_path = tempname()
    let l:cmd ..= ' ' .. &shellpipe .. ' ' .. l:temp_path
    execute l:cmd

    let l:iar_output = readfile(l:temp_path)
    cgetexpr l:iar_output
    botright cwindow
    call delete(l:temp_path)
endfunction


command -bar Ib call IarBuild()
