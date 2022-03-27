" splleing msitake

set termguicolors
hi clear

function EnableTerminalUndercurl()
    " Non-standard escapes for undercurl, only works if they are supported!
    let &t_Cs = "\e[4:3m"
    let &t_Ce = "\e[4:0m"

    " Enable terminal undercurl in all cases where the GUI would have it.
    let updates = []
    for group in hlget()
        " Does the GUI use an undercurl for this highlight group?
        if group->get('gui', {})->get('undercurl', 0)
            " Does the highlight group have ctermbg set? If so it needs to be
			" unset.
            if has_key(group, 'ctermbg')
                unlet group.ctermbg

                " Not enough just to update the highlight group after removing
                " attributes, it needs to be explicitly cleared first.
                let cleared = {'name': group.name, 'cleared': v:true}
                eval updates->add(cleared)
            endif

            let group['cterm'] = {'undercurl': v:true}
            eval updates->add(group)
        endif
    endfor

    call hlset(updates)
endfunction

call EnableTerminalUndercurl()

autocmd ColorScheme * call EnableTerminalUndercurl()
