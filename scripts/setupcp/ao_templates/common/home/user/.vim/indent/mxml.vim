" Description: MXML indenter (Flex development)
" Version:     2.0
" Maintainer:  David Fishburn <dfishburn at gmail dot com>
" Last Change: 2010 May 05
" Based on:    indent/xml.vim and indent/html.vim


" History
" Version 2.0
"   - Changed the indent script and removed "setlocal ignorecase" and used
"     search atoms to accomplish the same thing.  If the indenter kicked 
"     out ignorecase was mistakenly changed.  <mx:> tags should be 
"     case sensitive.  Coutesy of Ingo Karkat.

" Only load this indent file when no other was loaded.
if exists("b:did_indent")
    finish
endif
let b:did_indent = 1


" [-- local settings (must come before aborting the script) --]
setlocal indentexpr=MxmlIndentGet(v:lnum)
"setlocal indentkeys=o,O,*<Return>,<>>,{,}
" [lb] disabled indenting line when you return on it, ick.
setlocal indentkeys=o,O,<>>,{,}
" [lb] notes, here's Vim's MXML default:
"  \ indentexpr=XmlIndentGet(v:lnum,1)
"  \ indentkeys=o,O,*<Return>,<>>,<<>,/,{,}

let s:cpo_save = &cpo
set cpo-=C

" [-- count indent-increasing tags of line a:lnum --]
function! <SID>MxmlIndentOpen(lnum, pattern)
    " First handle the xml definition
    " <?xml version="1.0" encoding="utf-8"?>
    let s = substitute(getline(a:lnum), '<?.\{-}?>', '', 'g')
    " Strip out everything but closing mx tags
    " Replace those tags with "\2" - a special character
    let s = substitute(s, '\C</mx:', "\2", 'g')
    " Next, strip out everything but the beginning type tags - <mx:Panel> 
    " Change all tags to a special character - "\1"
    let s = substitute(s, '\C<mx:', "\1", 'g')
    " Remove everything but the < 
    let s = substitute(s, "[^\1]", '', 'g')
    " This tells us how many shiftwidths to indent
    return strlen(s)
endfunction

" [-- count indent-decreasing tags of line a:lnum --]
function! <SID>MxmlIndentClose(lnum, pattern)
    " First handle the xml definition
    " <?xml version="1.0" encoding="utf-8"?>
    let s = substitute(getline(a:lnum), '<?.\{-}?>', '', 'g')
    " Strip out everything but closing mx tags
    " Replace those tags with "\2" - a special character
    let multi_closing = substitute(s, '\C<\/mx:', "\1", 'g')
    " Remove everything but the marker
    let multi_closing = substitute(multi_closing, "[^\1]", '', 'g')
    " Get the count of single closing tags also using a special character 
    let single_closing = substitute(s, '\(/>\)', "\2", 'g')
    let single_closing = substitute(single_closing, "[^\2]", '', 'g')
    " This tells us how many shiftwidths to indent out
    " Starting indents - closing indents
    return strlen(multi_closing) + strlen(single_closing)
endfunction

" [-- count indent-increasing '{' of (java|css) line a:lnum --]
function! <SID>MxmlIndentOpenAlt(lnum)
    return strlen(substitute(getline(a:lnum), '[^{]\+', '', 'g'))
endfunction

" [-- count indent-decreasing '}' of (java|css) line a:lnum --]
function! <SID>MxmlIndentCloseAlt(lnum)
    return strlen(substitute(getline(a:lnum), '[^}]\+', '', 'g'))
endfunction

" [-- return the sum of indents respecting the syntax of a:lnum --]
function! <SID>MxmlIndentSum(lnum, style)
    let currline = getline(a:lnum)
    if a:style == match(currline, '^\s*</')
	if a:style == match(currline, '\C^\s*</\<\(mx:\)')
	    let open  = <SID>MxmlIndentOpen(a:lnum, '')
	    let close = <SID>MxmlIndentClose(a:lnum, '')
	    if 0 != open || 0 != close
		return open - close
	    endif
	endif
    endif
    if '' != &syntax &&
	\ synIDattr(synID(a:lnum, 1, 1), 'name') =~# '\(css\|java\).*' &&
	\ synIDattr(synID(a:lnum, strlen(currline), 1), 'name') =~# '\(css\|java\).*'
	if a:style == match(currline, '^\s*}')
	    return <SID>MxmlIndentOpenAlt(a:lnum) - <SID>MxmlIndentCloseAlt(a:lnum)
	endif
    endif
    return 0
endfunction

function! MxmlIndentGet(lnum)
    " Find a non-empty line above the current line.
    let prevlnum = prevnonblank(a:lnum - 1)

    " Hit the start of the file, use zero indent.
    if prevlnum == 0
	return 0
    endif

    " An alternate to this is to use the searchpair() function, but
    " I found the performance of it was abysmal, so using the 
    " search() function instead which is fast
    let as_end   = 0
    " Move the cursor to the start
    let as_start = search('\C<mx:Script',   'Wb')
    if as_start != 0
        " If a match was found, find the end to see
        " if the end tag is before our current line
        let as_end   = search('\C</mx:Script>', 'nW' )  
    endif

    " [-- special handling for ActionScript: use cindent --]
    if a:lnum > as_start && a:lnum < as_end
        " We're inside ActionScript
        if getline(a:lnum) =~# '<![CDATA['
            " When using the cindent() function, it expecting curly braces
            " in certain locations.  So I would prefer to indent according to 
            " the current indent location, but that does not work.
            " So, after the <![CDATA[ section, force indenting to the far left
            " and indent from there.  
            " This is OK as long as it is consistent.
            return 0
        endif
        return cindent(a:lnum)
    endif

    if getline(prevlnum) =~# ']]>'
        " After the <![CDATA[ section ends, restore our indent back to 
        " normal for the rest of the MXML tags
        return &sw
    endif

    let ind = <SID>MxmlIndentSum(prevlnum, -1)
    let ind = ind + <SID>MxmlIndentSum(a:lnum, 0)

    return indent(prevlnum) + (&sw * ind)
endfunction

let &cpo = s:cpo_save
unlet s:cpo_save
