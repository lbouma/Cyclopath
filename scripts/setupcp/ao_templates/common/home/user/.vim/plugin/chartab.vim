"*****************************************************************************
"** Name:      chartab.vim - print a character table                        **
"**                                                                         **
"** Type:      global VIM plugin                                            **
"**                                                                         **
"** Author:    Christian Habermann                                          **
"**            christian (at) habermann-net (point) de                      **
"**                                                                         **
"** Copyright: (c) 2004 by Christian Habermann                              **
"**                                                                         **
"** License:   GNU General Public License 2 (GPL 2) or later                **
"**                                                                         **
"**            This program is free software; you can redistribute it       **
"**            and/or modify it under the terms of the GNU General Public   **
"**            License as published by the Free Software Foundation; either **
"**            version 2 of the License, or (at your option) any later      **
"**            version.                                                     **
"**                                                                         **
"**            This program is distributed in the hope that it will be      **
"**            useful, but WITHOUT ANY WARRANTY; without even the implied   **
"**            warrenty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      **
"**            PURPOSE.                                                     **
"**            See the GNU General Public License for more details.         **
"**                                                                         **
"** Version:   1.0.0                                                        **
"**            tested under Linux and Win32, VIM and GVIM 6.2               **
"**                                                                         **
"** History:   1.0.0  31. Jan. 2004                                         **
"**              initial version                                            **
"**                                                                         **
"**                                                                         **
"*****************************************************************************
"** Description:                                                            **
"**   This script provides a character table (yes, yet another one :-) ).   **
"**   But it has some nice features:                                        **
"**     - it takes advantage of syntax-highlighting                         **
"**     - it allows to toggle base of codes without leaving buffer          **
"**     - it opens in currently active window, so no rearrangement of       **
"**       windows occur                                                     **
"**     - special codes are viewed with their real names (NUL, ETX,...)     **
"**     - quitting is very simple and fast - just one keystroke             **
"**                                                                         **
"**   Installation:                                                         **
"**     To use this script copy it into your local plugin-directory         **
"**     Unix:    ~./.vim/plugin                                             **
"**     Windows: c:\vimfiles\plugin                                         **
"**     After starting VIM this script is sourced automatically.            **
"**                                                                         **
"**     By default, press <Leader>ct to view character table.               **
"**                                                                         **
"**   Configuration:                                                        **
"**     - <Plug>CT_CharTable                                                **
"**       mapping to open character table                                   **
"**       default:                                                          **
"**          map <silent> <unique> <Leader>ct <Plug>CT_CharTable            **
"**                                                                         **
"**     - g:ct_base                                                         **
"**       Defines base of codes. Allowed values are 'hex' and 'dec'.        **
"**       Default is 'dec'.                                                 **
"**       Add  let g:ct_base="hex" to your .vimrc if you want to change it. **
"**                                                                         **
"**   Known limitations:                                                    **
"**     If a character is not printable by Vim it is printed as two         **
"**     characters, e.g. ~A. This may cause a misalignment of the table.    **
"**                                                                         **
"**   Known bugs:                                                           **
"**     none - well, up to now :-)                                          **
"**                                                                         **
"**                                                                         **
"**   Happy vimming....                                                     **
"*****************************************************************************

" allow user to avoid loading this plugin and prevent loading twice
if exists ("ct_chartable")
    finish
endif

let ct_chartable = 1




"*****************************************************************************
"************************** C O N F I G U R A T I O N ************************
"*****************************************************************************

" the mappings:
if !hasmapto('<Plug>CT_CharTable')
    map <silent> <unique> <Leader>ct <Plug>CT_CharTable
endif

map <silent> <unique> <script> <Plug>CT_CharTable  :call <SID>CT_CharTable()<CR>



if !exists('g:ct_base')      " base of numbers, default is hex (hex, dec)
    let g:ct_base = "dec"
endif




"*****************************************************************************
"****************** I N T E R F A C E  T O  C O R E **************************
"*****************************************************************************

"*****************************************************************************
"** this function separates plugin-core-function from user                  **
"*****************************************************************************
function <SID>CT_CharTable()
    call s:CharTable()
endfunction



