vim9script

import './util.vim'

def CountMatchingChars(str1: string, str2: string): number
    var idx: number = 0
    while (str1[idx] isnot '') && (str1[idx] == str2[idx])
        idx += 1
    endwhile

    return idx
enddef

def Strcmp(str1: string, str2: string): number
    if str1 < str2
        return -1
    elseif str1 == str2
        return 0
    else
        return 1
    endif
enddef

def TagSearch(str: string, is_regexp: bool = false): list<dict<any>>
    var expr = str
    if !is_regexp
        # This method ensures a binary search in as may cases as possible. The ^
        # must be at the start of the string. Binary search is also disabled if
        # there is a backslash after the ^.
        # TODO report this as a bug
        expr = '^' .. escape(str, '$*.[\~') .. '$'

        # Use a "very nomagic" pattern with anchors and escape backslashes
        #str = '\V\^' .. escape(str, '\') .. '\$'
    endif

    return taglist(expr)
enddef

def TagCompare(tag1: dict<any>, tag2: dict<any>): number
    var diff: number = tag2._rank - tag1._rank

    if 0 == diff
        # Closer proximity takes priority. Proximity values for matching paths
        # are zero, but they already rank higher than non-matching
        diff = tag2._prox_rank - tag1._prox_rank
    endif

    if 0 == diff
        # Alphabetical priority of kind (if available) - function (f) before
        # prototype (p)
        var kind1 = tag1->get('kind', 'z')
        var kind2 = tag2->get('kind', 'z')
        diff = Strcmp(kind1, kind2)
    endif

    if 0 == diff
        # Alphabetical priority of filename
        diff = Strcmp(tag1.filename, tag2.filename)
    endif

    # Return -1 for before, 0 for same and 1 for after
    if diff < 0
        diff = -1
    elseif diff > 0
        diff = 1
    endif

    return diff
enddef

def g:TagFunc(pattern: string, flags: string, info: dict<any>): any
    var is_regexp = stridx(flags, 'r') >= 0
    var tag_list = TagSearch(pattern, is_regexp)

    var buf_path = info->get('buf_ffname', '')
    if buf_path != ''
        buf_path = fnamemodify(info.buf_ffname, ':p')
    endif

    # Forward declarations - should make the loop faster?
    var rank: number
    var start_pos: number
    var end_pos: number
    var cmd: string

    for tag_data in tag_list
        rank = 0

        if is_regexp
            [_, start_pos, end_pos] = matchstrpos(tag_data.name, pattern)
            if 0 == start_pos
                rank += 8
            endif

            if len(tag_data.name) == end_pos
                rank += 4
            endif
        endif

        if buf_path == ''
            # Static tags rank lower if no file comparison possible
            rank += tag_data.static ? 0 : 1
            tag_data._prox_rank = 0
        else
            var tag_path = fnamemodify(tag_data.filename, ':p')
            if buf_path == tag_path
                rank += 2

                # Static tags rank higher for the same file
                rank += tag_data.static ? 1 : 0
                tag_data._prox_rank = 0
            else
                # Static tags rank lower for a different files
                rank += tag_data.static ? 0 : 1
                tag_data._prox_rank = CountMatchingChars(buf_path, tag_path)
            endif
        endif

        tag_data._rank = rank

        # Search backward for function definitions to avoid matching a prototype
        # in cases where the parameter list spans multiple lines.  In those
        # cases the prototype and the definition can have the same search
        # pattern. This works around this issue in most cases.
        if tag_data->get('kind', '') == 'f'
            cmd = tag_data.cmd
            if cmd[0] == '/' && cmd[-1] == '/'
                tag_data.cmd = '?' .. cmd[1 : -2] .. '?'
            endif
        endif

        # Workaround for Vim bug where the static entry is always zero after
        # processing the tagfunc - restore the original empty file attribute
        # that is used in tag file and Vim will set the static entry value to
        # one
        # TODO report this
        if tag_data.static
            tag_data.file = ''
        endif
    endfor

    # Note: tag entries with non-string values (_rank and _prox_rank) get
    # automatically removed.
    return tag_list->sort(TagCompare)
enddef

def GuessPath(part_path: string): string
    # Just the file part for a tag search
    var file_name = fnamemodify(part_path, ':t')

    # Filter non-filename tags and tags where file matches, but a partial
    # directory component doesn't
    var part_idx = -strchars(part_path)
    var FilterExpr = (idx, val) =>
                        (val->get('kind', '') == 'F') &&
                        (val.filename[part_idx : ] == part_path)

    var tag_list = TagSearch(file_name)->filter(FilterExpr)

    var path = part_path
    if !empty(tag_list)
        var cur_buf_path = expand('%:p')

        # Find the result with the closest proximity to the current buffer path
        path = fnamemodify(tag_list[0].filename, ':p')
        var match_count = CountMatchingChars(cur_buf_path, path)
        for tag_data in tag_list[1 : ]
            # Note, this call can be very slow on long lists
            var check_path = fnamemodify(tag_data.filename, ':p')
            var check_count = CountMatchingChars(cur_buf_path, check_path)

            if check_count > match_count
                match_count = check_count
                path = check_path
            endif
        endfor
    endif

    return path
enddef

function g:ToggleHeaderSource()
    let l:base = expand('%:t:r')
    let l:ext = expand('%:e')
    if l:ext == 'h'
        execute 'tag' l:base .. '.c'
    else
        execute 'tag' l:base .. '.h'
    end
endfunction

function g:CscopeCall(...)
    call setqflist([])
    let l:tagfunc_save = &tagfunc
    set tagfunc=
    try
        execute join(a:000)
    catch
        var msg = substitute(v:exception, '\C^Vim([^)]*):', '', '')
        util.PrintError(msg)
    endtry

    let &tagfunc = l:tagfunc_save
    botright cwindow
endfunction

defcompile

set tags=./tags;
set tagcase=match
set tagfunc=g:TagFunc

# Trick to make all commands depending on path work by re-routing the path
# search to a tag lookup which guesses the path
#
# gf, :find, :sfind, :tabfind, CTRL-W_f, CTRL-R CTRL-P, CTRL-X CTRL-I, CTRL-X
# CTRL-D, CTRL-X CTRL-F (Vim TODO), <cfile>
# "[i", "]I", "[d", etc..???
#
# TODO, automatically set path for file_in_path completion?
#
# TODO, apply current include expr
set includeexpr=s:GuessPath(v:fname)

set nocscopetag
set cscopequickfix=s-,c-,d-,t-,e-,i-,a-

if executable('cscope')
    var cscope_out = findfile('cscope.out', '.;')
    if cscope_out != ''
        execute 'cscope add' cscope_out
    endif
endif

# Workaround for bug that executes the tagfunc when cscope is used
# TODO report this
command -nargs=+ -complete=command C g:CscopeCall(<f-args>)

command -nargs=+ Cfind g:CscopeCall('cscope', 'find', <f-args>)

command -nargs=? T
    \ execute '!' .. g:vim_home .. '/.vim/shell/gen_tags.bash ' .. <q-args>

# TODO :Tf to open a file tag

#map gf :call g:GotoFile()<CR>
noremap gh :call g:ToggleHeaderSource()<CR>
#noremap <C-}> :Cfind c <C-R><C-W><CR>
