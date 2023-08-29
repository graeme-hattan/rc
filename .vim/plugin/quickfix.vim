vim9script

import './util.vim'

def QuickFixTab()
    for tab_info in gettabinfo()
        if tab_info.variables->has_key('quickfix_tab')
            execute 'tabnext ' .. tab_info.tabnr
            break
        endif
    endfor

    if !exists('t:quickfix_tab')
        if !util.InNewTab()
            tabnew
        endif

        t:quickfix_tab = 1
    endif

    botright copen
enddef

def HelpSplitWorkaround(is_help: bool)
    # TODO Ideally help would behave like any other window in the quickfix tab,
    # but easier to put it in vertical split for now
    if !is_help
        helpclose
    elseif !util.TabHasHelpWindow()
        wincmd k
        vertical help
        wincmd j
    endif
enddef

def OnQuickFixCmdPre()
    # If the current quickfix list is empty, replace it when adding a new one
    var qf = getqflist({'size': 0, 'nr': 0})
    if qf.size == 0
        if qf.nr > 1
            # If the current list is not the first, use :colder so that it is
            # replaced by the new one
            silent colder
        else
            # :colder just gives an error for the first list on the stack, in
            # this case we can just clear the whole stack
            setqflist([], 'f')
        endif
    endif
enddef

def OnQuickFixCmdPost()
    var qf = getqflist({'size': 0})
    if qf.size > 0
        QuickFixTab()

        # Workaround split for help - try to make it like another window
        HelpSplitWorkaround(expand('<amatch>') == 'helpgrep')
    endif
enddef

def ShiftQuickFixList(forward: bool, bang: string)
    try
        if forward
            cnewer
        else
            colder
        endif
    catch
        util.PrintError(v:exception)
        return
    endtry

    QuickFixTab()

    var qf = getqflist()
    if len(qf) > 0
        # The helpgrep command uses a special type in the quickfix entries
        HelpSplitWorkaround(qf[0].type == "\<C-A>")

        try
            execute 'cc' .. bang
        catch
            util.PrintError('x' .. v:exception)
        endtry
    endif
enddef

defcompile

augroup quickfix
    autocmd!
    autocmd QuickFixCmdPre [^l]* OnQuickFixCmdPre()
    autocmd QuickFixCmdPost [^l]* OnQuickFixCmdPost()
augroup END

#TODO -mods?
command -bang -bar Colder ShiftQuickFixList(false, <q-bang>)
command -bang -bar Cnewer ShiftQuickFixList(true, <q-bang>)

noremap [e :cprevious<CR>
noremap ]e :cnext<CR>
noremap [l :Colder<CR>
noremap ]l :Cnewer<CR>