"***************************  END OF USER'S WORLD  ***************************




"*****************************************************************************
"************************* I N I T I A L I S A T I O N ***********************
"*****************************************************************************

" used to store number of buffer showing character table 
" set it to impossible value
let s:viewBufNr = -1 






"*****************************************************************************
"************************ C O R E  F U N C T I O N S *************************
"*****************************************************************************




"*****************************************************************************
"** input:   none                                                           **
"** output:  none                                                           **
"*****************************************************************************
"** remarks:                                                                **
"**   This is the main function where all jobs are initiated.               **
"**                                                                         **
"**   The buffer loaded to view search-result will be deleted at:           **
"**     - loading another buffer into the same window (automatic)           **
"**     - user cancles view (see CloseViewBuffer())                         **
"**                                                                         **
"*****************************************************************************
function s:CharTable()

    " allow modifications (necessary if called from the scripts own buffer)
    setlocal modifiable


    "open buffer for viewing character table
    call s:OpenViewBuffer()


    " define locale mappings of user interface
    call s:SetLocalKeyMappings()


    " set syntax highlighting for view
    call s:SetupSyntaxHighlighting()


    
    " make string for header of view => s:txt
    call s:MakeHeader()


    " add character table => s:txt; that's what user want to see
    call s:MakeCharTable()

    
    " output result
    setlocal modifiable
    
    put! = s:txt

    setlocal nomodifiable

endfunction




"*****************************************************************************
"** input:   none                                                           **
"** output:  none                                                           **
"*****************************************************************************
"** remarks:                                                                **
"**   Make string for header of view.                                       **
"*****************************************************************************
function s:MakeHeader()

    let s:txt =         "\"             Character Table\n"
    let s:txt = s:txt . "\"            =================\n"
    let s:txt = s:txt . "\"\n"
    let s:txt = s:txt . "\"  b : toggle base\n"
    let s:txt = s:txt . "\"  q : quit\n\n\n"

endfunction




"*****************************************************************************
"** input:   none                                                           **
"** output:  none                                                           **
"*****************************************************************************
"** remarks:                                                                **
"**   Print character table into current buffer.                            **
"*****************************************************************************
function s:MakeCharTable()

    let NUM_OF_ROWS = 32
    let NUM_OF_COLS = 8
    
    let code = 0
    let row  = 0  
   
   
    while row < NUM_OF_ROWS
    
        let column = 0

        while column < NUM_OF_COLS
            let code = row + column * NUM_OF_ROWS

            " add code number
            let s:txt = s:txt ." " . s:Nr2String(code, g:ct_base). " "

            " add character
            if (s:IsCodeSpecialChar(code))
                let s:txt = s:txt . s:GetStringOfSpecialChar(code)
                let spaceToNext = " "
            else
                let s:txt = s:txt . nr2char(code)
                let spaceToNext = "   "
            endif
            
            let s:txt = s:txt . ( (column == (NUM_OF_COLS - 1)) ? "" : spaceToNext . "|" )

            let column = column + 1
        endwhile
    
        let s:txt = s:txt . "\n"
      
        let row = row + 1
    endwhile

  
endfunction




"*****************************************************************************
"** input:   code: number to be converted to a string                       **
"**          base: defines base of number ("hex" or "dec")                  **
"** output:  formated string                                                **
"*****************************************************************************
"** remarks:                                                                **
"**   This function converts a number to a string.                          **
"*****************************************************************************
function s:Nr2String(nr, base)

    let nr   = a:nr
    let base = a:base


    " get base as a number
    if (a:base == "dec")
        let base = 10
    else
        let base = 16
    endif


    " convert number to string
    let strng = (nr == 0) ? "0" : ""

    while nr
        let strng = '0123456789ABCDEF'[nr % base] . strng
        let nr = nr / base
    endwhile
   
   
    " format string: 3 digits, right alignment
    if (base == 10)
        if (strlen(strng) == 1)
            let strng = "  " . strng 
        elseif (strlen(strng) == 2)
            let strng = " " . strng      
        endif
    else       " assume hex
        if (strlen(strng) == 1)
            let strng = "0" . strng 
        endif

        let strng = strng . "h"
    endif
    
    
    
    return strng
    
