vim9script

import './util.vim'

const ACTION_ARGS = {
    'def': '-d',
    'ref': '-r',
    'grep': '--grep',
    'path': '--path'
}

def GblCmdCompletion(lead: string,
                     cmd_line: string,
                     byte_idx: number): list<string>
    var char_idx = cmd_line->charidx(byte_idx)
    var part_cmd = cmd_line[0 : char_idx]
    var arg_list = util.ParseQArgs('', part_cmd, true)

    var compl_arg = len(arg_list)
    var matches = []
    if compl_arg == 2
        var compl_pattern = '^\V' .. lead
        var FilterFunc = (idx, val) => val =~ compl_pattern
        matches = ACTION_ARGS->keys()->filter(FilterFunc)
    elseif compl_arg == 3
         matches = g:GlobalRunComplete(lead, arg_list[1] == 'path')
    endif

    return matches
enddef

def GlobalRun(action: string, pattern: any = v:none): list<string>
    var cmd = ['global', '--result=grep', '--path-style=absolute']

    var full_path = expand('%:p')
    if full_path != ''
        cmd += ['--nearness=' .. full_path]
    endif

    if ACTION_ARGS->has_key(action)
        cmd += [ACTION_ARGS[action]]
    else
        throw "global: Invalid action: '" .. action .. "'"
    endif

    if type(pattern) == v:t_none
        cmd += ['--literal', expand('<cword>')]
    elseif pattern[0] == '/'
        # Global has a bug where regexps need to have a regexp character for
        # regexp searches to use partial matching. Otherwise the match will be
        # the same as a literal search, where full string matching is used. A
        # '.*' is added to ensure the partial regexp matching is enabled and
        # removes inconsistencies.
        #
        # As an example consider a database containing the tags 'xxx', 'yyxxx'
        # and 'xxxyy'. The pattern 'x.x' will match all of them (partial
        # matching) since '.' is a special regexp character, but 'xxx' will only
        # match 'xxx' as would be expected for '^xxx$'. Changing 'xxx' to
        # 'xxx.*' will match all three tags (including 'yyxxx'). The '.*' has no
        # further effect once the partial matching is enabled.
        #
        # Note that appending '.*' to a pattern like 'xxx$' appears to be
        # harmless ('xxx$.*' is equivalent to 'xxx$'). On the other hand, if the
        # '.*' is prepended there is a subtle side effect which is only
        # noticeable for large databases. The search for a pattern like '.*^xxx'
        # is much slower than for '^xxx'. Probably because for '^xxx' triggers a
        # binary search for the first part of the match, which is disabled by
        # prepending the '.*'.
        cmd += ['--regexp', pattern[1 :] .. '.*']
    else
        cmd += ['--literal', pattern]
    endif

    # Escape all arguments and create a command string
    var MapShellEscape = (idx, val) => shellescape(val)
    cmd = cmd->map(MapShellEscape)

    # Run the command and return the output
    var matches = systemlist(cmd->join(' '))

    if v:shell_error != 0
        if len(matches) == 0
            throw 'global: returned error ' .. v:shell_error
        else
            throw matches[-1]
        endif
    endif

    return matches
enddef

def g:GlobalRunComplete(lead: string, path: bool = false): list<string>
    var cmd = 'global --completion '
    if path
        cmd ..= '--path '
    endif

    var matches = systemlist(cmd .. shellescape(lead))

    return v:shell_error == 0 ? matches : []
enddef

def g:GblCmdFunc(bang: string, q_args: string)
    var action: string
    var matches: list<string>
    try
        var arg_list = util.ParseQArgs('global', q_args)
        action = arg_list->get(0, 'ref')
        var pattern = arg_list->get(1, v:none)
        matches = GlobalRun(action, pattern)
    catch /^global: /
        util.PrintError(v:exception)
        return
    endtry

    if len(matches) == 0
        const words = {
            'def': 'definitions',
            'ref': 'references',
            'grep': 'matches',
            'path': 'paths'
        }

        util.PrintError('global: No ' .. words[action] .. ' found')
        return
    endif

    var errorformat_save = &errorformat
    try
        &errorformat = '%f:%l:%m'
        if bang == '!'
            cgetexpr matches
        else
            cexpr matches
        endif
    finally
        &errorformat = errorformat_save
    endtry
enddef

defcompile

command -nargs=* -bang -complete=customlist,GblCmdCompletion
    \ Gbl g:GblCmdFunc(<q-bang>, <q-args>)

# TODO, visual mode key binding - https://stackoverflow.com/questions/1533565/how-to-get-visually-selected-text-in-vimscript
noremap <Leader>] :execute 'Gbl! ref ' .. expand('<cword>')<CR>
