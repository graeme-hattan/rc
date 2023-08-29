function s:PrintError(msg) abort
    echohl ErrorMsg
    echomsg a:msg
    echohl None
endfunction


function s:CygwinToWindowsPath(path) abort
    " Trim the \n from the end
    return system('cygpath -aw -- ' .. a:path)[:-2]
endfunction


function s:FindProjectFiles(paths) abort
    " If no .ewp path given, start in the directory of the current file. If the
    " .ewp file is given, start in its directory
    if a:paths.ewp is ''
        let l:search_path = expand('%:p:h')
    else
        let l:search_path = fnamemodify(a:paths.ewp, ':p:h')
    endif

    " Search finishes when we can't remove any more from the path
    let l:last_dir = ''
    while (l:last_dir != l:search_path) &&
                \ (a:paths.ewp is '' || a:paths.argvars is '')
        if a:paths.ewp is ''
            let l:matches = globpath(l:search_path, '*.ewp', 1, 1)
            if len(l:matches) > 0
                let a:paths.ewp = l:matches[0]
            endif
        endif

        if a:paths.argvars is ''
            let l:matches = globpath(l:search_path, '*.custom_argvars', 1, 1)
            if len(l:matches) > 0
                let a:paths.argvars = l:matches[0]
            endif
        endif

        let l:last_dir = l:search_path

        " Remove the last directory in the path
        let l:search_path = fnamemodify(l:search_path, ':h')
    endwhile

    if has('win32unix')
        " Path conversion for Cygwin
        if a:paths.ewp isnot ''
            let a:paths.ewp = s:CygwinToWindowsPath(a:paths.ewp)
        endif

        if a:paths.argvars isnot ''
            let a:paths.argvars = s:CygwinToWindowsPath(a:paths.argvars)
        endif
    endif

    let a:paths.ewp = fnameescape(a:paths.ewp)
    let a:paths.argvars = fnameescape(a:paths.argvars)
endfunction


function IarBuild(ewp_path = '') abort
    " Write all buffers
    wall

    if !executable('IarBuild')
        call s:PrintError("Cannot find 'IarBuild' executable")
        return
    endif

    let l:paths = #{ewp: a:ewp_path, argvars: ''}
    call s:FindProjectFiles(l:paths)
    if l:paths.ewp is ''
        call s:PrintError('Could not find a .ewp file')
        return
    endif

    let l:cmd = '!IarBuild ' .. paths.ewp .. ' -build Debug'
    if l:paths.argvars isnot ''
        let l:cmd ..= ' -varfile ' .. l:paths.argvars
    endif

    " Using ! along with shellpipe allows us to see the build progress, if
    " supported by the OS
    let l:temp_path = tempname()
    let l:cmd ..= ' ' .. &shellpipe .. ' ' .. l:temp_path
    execute l:cmd

    let l:iar_output = readfile(l:temp_path)
    call delete(l:temp_path)

    let l:qf_data = []
    for l:line in l:iar_output
        let l:matches = matchlist(
                    \ l:line,
                    \ '\C\v(.*)\((\d+)\) : %(Fatal |)(\u)\l+\[\w+\]: (.*)$')

        " List will contain 10 entries if there was a match. l:matches[0] is the
        " file matched string. l:matches[1:9] have submatches \1 - \9
        if len(l:matches) >= 5
            let [l:filename, l:lnum, l:type, l:text] = l:matches[1:4]
            let l:text = substitute(l:text, '\C (declared [^)]*)', '', '')
            let l:text = substitute(l:text, '\C__interwork ', '', 'g')
            let l:text = substitute(l:text, '\C__softfp ', '', 'g')
            let l:qf_data += [#{
                \ filename: fnamemodify(l:filename, ':.'),
                \ lnum: l:lnum,
                \ type: l:type,
                \ text: l:text
            \ }]
        endif
    endfor

    doautocmd QuickFixCmdPre cgetexpr
    call setqflist(l:qf_data)
    doautocmd QuickFixCmdPost cgetexpr
endfunction


command -nargs=? -complete=file -bar Ib call IarBuild(<f-args>)
