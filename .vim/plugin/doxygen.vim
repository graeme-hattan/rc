" TODO - script header, g:loaded_, cpoptions
" Limit  number of tokens parsed
const s:MAX_TOKENS = 128

" All C symbols for reference:
"   ~!#$%^&*()_+,./|\`-=<>?{}[]:";
"
" Keywords:
"   auto break case char const continue default do double else enum extern float
"   for goto if inline int long register restrict return short signed sizeof
"   static struct switch typedef union unsigned void volatile while

function s:PrintError(msg) abort
    echohl ErrorMsg
    echomsg a:msg
    echohl None
endfunction


function s:IsSymbol(token) abort
    return match(a:token, '\w') < 0
endfunction


function s:InList(list, item) abort
    return index(a:list, a:item) >= 0
endfunction


function s:InString(string, sub) abort
    return stridx(a:string, a:sub) >= 0
endfunction


function s:NewTokeniser(allowed_symbols, disallowed_keywords) abort
    let l:tokeniser = #{
        \ tokens_remaining: s:MAX_TOKENS,
        \ allowed_symbols: a:allowed_symbols,
        \ disallowed_keywords: a:disallowed_keywords,
        \ line_num: line('.'),
        \ tokens: [],
        \ allowed_symbols_stack: [],
        \ disallowed_keywords_stack: [],
    \ }

    function l:tokeniser.next() abort
        if l:self.tokens_remaining <= 0
            throw 'invalid'
        endif

        let l:sep_pattern =  '\(\s\+\|' .
                                \ '^[^[:space:][:alnum:]_]\zs\s*\|' .
                                \ '\ze[^[:space:][:alnum:]_]\)'
        while empty(l:self.tokens)
            if l:self.line_num > line('$')
                throw 'eof'
            endif

            let l:line_str = getline(l:self.line_num)
            let l:self.tokens = split(l:line_str, l:sep_pattern)
            let l:self.line_num += 1
        endwhile

        let l:token = remove(l:self.tokens, 0)
        let l:self.tokens_remaining -= 1
        if s:IsSymbol(l:token)
            if !s:InString(l:self.allowed_symbols, l:token)
                throw 'invalid'
            endif
        elseif s:InList(l:self.disallowed_keywords, l:token)
            throw 'invalid'
        endif

        return token
    endfunction

    function l:tokeniser.push_token(token) abort
        call insert(l:self.tokens, a:token)
        let l:self.tokens_remaining += 1
    endfunction

    function l:tokeniser.push_context(allowed_symbols, disallowed_keywords) abort
        let l:self.allowed_symbols_stack += [l:self.allowed_symbols]
        let l:self.disallowed_keywords_stack += [l:self.disallowed_keywords]

        let l:self.allowed_symbols = a:allowed_symbols
        let l:self.disallowed_keywords = a:disallowed_keywords
    endfunction

    function l:tokeniser.pop_context() abort
        let l:self.allowed_symbols = remove(l:self.allowed_symbols_stack, -1)
        let l:self.disallowed_keywords =
                                \ remove(l:self.disallowed_keywords_stack, -1)
    endfunction

    return tokeniser
endfunction


function s:SkipFunctionArrayDeclarators(tokeniser) abort
    let l:allowed_symbols = "~!$%^&*()+./|\'-=<>?[]:\";"
    let l:disallowed_keywords = [
        \ 'auto', 'break', 'case', 'continue', 'default', 'do', 'else',  'for',
        \ 'goto', 'if', 'inline', 'register', 'restrict', 'return', 'struct',
        \ 'union', 'while'
    \ ]
    call a:tokeniser.push_context(l:allowed_symbols, l:disallowed_keywords)

    " Opening bracket already parsed
    let l:open = 1
    while l:open > 0
        let l:token = a:tokeniser.next()
        if ']' ==# l:token
            let l:open -= 1

            " Parse next token to allow multidimensional arrays
            let l:token = a:tokeniser.next()
        endif

        if '[' ==# l:token
            let l:open += 1
        endif
    endwhile

    " Have read the token after the final closing ], push it back
    call a:tokeniser.push_token(token)
    call a:tokeniser.pop_context()
endfunction


" Not supported - attributes, functions returning a pointer to an array
function s:ParseFunctionProtoType() abort
    let l:allowed_symbols = '*(\'
    let l:disallowed_keywords = [
        \ 'auto', 'break', 'case', 'continue', 'default', 'do', 'else', 'for',
        \ 'goto', 'if', 'return', 'sizeof', 'switch', 'typedef'
    \ ]

    let l:tokeniser = s:NewTokeniser(l:allowed_symbols, l:disallowed_keywords)

    " Parse qualifiers/return type/name
    let l:have_name = 0
    let l:has_return_val = 1
    let l:token = v:null
    while l:token != '('
        let l:token = tokeniser.next()
        if l:token ==# 'void'
            " If a * follows it's a void pointer, otherwise it's a return value
            let l:token = tokeniser.next()
            if l:token != '*'
                let l:has_return_val = 0
            endif
        endif

        if l:token != '('
            let l:have_name = !s:IsSymbol(l:token)
        endif
    endwhile

    if !l:have_name
        throw 'invalid'
    endif

    " Parse parameter list
    " TODO, in/out
    let l:tokeniser.allowed_symbols = '*[,)\'
    let l:disallowed_keywords += ['extern', 'static']
    let l:last_word = v:null
    let l:params = []
    while l:token != ')'
        let l:token = l:tokeniser.next()
        if !s:IsSymbol(l:token)
            let l:last_word = l:token
        elseif '[' ==# l:token
            call s:SkipFunctionArrayDeclarators(l:tokeniser)
        elseif ',' ==# l:token
            if l:last_word is v:null
                throw 'invalid'
            else
                let l:params += [l:last_word]
                let l:last_word = v:null
            endif
        endif
    endwhile

    if l:last_word is v:null
        throw 'invalid'
    elseif 'void' != l:last_word
        let l:params += [l:last_word]
    endif

    " Ensure either ; for declaration or { for definition
    let l:tokeniser.allowed_symbols = ';{'
    let l:token = l:tokeniser.next()
    if !s:InString(l:tokeniser.allowed_symbols, l:token)
        throw 'invalid'
    endif

    return #{has_return_val: l:has_return_val, params: l:params}