endfunction





"*****************************************************************************
"** input:   code: number to be tested                                      **
"** output:  0  : no special character                                      **
"**          > 0: code is a special character                               **
"*****************************************************************************
"** remarks:                                                                **
"**   This function tests whether 'code' is a special character.            **
"**   Special characters are: 0...0x20 and 0x7F, space (0x20) is included   **
"**                           here to print it as ' '                       **
"*****************************************************************************
function s:IsCodeSpecialChar(code)

  if ( ((a:code >= 0) && (a:code <= 0x20)) || (a:code == 0x7F) )
      return 1
  else
      return 0
  endif


endfunction




"*****************************************************************************
"** input:   code: code of special character 0..0x20 or 0x7F                **
"** output:  name of special character                                      **
"*****************************************************************************
"** remarks:                                                                **
"**   returns name of special character, e.g. code = 0 will return NUL      **
"*****************************************************************************
function s:GetStringOfSpecialChar(code)
    
    let strng = "-"

    if (a:code == 0)
        let strng = "NUL"
    elseif (a:code ==  1)
        let strng = "SOH"
    elseif (a:code ==  2)
        let strng = "STX"
    elseif (a:code ==  3)
        let strng = "ETX"
    elseif (a:code ==  4)
        let strng = "EOT"
    elseif (a:code ==  5)
        let strng = "ENQ"
    elseif (a:code ==  6)
        let strng = "ACK"
    elseif (a:code ==  7)
        let strng = "BEL"
    elseif (a:code ==  8)
        let strng = "BS "
    elseif (a:code ==  9)
        let strng = "TAB"
    elseif (a:code == 10)
        let strng = "LF "
    elseif (a:code == 11)
        let strng = "VT "
    elseif (a:code == 12)
        let strng = "FF "
    elseif (a:code == 13)
        let strng = "CR "
    elseif (a:code == 14)
        let strng = "SO "
    elseif (a:code == 15)
        let strng = "SI "
    elseif (a:code == 16)
        let strng = "DLE"
    elseif (a:code == 17)
        let strng = "DC1"
    elseif (a:code == 18)
        let strng = "DC2"
    elseif (a:code == 19)
        let strng = "DC3"
    elseif (a:code == 20)
        let strng = "DC4"
    elseif (a:code == 21)
        let strng = "NAK"
    elseif (a:code == 22)
        let strng = "SYN"
    elseif (a:code == 23)
        let strng = "ETB"
    elseif (a:code == 24)
        let strng = "CAN"
    elseif (a:code == 25)
        let strng = "EM "
    elseif (a:code == 26)
        let strng = "SUB"
    elseif (a:code == 27)
        let strng = "ESC"
    elseif (a:code == 28)
        let strng = "FS "
    elseif (a:code == 29)
        let strng = "GS "
    elseif (a:code == 30)
        let strng = "RS "
    elseif (a:code == 31)
        let strng = "US "
    elseif (a:code == 32)
        let strng = "\' \'"
    elseif (a:code == 127)
        let strng = "DEL"
    endif
        

    return strng
    
endfunction





"*****************************************************************************
"** input:   none                                                           **
"** output:  none                                                           **
"*****************************************************************************
"** remarks:                                                                **
"**   set local/temporarily key-mappings valid while viewing result         **
"*****************************************************************************
function s:SetLocalKeyMappings()
                                         " use 'q' to close view-buffer
                                         " and switch to previously used buffer
    nnoremap <buffer> <silent> q :call <SID>CT_Exit()<cr>

                                         " use 'b' to toggle base of codes
    nnoremap <buffer> <silent> b :call <SID>CT_ToggleBase()<cr>

    " [lb] Added 2009.08.28 to fit better w/ my EditPlus-esque vimrc
    " TODO Is there a way to do this from my vimrc file?

                                         " alias 'ESC' and Alt-Shift-1 to 'q'
    nnoremap <buffer> <silent> <ESC> :call <SID>CT_Exit()<cr>
    nnoremap <buffer> <silent> <M-!> :call <SID>CT_Exit()<cr>

endfunction




