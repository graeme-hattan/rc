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

function PrintError(msg) abort
    echohl ErrorMsg
    echomsg a:msg
    echohl None
endfunction


function IsSymbol(token) abort
    return match(a:token, '\w') < 0
endfunction


function InList(list, item) abort
    return index(a:list, a:item) >= 0
endfunction


function InString(string, sub) abort
    return stridx(a:string, a:sub) >= 0
endfunction


function NewTokeniser(allowed_symbols, disallowed_keywords) abort
    let l:tokeniser = #{
        \ tokens_remaining: s:MAX_TOKENS,
        \ allowed_symbols: a:allowed_symbols,
        \ disallowed_keywords: a:disallowed_keywords,
        \ line_num: line('.'),
        \ tokens: [],
        \ allowed_symbols_stack: [],
        \ disallowed_keywords_stack: [],
    \ }

    function tokeniser.next() abort
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
        if IsSymbol(l:token)
            if !InString(l:self.allowed_symbols, l:token)
                throw 'invalid'
            endif
        elseif InList(l:self.disallowed_keywords, l:token)
            throw 'invalid'
        endif

        return token
    endfunction


    function tokeniser.push_token(token) abort
        call insert(l:self.tokens, a:token)
        let l:self.tokens_remaining += 1
    endfunction


    function tokeniser.push_context(allowed_symbols, disallowed_keywords) abort
        let l:self.allowed_symbols_stack += [l:self.allowed_symbols]
        let l:self.disallowed_keywords_stack += [l:self.disallowed_keywords]

        let l:self.allowed_symbols = a:allowed_symbols
        let l:self.disallowed_keywords = a:disallowed_keywords
    endfunction


    function tokeniser.pop_context() abort
        let l:self.allowed_symbols = remove(l:self.allowed_symbols_stack, -1)
        let l:self.disallowed_keywords =
                                \ remove(l:self.disallowed_keywords_stack, -1)
    endfunction


    return tokeniser
endfunction


function SkipFunctionArrayDeclarators(tokeniser) abort
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
        if ']' == l:token
            let l:open -= 1

            " Parse next token to allow multidimensional arrays
            let l:token = a:tokeniser.next()
        endif

        if '[' == l:token
            let l:open += 1
        endif
    endwhile

    " Have read the token after the final closing ], push it back
    call a:tokeniser.push_token(token)
    call a:tokeniser.pop_context()
endfunction


" Not supported - attributes, functions returning a pointer to an array
function ParseFunctionProtoType() abort
    let l:allowed_symbols = '*(\'
    let l:disallowed_keywords = [
        \ 'auto', 'break', 'case', 'continue', 'default', 'do', 'else', 'for',
        \ 'goto', 'if', 'return', 'sizeof', 'switch', 'typedef'
    \ ]

    let l:tokeniser = NewTokeniser(l:allowed_symbols, l:disallowed_keywords)

    " Parse qualifiers/return type/name
    let l:have_name = 0
    let l:has_return_val = 1
    let l:token = v:null
    while l:token != '('
        let l:token = tokeniser.next()
        if l:token == 'void'
            " If a * follows it's a void pointer, otherwise it's a return value
            let l:token = tokeniser.next()
            if l:token != '*'
                let l:has_return_val = 0
            endif
        endif

        if l:token != '('
            let l:have_name = !IsSymbol(l:token)
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
        if !IsSymbol(l:token)
            let l:last_word = l:token
        elseif '[' == l:token
            call SkipFunctionArrayDeclarators(l:tokeniser)
        elseif ',' == l:token
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
    if !InString(l:tokeniser.allowed_symbols, l:token)
        throw 'invalid'
    endif

    return #{has_return_val: l:has_return_val, params: l:params}
endfunction


function MatchBackForward(pattern) abort
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


function FindDuplicateParam(param) abort
    let l:duplicate = v:null
    let l:pattern = '^\s*\* @param\s\+' . a:param . '\s'

    " Search current buffer first
    let l:buf_num = bufnr()
    let l:match_idx = MatchBackForward(l:pattern)

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


function AddFunctionComment(has_return_val, params) abort
    let l:doxygen = ['/**', ' * @brief']

    if len(a:params) > 0
        let l:doxygen += [' *']
        for l:param in a:params
            let l:duplicate = FindDuplicateParam(l:param)
            if l:duplicate is v:null
                let l:doxygen += [' * @param ' . l:param]
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


function doxygen#AddComment() abort
    try
        let l:proto_data = ParseFunctionProtoType()
    catch /\(invalid\|eof\)/
        call PrintError('Dox: no function prototype found')
        return
    endtry

    call AddFunctionComment(l:proto_data.has_return_val, l:proto_data.params)
endfunction


function doxygen#WarningsQuickfix(...) abort
    if !executable('doxygen')
        PrintError("Cannot find 'doxygen' executable")
        return
    endif

    let l:doxyfile_template =<< trim eval END
        EXTRACT_STATIC = YES
        QUIET = YES
        WARN_NO_PARAMDOC = YES
        INPUT = `=join(a:000)`
        RECURSIVE = YES
        GENERATE_HTML = NO
    END

    cgetexpr system('doxygen -', l:doxyfile_template)

    let l:qf_data = getqflist(#{size: 1})
    if l:qf_data.size > 0
        copen
    else
        echomsg 'No Doxygen warnings found'
    endif
endfunction


command -bar Dox call doxygen#AddComment()
command -nargs=* -complete=file -bar Dow call doxygen#WarningsQuickfix(<f-args>)
