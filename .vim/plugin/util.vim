vim9script

export def PrintError(msg: string)
    echohl ErrorMsg
    echomsg msg
    echohl None
enddef

export def InNewTab(): bool
    var bufs = tabpagebuflist()
    if getline(1) != '' || len(bufs) > 1
        return false
    endif

    var info = getbufinfo(bufs[0])[0]
    if info.changed || info.linecount > 1 || info.name != ''
        return false
    endif

    # TODO, true if tab with empty quickfix window
    return true
enddef

export def TabHasHelpWindow(): bool
    var tab_nr = tabpagenr()
    var tab_info = gettabinfo(tab_nr)[0]
    for win_id in tab_info.windows
        var buf_nr = winbufnr(win_id)
        if getbufvar(buf_nr, '&filetype') == 'help'
            return true
        endif
    endfor

    return false
enddef

export def ParseQArgs(cmd: string,
                      arg_str: string,
                      partial: bool = false): list<string>
    var arg_list = []
    var unquoted: string
    var double_str: string
    var state = 'skip'
    for char in arg_str
        if state == 'skip' && char != ' '
            # Start of new word - initialise word to empty string
            unquoted = ''
            state = 'word'
        elseif state == 'single_escape'
            if char == "'"
                # A double '' inside single quotes - write one ' and return to
                # parsing single quote contents
                unquoted ..= char
                state = 'single'
                continue
            else
                # End of single quote
                state = 'word'
            endif
        endif

        if state == 'word'
            # Parsing normal text, nothing quoted
            if char == '\'
                # Ignore any special meaning of next character
                state = 'escape'
            elseif char == "'"
                state = 'single'
            elseif char == '"'
                # Start of double quote - initialise double_str to empty string
                double_str = ''
                state = 'double'
            elseif char == ' '
                # End of word, add it to the argument list
                arg_list += [unquoted]
                state = 'skip'
            else
                unquoted ..= char
            endif
        elseif state == 'escape'
            unquoted ..= char
            state = 'word'
        elseif state == 'single'
            if char == "'"
                # May be end of single quotes or, if followed by another single
                # quote, a literal '
                state = 'single_escape'
            else
                unquoted ..= char
            endif
        elseif state == 'double'
            if char == '"'
                # Evaluate the string inside double quotes to expand escape
                # sequences supported by Vim. If more non-space characters
                # follow these are added to the same word (e.g. "xx"yy -> xxyy).
                unquoted ..= eval('"' .. double_str .. '"')
                state = 'word'
            elseif char == '\'
                # Leave escape sequences unaltered so they can be expanded later
                state = 'double_escape'
                double_str ..= char
            else
                double_str ..= char
            endif
        elseif state == 'double_escape'
            # Leave escape sequences unaltered so they can be expanded later
            double_str ..= char
            state = 'double'
        endif
    endfor

    # 'single_escape' means we finished on a single quote (ok)
    # 'double_escape' means we finished on a '\' inside a double quote (not ok)
    if state == 'word' || state == 'single_escape'
        arg_list += [unquoted]
    elseif partial && state == 'skip'
        # Empty word to aid completion
        arg_list += ['']
    elseif partial
        # Behave like all quotes are close and treat trailing slashes like
        # \\ was typed
        if state == 'escape'
            unquoted ..= '\'
        elseif state == 'double'
            unquoted ..= eval('"' .. double_str .. '"')
        elseif state == 'double_escape'
            unquoted ..= eval('"' .. double_str .. '\\"')
        endif

        arg_list += [unquoted]
    else
        var msg: string
        if state == 'escape'
            msg = 'Backslash at end of command: \'
        elseif state == 'single'
            msg = "Missing single quote: '"
        elseif state == 'double' || state == 'double_escape'
            msg = 'Missing double quote: "'
        endif

        throw cmd .. ': ' .. msg
    endif

    return arg_list
enddef

defcompile