"*****************************************************************************
"** input:   errNr: number which defines an error (> 0)                     **
"** output:  none                                                           **
"*****************************************************************************
"** remarks:                                                                **
"**   this function prints an error-msg                                     **
"*****************************************************************************
"function s:Error(errNr)
"    
"    if (a:errNr == 1)
"        echo scriptName.": can't open buffer"
"    else
"        echo scriptName.": unknown error"
"    endif
"
"endfunction




"*****************************************************************************
"** input:   none                                                           **
"** output:  none                                                           **
"*****************************************************************************
"** remarks:                                                                **
"**   set syntax-highlighting (if VIM has 'syntax')                         **
"*****************************************************************************
function s:SetupSyntaxHighlighting()

    " don't continue, if this version of VIM does not support syntax-highlighting
    if !has('syntax')
        return
    endif

    syntax match ctComment  "^\".*"
    

    " matches both separator or start of line and code
    syn match ctSepaCode  "\(^\||\)[ ]\+[0-9A-Fa-fh]\+" contains=ctCode,ctSeparator
    
    " matches code only
    syn match ctCode      "[0-9A-Fa-fh]\+" contained
    
    " matches serparator only
    syn match ctSeparator "|" contained


    if !exists('g:ct_syntaxHighInit')
        let g:ct_syntaxHighInit = 0

        hi def link ctComment   Comment
        hi def link ctCode      String
        hi def link ctSeparator Comment
    endif

endfunction




"*****************************************************************************
"** input:   none                                                           **
"** output:  none                                                           **
"*****************************************************************************
"** remarks:                                                                **
"**   Open a buffer to view character table and for user interaction.       **
"**                                                                         **
"*****************************************************************************
function s:OpenViewBuffer()

    " save current buffer number so that we can switch back to this buffer
    " when finishing job
    " but only if the current buffer isn't already one of chartab's
    if (s:viewBufNr != winbufnr(0))
        let s:startBufNr = winbufnr(0)
    endif


    " open new buffer
    execute "enew"
    

    " save buffer number used by this script to view result
    let s:viewBufNr = winbufnr(0)


    " buffer specific settings:
    "   - nomodifiable:     don't allow to edit this buffer
    "   - noswapfile:       we don't need a swapfile
    "   - buftype=nowrite:  buffer will not be written
    "   - bufhidden=delete: delete this buffer if it will be hidden
    "   - nowrap:           don't wrap around long lines
    "   - iabclear:         no abbreviations in insert mode
    setlocal nomodifiable
    setlocal noswapfile
    setlocal buftype=nowrite
    setlocal bufhidden=delete
    setlocal nowrap
    iabclear <buffer>

endfunction




"*****************************************************************************
"** input:   none                                                           **
"** output:  none                                                           **
"*****************************************************************************
"** remarks:                                                                **
"**   Switch to buffer in which the script was invoked. Then the view-      **
"**   buffer will be deleted automatically.                                 **
"**   If there was no buffer at start of script, delete view-buffer         **
"**   explicitely.                                                          **
"*****************************************************************************
function s:CloseViewBuffer()

    " if start and view-buffer are the same, there was no buffer at invoking script
    if (s:startBufNr != s:viewBufNr)
        exec("buffer! ".s:startBufNr)
    else
        exec("bdelete ".s:startBufNr)
    endif

endfunction




"*****************************************************************************
"** input:   none                                                           **
"** output:  none                                                           **
"*****************************************************************************
"** remarks:                                                                **
"**   toggle base of numbers                                                **
"*****************************************************************************
function <SID>CT_ToggleBase()

    " save current cursor position
    let lineNr = line(".")
    let colNr  = col(".")


    " toggle base of numbers
    let g:ct_base = (g:ct_base == "dec") ? "hex" : "dec"

    " redraw view with new base
    call <SID>CT_CharTable()


    " restore cursor position
    call cursor(lineNr, colNr)

endfunction




"*****************************************************************************
"** input:   none                                                           **
"** output:  none                                                           **
"*****************************************************************************
"** remarks:                                                                **
"**   Job is done. Clean up.                                                **
"*****************************************************************************
function <SID>CT_Exit()

    call s:CloseViewBuffer()

endfunction



"*** EOF ***
