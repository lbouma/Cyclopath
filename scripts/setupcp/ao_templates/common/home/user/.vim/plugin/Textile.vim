" This file is part of Dubsacks.
" --------------------------------
" Dubsacks is Copyright © 2009, 2010 Landon Bouma.
" 
" Dubsacks is free software: you can redistribute it and/or modify
" it under the terms of the GNU General Public License as published by
" the Free Software Foundation, either version 3 of the License, or
" (at your option) any later version.
" 
" Dubsacks is distributed in the hope that it will be useful,
" but WITHOUT ANY WARRANTY; without even the implied warranty of
" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
" GNU General Public License for more details.
" 
" You should have received a copy of the GNU General Public License
" along with Dubsacks. If not, see <http://www.gnu.org/licenses/>.

" ------------------------------------------
" textile.vim
" ------------------------------------------

" ------------------------------------------
" Preamble

" Authored by Landon Bouma <dubsacks.vim@retrosoft.com>

" This file is distributed under the terms of the 
" Vim license. See ":help license".

" ------------------------------------------
" Usage

" TODO

" ------------------------------------------
" Changelog

" Version 1.0.0 / 2009.09.09 / Landon Bouma
"   Initial release.

" ------------------------------------------
" Thescript

" Say no-no to the double-load-load
if exists("plugin_textile_vim")
  finish
endif
let plugin_textile_vim = 1

" ------------------------------------------
" User Command Mappings

" Map the script function to a global :command 
command! -bang -nargs=0 RenderTextileToHtml 
  \ call <SID>RenderTextileToHtml('<bang>')

" Map the :command to <Leader>tt
noremap <silent> <Leader>tt 
  \ :RenderTextileToHtml<CR>

" ------------------------------------------
" Private Interface

" LoadRedClothWrapper loads the textile.rb code, 
" which is a wrapper around the RedCloth gem.
" NOTE RedClothWrapperLoaded is -1 until run the 
"      first time, then it's either 0 or 1 
"      depending on the outcome
let s:RedClothWrapperFile = "textile.rb"
let s:RedClothWrapperPath = ""
let s:RedClothWrapperLoaded = -1
function s:LoadRedClothWrapper()

  if -1 == s:RedClothWrapperLoaded
    " Load associated Ruby code from either from 
    " the user's home directory or from the 
    " application's runtime directory
    " NOTE We check the user's home directory 
    "      first, so they can override the system  
    "      default
    " NOTE 
    "   *nix: /usr/local/share/vim/vim71/plugin/ 
    "    and: ~/.vim/plugin/
    "   *doz: C:\Program Files\Vim\vim72\plugin
    "    and: C:\Documents and 
    "             Settings\User\vimfiles\plugin
    if filereadable($HOME . "/.vim/plugin/" 
                    \ . s:RedClothWrapperFile)
      " $HOME/.vim is just *nix
      let s:RedClothWrapperPath = $HOME 
        \ . "/.vim/plugin/" . s:RedClothWrapperFile
    elseif filereadable($USERPROFILE 
                        \ . "/vimfiles/plugin/" 
                        \ . s:RedClothWrapperFile)
      " $HOME/vimfiles is just Windows
      let s:RedClothWrapperPath = $USERPROFILE 
        \ . "/vimfiles/plugin/" 
        \ . s:RedClothWrapperFile
    "elseif
      " TODO What about Mac? Probably just 
      "      like *nix, right?
    elseif filereadable($VIMRUNTIME 
                        \ . "/plugin/" 
                        \ . s:RedClothWrapperFile)
      " $VIMRUNTIME works for both *nix and Windows
      let s:RedClothWrapperPath = $VIMRUNTIME 
        \ . "/plugin/" . s:RedClothWrapperFile
    endif
  endif

  if (-1 == s:RedClothWrapperLoaded) && 
        \ !empty(s:RedClothWrapperPath)
    " TODO Since this is native Windows gVim 
    "      and our Ruby environment is Cygwin,
    "      we can start to load the Ruby file, 
    "      but it bombs on any 'requires', 
    "      probably just 'cause the PATHs aren't
    "      set...
    "
    "      ... so this does not work:
    "
    "        rubyfile $RUBYREDCLOTHWRAPPER
    "
    "      Instead, we'll just know the file 
    "      exists, and then, when the user runs 
    "      the command, we'll just execute !ruby, 
    "      rather than ruby
    let s:RedClothWrapperLoaded = 1
  else
    let s:RedClothWrapperLoaded = 0
    call confirm(
      \ "Unable to load Vim plugin file: \"" 
      \ . expand("%") . "\".\n\n" 
      \ . "Cannot find Ruby RedCloth wrapper: \"" 
      \ . s:RedClothWrapperFile . "\".\n\n" 
      \ . "Please place "
      \ . "\"" . s:RedClothWrapperFile . "\""
      \ . " in one of the plugin \n" 
      \ . "directories -- you can use either the "
      \ .   "one in your \n" 
      \ . "Vim home directory or the one in "
      \ .   "Vim's application \n"
      \ . "directory.")
  endif

endfunction

" RenderTextileToHtml renders the active buffer 
" to a new HTML file. The name and path of the 
" HTML are derived from the name and path of 
" the active buffer, and the user is asked to 
" confirm replacement of the HTML file if it 
" already exists (though one can use a bang to 
" force replacement without prompting).
function! s:RenderTextileToHtml(bang)

  " First things first, make sure the 
  " RedCloth wrapper exists
  call <SID>LoadRedClothWrapper()

  if 1 == s:RedClothWrapperLoaded

    " Start by constructing the path of the HTML 
    " output file.
    " NOTE Vim maps % to the current buffer's full 
    "      path and filename when used in bang cmds
    "      or when expanded.
    let HtmlFile = substitute(
      \ expand("%"), "\.txt$", "\.htm", "")
    if HtmlFile == expand("%")
      let HtmlFile = substitute(
        \ expand("%"), "\.textile$", "\.htm", "")
    endif
    if HtmlFile == expand("%")
      let HtmlFile = expand("%") . ".htm"
    endif

    " Next, see if the HTML output file already 
    " exists
    let ftype = getftype(HtmlFile)
    " ftype is non-empty if the item exists
    let confirmed = 1
    if ftype != ""
      if ftype != "file"
        echoerr "Cannot create Textile HTML file: "
          \ ."already exists and not a file: " 
          \ . HtmlFile
        let confirmed = 0
      elseif a:bang == "!"
        echomsg "Overwriting existing HTML file"
          \ . ": " . HtmlFile
      else
        let choice = confirm(
          \ "Overwrite \"" . HtmlFile . "\"?", 
          \ "&Yes\n&No\n&Cancel")
        if 1 != choice
          let confirmed = 0
        endif
      endif
    endif

    " Finally, make the ruby command and do it
    if 1 == confirmed
      " NOTE In a bang command, % gets expanded
      " NOTE Yes, that's a stdout > redirect
      execute "!ruby " 
        \ . '"' . s:RedClothWrapperPath . '"'
        \ . " % > "
        \ . '"' . HtmlFile . '"'
    endif

  endif

endfunction

" ------------------------------------------
" ----------------------------------- EOF --