endfunction


function s:MatchBackForward(pattern) abort
    let l:buf_num = bufnr()
    let l:cur_line_num = line('.')

    " Search backward from cursor position
    let l:lines = getbufline(l:buf_num, 1, l:cur_line_num)
    let l:lines = reverse(l:lines)
    let l:match_idx = match(l:lines, a:pattern)
    if l:match_idx >= 0
        let l:match_idx = l:cur_line_num - l:match_idx - 1
    else
        " Search forward from cursor position
        let l:lines = getbufline(l:buf_num, l:cur_line_num + 1, '$')
        let l:match_idx = match(l:lines, a:pattern)
        if l:match_idx >= 0
            let l:match_idx += l:cur_line_num
        endif
    endif

    " Note this is a list index, not a line number
    return l:match_idx
endfunction


function s:FindDuplicateParam(param) abort
    let l:duplicate = v:null
    let l:pattern = '^\s*\* @param\s\+' .. a:param .. '\s'

    " Search current buffer first
    let l:buf_num = bufnr()
    let l:match_idx = s:MatchBackForward(l:pattern)

    if l:match_idx < 0
        " Try other buffers
        let l:keys = #{buflisted: 1}
        for buf_info in getbufinfo(l:keys)
            if l:buf_num != buf_info.bufnr
                call bufload(l:buf_num)
                let l:lines = getbufline(buf_info.bufnr, 1, '$')
                let l:match_idx = match(l:lines, l:pattern)
                if l:match_idx >= 0
                    let l:buf_num = buf_info.bufnr
                    break
                endif
            endif
        endfor
    endif

    if l:match_idx >= 0
        let l:match_line_num = l:match_idx + 1
        let l:duplicate = getbufline(l:buf_num, l:match_line_num)
        let l:loop = 1
        while loop
            let l:match_line_num += 1
            let l:check_list = getbufline(l:buf_num, l:match_line_num)
            if match(l:check_list, '^\s*\*\s*[^/@[:space:]]') >= 0
                let l:duplicate += l:check_list
            else
                let l:loop = 0
            endif
        endwhile
    endif

    return duplicate
endfunction


function s:AddFunctionComment(has_return_val, params) abort
    let l:doxygen = ['/**', ' * @brief']

    if len(a:params) > 0
        let l:doxygen += [' *']
        for l:param in a:params
            let l:duplicate = s:FindDuplicateParam(l:param)
            if l:duplicate is v:null
                let l:doxygen += [' * @param ' .. l:param]
            else
                let l:doxygen += l:duplicate
            endif
        endfor
    endif

    if a:has_return_val
        let l:doxygen += [' *', ' * @return']
    endif

    " TODO, allow command on line above
    let l:doxygen += [' */']
    call append(line('.') - 1, l:doxygen)
endfunction


function DoxygenAddComment() abort
    try
        let l:proto_data = s:ParseFunctionProtoType()
    catch /\(invalid\|eof\)/
        call s:PrintError('Dox: no function prototype found')
        return
    endtry

    call s:AddFunctionComment(l:proto_data.has_return_val, l:proto_data.params)
endfunction


function DoxygenWarnings(...) abort
    " Write all buffers
    wall

    if !executable('doxygen')
        call s:PrintError("Cannot find 'doxygen' executable")
        return
    endif

    " TODO, very targeted... can parse from an existing Doxyfile
    let l:doxyfile =<< trim END
        EXTRACT_STATIC = YES
        QUIET = YES
        WARN_NO_PARAMDOC = YES
        RECURSIVE = YES
        GENERATE_HTML = NO
        GENERATE_LATEX = NO
    END

    " Parameters specify input paths. If none are given, use the directory of
    " the current file
    if len(a:000) > 0
        let l:input_paths = join(a:000)
    else
        let l:input_paths = expand('%:p:h')
    endif

    let l:doxyfile += ['INPUT = ' .. l:input_paths]
    let l:warnings = systemlist('doxygen -', l:doxyfile)

    " No output formats is deliberate, remove the message
    if get(l:warnings, 0) =~ '^warning: No output formats selected!'
        call remove(l:warnings, 0)
    endif

    if len(l:warnings) > 0
        cgetexpr l:warnings
        botright copen
    else
        echomsg 'No Doxygen warnings found'
    endif
endfunction


command -bar Dox call DoxygenAddComment()
command -nargs=* -complete=file -bar Dow call DoxygenWarnings(<f-args>)
