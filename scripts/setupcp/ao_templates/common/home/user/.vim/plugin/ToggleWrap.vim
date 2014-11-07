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

" ----------------------------------------
" ToggleWrap is a Vim plugin to make working 
" with and without text wrapping more pleasant.
" ----------------------------------------

" This code was original written by Harold Giménez
"   See his blog at 
"     http://awesomeful.net/posts/57-small-collection-of-useful-vim-tricks
"   And his vimrc file at
"     http://github.com/hgimenez/vimfiles/blob/c07ac584cbc477a0619c435df26a590a88c3e5a2/vimrc#L72-122

" The code was later adapted by Landon Bouma 
" for an EditPlus-inspired gVim configuration.

" This file is distributed under the terms of the 
" Vim license. See ":help license".

" Why ":set wrap" Isn't Enough
" -------------------------
" The 'wrap' option does exactly what it says -- 
" it visually wraps text that otherwise would
" extend past the right edge of a window.
"
" However, setting 'wrap' doesn't affect any 
" navigation keys, so you might notice 
" something -- using <Up>, <Down>, <Home>, and 
" <End> keys applies to the logical text line, not 
" to the visual line.
"
" E.g., suppose a long line is wrapped and now 
" spans four visual lines in a window; if you 
" put the cursor at the start of the line of 
" text and then press <Down>, rather than moving 
" the cursor down by one visual line, the 
" cursor instead jumps four visuals lines down 
" to the next actual line in the document (i.e., 
" past the next newline it finds).
"
" Another e.g., if you press <Home>, the cursor 
" jumps to the logical start of the line, which 
" may be on a visual line above the current one.
"
" Fortunately, Vim supports visual line 
" navigation as well as logical line navigation.
" So now, when in wrap mode, we can remap <Up> 
" and <Down> to move the cursor by one visual 
" line (rather than one logical line), and <Home>
" and <End> to move the cursor to the start or end 
" of the current visual line.

" Poo-poo on the double-load
if exists("plugin_togglewrap_vim")
  finish
endif
let plugin_togglewrap_vim = 1

" ToggleWrap function
" -------------------------
" ToggleWrap toggles the wrap options on or 
" off. The WrapIt() and UnwrapIt() functions 
" take care of massaging the environment to 
" be more functional in either mode.
function s:ToggleWrap()
  if &wrap
    echo "Wrap OFF"
    call s:UnwrapIt()
  else
    echo "Wrap ON"
    call s:WrapIt()
  endif
endfunction

" Toggle wrapping with \w
" -------------------------
noremap <silent> <Leader>w :call <SID>ToggleWrap()<CR>

" WrapIt
" -------------------------
function s:WrapIt()
  " Turn on wrapping (whereby lines are 
  " wrapped as soon as they hit the right
  " edge of the window)
  set wrap
  " Tell wrapping to logically wrap at word 
  " boundaries, so they're easier to read
  set linebreak
  " Disable virtualedit, which ...
  " TODO Not sure we should be setting 
  "      virtualedit=all in UnwrapIt()
  "set virtualedit=
  " Set the characters the linebreak option 
  " uses to determine where to break the line.
  " NOTE This is breakat's default setting 
  "      ... so I'm not sure setting this is 
  "      really all that necessary...
  "      unless maybe another call in UnwrapIt() 
  "      affects breakat?
  "set breakat=\ ^I!@*-+;:,./?
  " Add a '>' character to the start of every 
  " wrapped line
  " NOTE This sounds nice, but -- regardless that 
  "      I can't get it to work on Windows -- all 
  "      you really need is line numbers.
  "set showbreak=>
  " display defaults to ""; adding lastline means:
  "   "When included, as much as possible of the 
  "    last line in a window will be displayed.  
  "    When not included, last line that doesn't 
  "    fit is replaced with "@" lines."
  "  In other words, don't just show a bunch of 
  "  empty visual lines because Vim can't fit the 
  "  whole logical line in view!
  setlocal display+=lastline
  " Finally, remap navigation keys so they 
  " traverse visual boundaries, not logical ones 
  " (make sure to use <buffer> so it only applies 
  " to the current buffer).
  nnoremap  <buffer> <silent> k gk
  nnoremap  <buffer> <silent> j gj
  nnoremap  <buffer> <silent> <Up>   gk
  nnoremap  <buffer> <silent> <Down> gj
  nnoremap  <buffer> <silent> <Home> g<Home>
  nnoremap  <buffer> <silent> <End>  g<End>
  inoremap <buffer> <silent> <Up>   <C-o>gk
  inoremap <buffer> <silent> <Down> <C-o>gj
  inoremap <buffer> <silent> <Home> <C-o>g<Home>
  inoremap <buffer> <silent> <End>  <C-o>g<End>
  snoremap <buffer> <silent> <Up>   <C-o><Esc>gk
  snoremap <buffer> <silent> <Down> <C-o><Esc>gj
  snoremap <buffer> <silent> <Home> 
            \ <C-o><Esc>g<Home>
  snoremap <buffer> <silent> <End>  
            \ <C-o><Esc>g<End>
endfunction
 
" UnwrapIt
" -------------------------
" Undoes (resets back to normal) 
" everything WrapIt() changed
function s:UnwrapIt()
  set nowrap
  "   Setting virtualedit=all allows you 
  " to move the cursor past the end of 
  " a logical line of text (or even over 
  " the individual visual space characters 
  " used to represent a logical <Tab>). If 
  " you insert, Vim just pads from the end 
  " of the logical line to the cursor with 
  " spaces.
  "   To really see the end of a logical line, 
  " rather than using <Right>, hit <End>.
  " TODO This is interesting, but is it helpful?
  "set virtualedit=all
  nnoremap  <buffer> <silent> k k
  nnoremap  <buffer> <silent> j j
  nnoremap  <buffer> <silent> <Up>   k
  nnoremap  <buffer> <silent> <Down> j
  nnoremap  <buffer> <silent> <Home> <Home>
  nnoremap  <buffer> <silent> <End>  <End>
  inoremap <buffer> <silent> <Up>   <C-o>k
  inoremap <buffer> <silent> <Down> <C-o>j
  inoremap <buffer> <silent> <Home> <C-o><Home>
  inoremap <buffer> <silent> <End>  <C-o><End>
  snoremap <buffer> <silent> <Up>   <C-o>k
  snoremap <buffer> <silent> <Down> <C-o>j
  snoremap <buffer> <silent> <Home> <C-o><Home>
  snoremap <buffer> <silent> <End>  <C-o><End>
endfunction

" Fix environment on Vim startup
" -------------------------
" The following runs when Vim sources 
" this file (probably when Vim is 
" starting), so we should fix the 
" environment here if we set to wrap.
if &wrap
  call s:WrapIt()
endif

" Don't forget new buffers!
" -------------------------
autocmd BufWinEnter *
  \ if &wrap |
  \   call <SID>WrapIt() |
  \ endif

" ------------------------------------------
" ----------------------------------- EOF --

