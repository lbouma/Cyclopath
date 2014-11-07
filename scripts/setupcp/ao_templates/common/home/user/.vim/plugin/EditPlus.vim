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

" FIXME Rename this file, or combine/reorganize with dubsacks.vim -- 
"       While it was inspired by EditPlus 2 (and other text editors)
"       it's diverged so much and become it's own beast

" ------------------------------------------
"  EditPlus Vim Treatment
" ------------------------------------------

" Author: Landon Bouma <dubsacks.vim@retrosoft.com>
" Version: 0.0.1 / Summer Aught Nine
" License: What License?

" NOTE!! If you edit this file, be sure to delete
"        ~/vimfiles/Session.vim

" Startup
" ------------------------

" Load this script just once
if exists("plugin_editplus_vim")
  finish
endif
let plugin_editplus_vim = 1

" ------------------------------------------
"  EditPlus
" ------------------------------------------
" 'It doesn't suck,' says BBEdit. Which I 
" started using sometime in the 90s. Then 
" I graduated college, and some corporation 
" sent monies my way to program on Windows. 
" So I found EditPlus, which is the mostest 
" baddest-ass Windows GUI editor ever. No 
" Intellisence for me, thank you very much! 
" Just file and project browsing, and regex 
" searching to boot. And lots of nice keyboard 
" shortcuts. Which we try to mock herein.

" Welcome to the (Incomplete) Vim treatment 
" of EditPlus. Who doesn't use <M-f>e all 
" the time?

" --------------------------------
"  EditPlus // File Commands
" --------------------------------
" Ctrl-W and Ctrl-Q are GUI editor favorites.
" But in gVim on Windows, <C-q> remaps what 
" <C-v> was (which is "start Visual mode 
" blockwise", so that <C-v> can be used for 
" paste), and <C-w> is the start of all Window 
" commands (and if you touch that, an angry 
" mob of puritan Vimmers will come find you). 
" So instead, get used to Alt-F commands, i.e., 
" the File menu.

" The menu is created and populated 
"   $VIMRUNTIME/menu.vim
if has("menu") && has("gui_running")

  " --------------------------------
  " A Close is a close is a close
  " --------------------------------
  " ... No, I mean *REALLY* close it. Don't just 
  " hide the dang buffer -- pop it from the list. 
  " And show the last buffer we were on.
  "
  " menu.vim's File.Close calls :close, which 
  " closes the current window (or hides the 
  " active buffer if there's only one window left 
  " (and by hide I mean :enew is called to start 
  " a new buffer)). So it's not actually closing 
  " the file, it's closing the window or making a 
  " new buffer. I'm not sure why this is mapped 
  " to the File menu... so let's change it and 
  " make File.Close really close (i.e., release) 
  " the current file buffer. Do any or you Vimmer 
  " traditionalists have a problem with that? =)
  " (Also -- redundantly -- the :close command 
  "  is mapped to Window.Close, aka <Alt-W>c,
  "  or <Ctrl-W>c.)
  " NOTE 10.330 is File.Close, and 10.335 is 
  "      File.-SEP1-
  "      i.e., from menu.vim:
  "   an <silent> 10.330 &File.&Close<Tab>:close
  "     \ :if winheight(2) < 0 <Bar>
  "     \   confirm enew <Bar>
  "     \ else <Bar>
  "     \   confirm close <Bar>
  "     \ endif<CR>
  " 'Un'-menu the existing menu item
  aunmenu File.Close
  " Use :an rather than :menu to apply to all 
  " modes
  an 10.330 &File.&Close<Tab>:Bclose :Bclose<CR>
  " Thanks for :Bclose, Joe! (See: newbufdel.vim)
  "   http://vim.wikia.com/wiki/VimTip165

  " --------------------------------
  " Clear the buffer list
  " --------------------------------
  " <Alt-f>e ==> Close all files. This isn't 
  " like <Alt-f>x, which quits and preserves your 
  " workspace for the next time you run gVim.
  " This command literally deletes all your 
  " buffers and starts a new one for you.
  " TODO This is broken if you <Alt-f>c some 
  "      files and then quit -- the closed 
  "      buffers are reopened. I think this is 
  "      probably got to do with what's in 
  "      Session.vim -- but even if I <Alt-f>c 
  "      one buffer, then modify another buffer, 
  "      save it, and quit- on restart, the 
  "      buffer I closed is reopened (meaning, 
  "      Session.vim was rewrit but still 
  "      contains the closed buffers). This also 
  "      has to do w/ Vim hidden buffers, which I 
  "      don't completely get yet -- if you close 
  "      a buffer and remove it from your buffer 
  "      list, why is it just hidden and not 
  "      really gone? Does this have to do with 
  "      tags that are set, or something?
  " NOTE To work-around this, you have to <Alt-
  "      f>e to close all buffers, and then you 
  "      have to <Alt-f>x to quit -- I've got it 
  "      so if there's only the one empty buffer 
  "      open when you quit, then Session.vim is 
  "      deleted. Then, when you re-run Vim, none 
  "      of those closed buffers are re-opened.
  nmenu 10.331 &File.Clos&e\ All 
   \ :only<CR>:enew<CR>:BufOnly<CR>
  imenu 10.331 &File.Clos&e\ All  
   \ <C-O>:only<CR><C-O>:enew<CR><C-O>:BufOnly<CR>
  cmenu 10.331 &File.Clos&e\ All 
   \ <C-O>:only<CR><C-O>:enew<CR><C-O>:BufOnly<CR>
  omenu 10.331 &File.Clos&e\ All 
   \ <C-O>:only<CR><C-O>:enew<CR><C-O>:BufOnly<CR>
  " Thanks for :BufOnly, CJR!
  "   http://www.vim.org/scripts/script.php?script_id=1071

  " ------------------------------------------
  " Re-map Split Open, Before Mapping Save All
  " ------------------------------------------

  " Re-map the split command, which uses the  
  " same <Alt-f>l shortcut, i.e., from menu.vim:
  "   an 10.320 &File.Sp&lit-Open\.\.\.<Tab>:sp 
  "     \ :browse sp<CR>
  aunmenu File.Split-Open\.\.\.
  an 10.320 &File.Spli&t-Open\.\.\.<Tab>:sp 
    \ :browse sp<CR>

  " --------------------------------
  " Simple Save All
  " --------------------------------
  " <Alt-f>l ==> Save All
  "      :wa (save all buffers)
  "   or :xa (save-all-and-bidy-bye!)
  "      ZZ is also a nice way to save/close 
  "         current buffer/window
  " NOTE 10.350 is File.Save; 10.400 is 
  "      File.-SEP2-

  " Make Save All the new <Alt-f>l
  an 10.350 &File.Save\ A&ll<Tab>:wa :wa<CR>

  " --------------------------------
  " Make a Window.New that splits Vertically
  " --------------------------------
  " <Ctrl-W>n (also mapped to menu <Alt-w>n) 
  " opens a new window above the current one 
  " with an empty buffer. We want to do the 
  " same, but for a vertically-split window, 
  " i.e., open a new buffer in a new window 
  " to the right of the current window.
  "an 70.300 &Window.&New<Tab>^Wn			<C-W>n
  nmenu 70.301 &Window.New\ V-&Split<Tab>^Ws 
 \ <C-w>v<C-w>p:enew<CR><C-w>p
  imenu 70.301 &Window.New\ V-&Split<Tab>^Ws 
 \ <C-O><C-w>v<C-O><C-w>p<C-O>:enew<CR><C-O><C-w>p
  cmenu 70.301 &Window.New\ V-&Split<Tab>^Ws 
 \ <C-O><C-w>v<C-O><C-w>p<C-O>:enew<CR><C-O><C-w>p
  omenu 70.301 &Window.New\ V-&Split<Tab>^Ws 
 \ <C-O><C-w>v<C-O><C-w>p<C-O>:enew<CR><C-O><C-w>p

endif " has("menu") && has("gui_running")

" --------------------------------
"  EditPlus // F-Keys
" --------------------------------

" Find next/previous
" --------------------------------
" Map F3 and Shift-F3 to find next/previous
""map <F3> n
""map <F3> *
"noremap <F3> *
"inoremap <F3> <C-O>*
""cnoremap <F3> :<C-R><C-W>*
""onoremap <F3> :<C-R><C-W>*
""map <S-F3> N
""map <S-F3> #
"noremap <S-F3> #
"inoremap <S-F3> <C-O>#
""cnoremap <S-F3> <C-O>#
""onoremap <S-F3> <C-O>#
"" Start a *-search w/ Ctrl-F3
""map <C-F3> *

" Start a(n advanced) *-search w/ simply F1
" --------------------------------
" A Vim star search (search for the stars!) searches 
" the word under the cursor- but only the word under 
" the cursor! It doesn't not search abbreviations. So 
" star-searching, say, "item" wouldn't also match 
" "item_set" or "item_get". Since the latter is sometimes 
" nice, and since we already have a star search mapping,
" let's map F1 to a more liberal star search. Maybe you
" want to a call it a b-star search, as in, B Movie star-
" you'll still be star-searching, you'll just get a lot
" more hits.

" Select current word under cursor
" The hard way:
"   b goes to start of word,
"   "zyw yanks into the z register to start of next word
" :map <F1> b"zyw:echo "h ".@z.""
" The easy way:
noremap <F1> /<C-R><C-W><CR>
inoremap <F1> <C-O>/<C-R><C-W><CR>
" NOTE Same as <C-F3>
vnoremap <F1> :<C-U>
  \ <CR>gvy
  \ gV
  \ /<C-R>"<CR>

" Start a whole-word *-search w/ Shift-F1
" --------------------------------
" 2013.02.28: This used to be C-F3 but that's not an easy keystroke.
"             S-F1 is easier.
" Search for the whole-word under the cursor, but return
" to the word under the cursor. <F1> alone starts searching,
" but sometimes you want to highlight whole-words without
" losing your position.
" NOTE: The ? command returns to the previous hit, where the cursor
"       was before * moved it.
" on onto bontop
noremap <S-F1> *?<CR>
inoremap <S-F1> <C-O>*<C-O>?<CR>
" NOTE When text selected, S-F1 same as plain-ole S-F1 and
"      ignores whole-word-ness.
" FIXME: The ? returns the cursor but the page is still scrolled.
"        So often the selected word and cursor are the first line
"        in the editor.
vnoremap <S-F1> :<C-U>
  \ <CR>gvy
  \ gV
  \ /<C-R>"<CR>
  \ ?<CR>

" Repeat previous search fwd or back w/ F3 and Shift-F3
" NOTE Using /<CR> instead of n because n repeats the last / or *
noremap <F3> /<CR>
inoremap <F3> <C-O>/<CR>
" To cancel any selection, use <ESC>, but also use gV to prevent automatic 
" reselection. The 'n' is our normal n.
" FIXME If you have something selected, maybe don't 'n' but search selected
"       text instead?
"vnoremap <F3> <ESC>gVn
" NOTE The gV comes before the search, else the cursor ends up at the second
"      character at the next search word that matches
vnoremap <F3> :<C-U>
  \ <CR>gvy
  \ gV
  \ /<C-R>"<CR>
" Backwards:
noremap <S-F3> ?<CR>
inoremap <S-F3> <C-O>?<CR>
"vnoremap <S-F3> <ESC>gVN
" Remember, ? is the opposite of /
vnoremap <S-F3> :<C-U>
  \ <CR>gvy
  \ gV
  \ ?<C-R>"<CR>?<CR>

" Fullscreen
" --------------------------------
" This is such a hack! Just set lines and columns 
" to ridiculous numbers.
" See dubsacks.vim, which inits cols,ll to 111,44
" FIXME 111,44 magic numbers, also shared w/ dubsacks.vim
""nmap <silent> <M-$> <Plug>ToggleFullscreen_Hack
""imap <silent> <M-$> <C-O><Plug>ToggleFullscreen_Hack
" 2011.05.20: Disabling. It sucks at what it does.
"map <F11> <Plug>ToggleFullscreen_Hack

" FIXME I don't use this fcn.: it's not very elegant. I just 
"       double-click the titlebar instead and let Gnome handle it... 

map <silent> <unique> <script> 
  \ <Plug>ToggleFullscreen_Hack 
  \ :call <SID>ToggleFullscreen_Hack()<CR>
"   2. Thunk the <Plug>
function s:ToggleFullscreen_Hack()
  if exists('s:is_fullscreentoggled')
      \ && (1 == s:is_fullscreentoggled)
    set columns=111 lines=44
    let s:is_fullscreentoggled = 0
  else
    " FIXME This causes weird scrolling phenomenon
    set columns=999 lines=999
    " FIXME Do this instead in Windows?
    " au GUIEnter * simalt ~x
    let s:is_fullscreentoggled = 1
  endif
endfunction
let s:is_fullscreentoggled = 0

" MRU Buffer Jumping
" --------------------------------
" Map F12 to Ctrl-^, to toggle between the 
" current buffer and the last used buffer.
" But first!
"   Turn on hidden, so if we're on a modified 
"   buffer, we can hide it without getting a 
"   warning
set hidden
" 2011.05.20: I don't use this for jumping buffers. 
"             I use F2 and the pg-right key.
"map <F12> :e #<CR>
"inoremap <F12> <C-O>:e #<CR>
"" cnoremap <F12> <C-C>:e #!<CR>
"" onoremap <F12> <C-C>:e #<CR>

" My left hand felt left out, so I mapped Ftoo, 2.
" Note that when text is selected, F1 sends it to par.
nnoremap <F2> :e #<CR>
inoremap <F2> <C-O>:e #<CR>

" Allow toggling between MRU buffers
" from Insert mode
" FIXME 2011.01.17 I never use these keys
" FIXME 2012.06.26 I just tested selecting text and hitting Ctrl-6 and the
"       screen only blipped at me but I didn't change buffers like F2.
" FIXME: Broken 'til fixed!
"inoremap <C-^> <C-O>:e #<CR>
"noremap <C-6> <C-O>:e #<CR>
"" cnoremap <F12> <C-C>:e #!<CR>
"" onoremap <F12> <C-C>:e #<CR>

" 2011.01.17 On my laptop, I've got Browser Fwd
"            mapped to <End> in ~/.xmodmap.
"            (Browser Fwd is just above <Right>)
"            Since Browser back is a special key,
"            too (delete), and since I use F12 a lot,
"            I figured I'd map the MRU buffer to 
"            Alt-End, as well, so I can find hit when 
"            I'm on the bottoms of my keyboard.
" I've got two available keys: M-BrwLeft and BrwRight
" (Really, M-BrwLeft is M-Delete, and BrwRight is End)
" I think I'll remap BrwRight to F12 instead of End...
"map <M-End> :e #<CR>
"inoremap <M-End> <C-O>:e #<CR>

" --------------------------------
"  EditPlus // Editing Controls
" --------------------------------

" TODO Should any of the following be mapped:
"      -- to Command mode (cmap)?
"      -- to Operator-pending mode (omap)?
"      -- to Visual mode (vmap)?

" A Better Backspace
" --------------------------------

" Ctrl-Backspace deletes to start of word
noremap <C-BS> db
inoremap <C-BS> <C-O>db

" Ctrl-Shift-Backspace deletes to start of line
noremap <C-S-BS> d<Home>
inoremap <C-S-BS> <C-O>d<Home>

" A Delicious Delete
" --------------------------------

" In EditPlus, Ctrl-Delete deletes characters 
" starting at the cursor and continuing to the 
" end of the word, or until certain punctuation. 
" If the cursor is on whitespace instead of a
" non-whitespace character, Ctrl-Delete just 
" deletes the continuous block of whitespace, 
" up until the next non-whitespace character.
"
" In Vim, the 'dw' and 'de' commands perform
" similarly, but they include whitespace, either 
" after the word is deleted ('dw'), or before 
" it ('de'). Therefore, to achieve the desired 
" behaviour -- such that contiguous blocks of 
" whitespace and non-whitespace are treated 
" independently -- we need a function to tell 
" if the character under the cursor is whitespace 
" or not, and to call 'dw' or 'de' as appropriate.
" NOTE Was originally called DeleteToEndOfWord, 
"      but really,
"   DeleteToEndOfWhitespaceAlphanumOrPunctuation
" --------------------------------
"  Original Flavor
function! s:Del2EndOfWsAz09OrPunct_ORIG()
  " If the character under the cursor is 
  " whitespace, do 'dw'; if it's an alphanum, do 
  " 'dw'; if punctuation, delete one character
  " at a time -- this way, each Ctrl-Del deletes 
  " a sequence of characters or a chunk of 
  " whitespace, but never both (and punctuation 
  " is deleted one-by-one, seriously, this is 
  " the way's I like's it).
  let char_under_cursor = 
    \ getline(".")[col(".") - 1]
  " Can't get this to work:
  "    if char_under_cursor =~ "[^a-zA-Z0-9\\s]"
  " But this works:
  if (char_under_cursor =~ "[^a-zA-Z0-9]")
        \ && (char_under_cursor !~ "\\s")
    " Punctuation et al.; just delete the 
    " char or sequence of the same char.
    " Well, I can't get sequence-delete to 
    " work, i.e.,
    "      execute 'normal' . 
    "        \ '"xd/' . char_under_cursor . '*'
    " doesn't do squat. In fact, any time I try 
    " the 'd/' motion it completely fails...
    " Anyway, enough boo-hooing, just delete the 
    " character-under-cursor:
    execute 'normal' . '"xdl'
  elseif char_under_cursor =~ '[a-zA-Z0-9]'
    " This is an alphanum; and same spiel as 
    " above, using 'd/' does not work, so none of 
    " this: 
    "   execute 'normal' . '"xd/[a-zA-Z0-9]*'
    " Instead try this:
    "execute 'normal' . '"xde'
    execute 'normal' . '"xdw'
  elseif char_under_cursor =~ '\s'
    " whitespace
    " Again -- blah, blah, blah -- this does not 
    " work: execute 'normal' . '"xd/\s*'
    execute 'normal' . '"xdw'
  " else
  "   huh? this isn't/shouldn't be 
  "         an executable code path
  endif
endfunction
" --------------------------------
"  NEW FLAVOR
function! s:Del2EndOfWsAz09OrPunct(wasInsertMode, deleteToEndOfLine)
  " If the character under the cursor is 
  " whitespace, do 'dw'; if it's an alphanum, do 
  " 'dw'; if punctuation, delete one character
  " at a time -- this way, each Ctrl-Del deletes 
  " a sequence of characters or a chunk of 
  " whitespace, but never both (and punctuation 
  " is deleted one-by-one, seriously, this is 
  " the way's I like's it).
  " 2010.01.01 First New Year's Resolution
  "            Fix Ctrl-Del when EOL (it cur-
  "            rently deletes back a char, rath-
  "            er than sucking up the next line)
  let s:char_under_cursor = 
    \ getline(".")[col(".") - 1]
  "call confirm(
  "      \ 'char ' . s:char_under_cursor
  "      \ . ' / char2nr ' . char2nr(s:char_under_cursor)
  "     \ . ' / col. ' . col(".")
  "      \ . ' / col$ ' . col("$"))
  if (       ( ((col(".") + 1) == col("$")) 
        \     && (col("$") != 2) )
        \ || ( ((col(".") == col("$")) 
        \     && (col("$") == 1)) 
        \     && (char2nr(s:char_under_cursor) == 0) ) )
    " At end of line; delete newline after cursor
    " (what vi calls join lines)
    execute 'normal gJ'
    "execute 'j!'
    " BUGBUG Vi returns the same col(".") for both 
    " the last and next-to-last cursor positions, 
    " so we're not sure whether to join lines or 
    " to delete the last character on the line. 
    " Fortunately, we can just go forward a 
    " character and then delete the previous char, 
    " which has the desired effect
    " Or not, I can't get this to work...
    "execute 'normal ^<Right'
    "execute 'normal X'
    "let this_col = col(".")
    "execute 'normal l'
    "let prev_col = col(".")
    "call confirm('this ' . this_col . ' prev ' . prev_col)
    "
    let s:cur_col = col(".")
    let s:tot_col = col("$")
    " This is a little hack; the d$ command below, which executes if the 
    " cursor is not in the last position, moves the cursor one left, so the 
    " callee moves the cursor back to the right. However, our gJ command 
    " above doesn't move the cursor, so, since we know the callee is going 
    " to move it, we just move it left
    if a:deleteToEndOfLine == 1
      execute 'normal h'
    endif
  else
    let s:cur_col = col(".")
    let s:tot_col = col("$")
    if (a:wasInsertMode 
          \ && (s:cur_col != 1) )
      " <ESC> Made us back up, so move forward one,
      " but not if we're the first column or the 
      " second-to-last column
        execute 'normal l'
    endif
    "let s:char_under_cursor = 
    "  \ getline(".")[col(".")]
    " Can't get this to work:
    "    if s:char_under_cursor =~ "[^a-zA-Z0-9\\s]"
    " But this works:
    if a:deleteToEndOfLine == 1
      execute 'normal d$'
    else
      if (s:char_under_cursor =~ "[^_a-zA-Z0-9\(\.]")
            \ && (s:char_under_cursor !~ "\\s")
        " Punctuation et al.; just delete the 
        " char or sequence of the same char.
        " Well, I can't get sequence-delete to 
        " work, i.e.,
        "      execute 'normal' . 
        "        \ '"xd/' . s:char_under_cursor . '*'
        " doesn't do squat. In fact, any time I try 
        " the 'd/' motion it completely fails...
        " Anyway, enough boo-hooing, just delete the 
        " character-under-cursor:
        execute 'normal "xdl'
      elseif s:char_under_cursor =~ '[_a-zA-Z0-9\(\.]'
        " This is an alphanum; and same spiel as 
        " above, using 'd/' does not work, so none of 
        " this: 
        "   execute 'normal' . '"xd/[a-zA-Z0-9]*'
        " Instead try this:
        "execute 'normal' . '"xde'
        execute 'normal "xdw'
      elseif s:char_under_cursor =~ '\s'
      "if s:char_under_cursor =~ '\s
        " whitespace
        " Again -- blah, blah, blah -- this does not 
        " work: execute 'normal' . '"xd/\s*'
        execute 'normal "xdw'
      " else
      "   huh? this isn't/shouldn't be 
      "         an executable code path
      endif
    endif
  endif
  if (a:wasInsertMode 
        \ && ((s:cur_col + 2) == s:tot_col))
    " <ESC> Made us back up, so move forward one,
    " but not if we're the first column or the 
    " second-to-last column
    "execute 'normal h'
  endif
endfunction
" Map the function to Ctrl-Delete in normal and 
" insert modes.
noremap <C-Del> :call <SID>Del2EndOfWsAz09OrPunct(0, 0)<CR>
" BUGBUG To call a function from Insert Mode -- or to even get 
"        the current column number of the cursor -- we need 
"        to either <C-O> or <Esc> out of Insert mode. If 
"        we <C-O> and the cursor is on either the last 
"        column or the second-to-last-column, the cursor 
"        is moved to the last column. Likewise, if we 
"        <Esc> and the cursor is on either the first column 
"        or the second column, the cursor is moved to the 
"        first column. I cannot figure out a work-around.
"        I choose <Esc> as the lesser of two evils. I.e., 
"        using <C-O>, if the cursor is at the second-to-
"        last column, a join happens but the last character 
"        remains; using <Esc>, if you <Ctrl-Del> from the 
"        second column, both the first and second columns 
"        are deleted. I <Ctrl-Del> from the end of a line 
"        much more ofter than from the second column of a 
"        line.
"inoremap <C-Del> 
"         \ <C-O>:call <SID>Del2EndOfWsAz09OrPunct()<CR>
inoremap <C-Del> 
         \ <Esc>:call <SID>Del2EndOfWsAz09OrPunct(1, 0)<CR>i

" Ctrl-Shift-Delete deletes to end of line
"noremap <C-S-Del> d$
"inoremap <C-S-Del> <C-O>d$
noremap <C-S-Del> :call <SID>Del2EndOfWsAz09OrPunct(0, 1)<CR>
inoremap <C-S-Del> 
         \ <Esc>:call <SID>Del2EndOfWsAz09OrPunct(1, 1)<CR>i<Right>

" 2011.02.01 Doing same for Alt-Delete
noremap <M-Del> :call <SID>Del2EndOfWsAz09OrPunct(0, 1)<CR>
inoremap <M-Del> 
         \ <Esc>:call <SID>Del2EndOfWsAz09OrPunct(1, 1)<CR>i<Right>

" Alt-Shift-Delete deletes entire line
noremap <M-S-Del> dd
inoremap <M-S-Del> <C-O>dd

" Fix That Shift
" --------------------------------
" Vim's default Ctrl-Shift-Left/Right behavior is 
" to select all non-whitespace characters (see 
" :help v_aW). We want to change this to not be 
" so liberal. Use vmap to change how Vim selects 
" text in visual mode. By using 'e' instead of 
" 'aW', for example, Vim selects alphanumeric 
" blocks but doesn't cross punctuation boundaries.
" In other words, we want to select blocks of 
" whitespace, alphanums, or punctuation, but 
" never combinations thereof.
" TODO This still isn't quite right -- the first 
"      selection is always too great, i.e., the 
"      cursor jumps boundaries 'b' and 'e' 
"      wouldn't
vnoremap <C-S-Left> b
vnoremap <C-S-Right> e

" Alt-Shift-Left selects from cursor to start of line
" (same as Shift-Home)
noremap <M-S-Left> v0
inoremap <M-S-Left> <C-O>v0
vnoremap <M-S-Left> 0

" Alt-Shift-Right selects from cursor to end of line
" (same as Shift-End)
noremap <M-S-Right> v$
inoremap <M-S-Right> <C-O>v$
vnoremap <M-S-Right> $

" Character Transposition
" --------------------------------
" Transpose two characters when in Insert mode
" NOTE We can't just 'Xp' and be all happy -- 
"      rather, if we're at the first column 
"      (start) of the line, 'Xp' does something 
"      completely different. So use 'Xp' if the 
"      cursor is anywhere but the first column, 
"      but use 'xp' otherwise.
function s:TransposeCharacters()
  let cursorCol = col('.')
  if 1 == cursorCol
    execute 'normal ' . 'xp'
  else
    execute 'normal ' . 'Xp'
  endif
endfunction
inoremap <C-T> 
  \ <C-o>:call <SID>TransposeCharacters()<CR>
" NOTE Make a mapping for normal mode -- 
"      but this obscures the original Ctrl-T 
"      command, which inserts a tab at the 
"      beginning of the line; see :help Ctrl-t

" Command-line Copy
" --------------------------------
" gVim/win maps Ctrl-C to yank, but only 
" in Normal and Insert modes. Here we make 
" it so Ctrl-C also works in the 
" Command-line window.
cmap <C-C> <C-Y>

" Indent Selected Text
" --------------------------------
" Vim's <Tab> is used to move the cursor 
" according to the jump list, but it's silly. 
" I.e., in Insert mode, if you have nothing 
" selected, <Tab> does what? Inserts a <Tab>. 
" What happens if you have text selected? 
" And I mean besides entering visual edit mode?
" My computer rings the bell and the Vim window 
" does a quiet beep (so... nothing!).
"
" Thusly, use Tab/Shift-Tab to add/remove indents
vnoremap <Tab> >gv
vnoremap <S-Tab> <gv
" NOTE Also remember that == smartly fixes  
"      the indent of the line-under-cursor

" --------------------------------
"  EditPlus // Document Navigation
" --------------------------------

" Sane Scrolling
" --------------------------------
" Map Ctrl-Up and Ctrl-Down to scrolling
" the window 'in the buffer', as the :help
" states. Really, it just moves the scrollbar,
" i.e., scrolls your view without moving your
" cursor.
noremap <C-Up> <C-y>
inoremap <C-Up> <C-O><C-y>
cnoremap <C-Up> <C-C><C-y>
onoremap <C-Up> <C-C><C-y>
noremap <C-Down> <C-e>
inoremap <C-Down> <C-O><C-e>
cnoremap <C-Down> <C-C><C-e>
onoremap <C-Down> <C-C><C-e>

" Quick Cursor Jumping
" --------------------------------
" EditPlus, among other editors, maps Ctrl-PageUp
" and Ctrl-PageDown to moving the cursor to the 
" top and bottom of the window (equivalent to 
" H and L in Vim (which also defines M to jump 
" to the middle of the window, which is not 
" mapped here)).
" NOTE In a lot of programs, C-PageUp/Down go to 
"      next/previous tab page; not so here, see
"      Alt-PageUp/Down for that.
"      FIXME 2011.01.16 Alt-PageUp/Down is broken...
"            (well, that, and I never use it)
noremap <C-PageUp> :call <SID>Smart_PageUpDown(1)<CR>
inoremap <C-PageUp> <C-O>:call <SID>Smart_PageUpDown(1)<CR>
noremap <C-PageDown> :call <SID>Smart_PageUpDown(-1)<CR>
inoremap <C-PageDown> <C-O>:call <SID>Smart_PageUpDown(-1)<CR>

" On my laptop, my right hand spends a lot of time near 
" (and using) the arrow keys, which are on the bottom 
" of the keyboard, but the other navigation keys (home, 
" end, page up and down and the ilk) are far, far away, 
" at the top of the keyboard. But we can map those to 
" Alt-Arrow Key combinations to make our hands happy
" (or is it to make our fingers frolicsome?).

" Alt-Up moves cursor to the top of the window, or, if 
" it's already there, it scrolls up one window.
noremap <M-Up> :call <SID>Smart_PageUpDown(1)<CR>
inoremap <M-Up> <C-O>:call <SID>Smart_PageUpDown(1)<CR>
vnoremap <M-Up> :<C-U>
  \ <CR>gvy
  \ :call <SID>Smart_PageUpDown(1)<CR>

" Alt-Down moves cursor to the bottom of the window, or, if 
" it's already there, it scrolls down one window.
noremap <M-Down> :call <SID>Smart_PageUpDown(-1)<CR>
inoremap <M-Down> <C-O>:call <SID>Smart_PageUpDown(-1)<CR>
vnoremap <M-Down> :<C-U>
  \ <CR>gvy
  \ :call <SID>Smart_PageUpDown(-1)<CR>

" Alt-Left moves the cursor to the beginning of the line.
noremap <M-Left> <Home>
inoremap <M-Left> <C-O><Home>
vnoremap <M-Left> :<C-U>
  \ <CR>gvy
  \ :execute "normal! 0"<CR>

" Alt-Right moves the cursor to the end of the line.
noremap <M-Right> <End>
inoremap <M-Right> <C-O><End>
vnoremap <M-Right> :<C-U>
  \ <CR>gvy
  \ :execute "normal! $"<CR>

function s:Smart_PageUpDown(direction)
  let cursor_cur_line = line(".")
  if a:direction == 1
    let window_first_line = line("w0")
    if cursor_cur_line == window_first_line
      " Cursor on first visible line; scroll window one page up
      execute "normal! \<C-B>"
    endif
    " Move cursor to first visible line; make 
    " sure it's in the first column, too
    execute 'normal H0'
  elseif a:direction == -1
    let window_last_line = line("w$")
    if cursor_cur_line == window_last_line
      " Cursor on last visible line; scroll window one page down
      execute "normal! \<C-F>"
    endif
    " Move cursor to last visible line; make 
    " sure it's in the first column, too
    execute 'normal L0'
  else
    call confirm('EditPlus.vim: Programmer Error!', 'OK')
  endif
endfunction

" 2011.01.16 Will I find this useful?
" Alt-End moves the cursor to the middle of the window.
" And starts editing.
"noremap <M-End> M0i
"inoremap <M-End> <C-O>M<C-O>0
"vnoremap <M-End> :<C-U>
"  \ <CR>gvy
"  \ :execute "normal! M0"<CR>
noremap <M-F12> M0i
inoremap <M-F12> <C-O>M<C-O>0
vnoremap <M-F12> :<C-U>
  \ <CR>gvy
  \ :execute "normal! M0"<CR>

" A Smarter Select
" --------------------------------

" Ctrl-Shift-PageUp selects from cursor to first line of window
noremap <C-S-PageUp> vH
inoremap <C-S-PageUp> <C-O>vH
cnoremap <C-S-PageUp> <C-C>vH
onoremap <C-S-PageUp> <C-C>vH
vnoremap <C-S-PageUp> H
" (And so does Alt-Shift-Up)
noremap <M-S-Up> vH
inoremap <M-S-Up> <C-O>vH
cnoremap <M-S-Up> <C-C>vH
onoremap <M-S-Up> <C-C>vH
vnoremap <M-S-Up> H

" Ctrl-Shift-PageDown selects from cursor to last line of window
noremap <C-S-PageDown> vL
inoremap <C-S-PageDown> <C-O>vL
cnoremap <C-S-PageDown> <C-C>vL
onoremap <C-S-PageDown> <C-C>vL
vnoremap <C-S-PageDown> L
" (And so does Alt-Shift-Down)
noremap <M-S-Down> vL
inoremap <M-S-Down> <C-O>vL
cnoremap <M-S-Down> <C-C>vL
onoremap <M-S-Down> <C-C>vL
vnoremap <M-S-Down> L

" Ctrl-Tab is for Tabs, Silly... no wait, Buffers!
" --------------------------------
" mswin.vim maps Ctrl-Tab to Next Window. To be 
" more consistent with Windows (the OS), Ctrl-Tab 
" should map to Next Tab... but in this case, I'm 
" going to deviate from the norm and ask that you 
" tab-holders-onners let go and try thinking in 
" terms of buffers. It's all about the buffers, 
" benjamin! (baby?)

" TODO The cursor is not preserved between 
"      buffers! So make code that restores 
"      the cursor...

" This is Ctrl-Tab to Next Buffer
"noremap <C-Tab> :bn<CR>
"inoremap <C-Tab> <C-O>:bn<CR>
""cnoremap <C-Tab> <C-C>:bn<CR>
"onoremap <C-Tab> <C-C>:bn<CR>
"snoremap <C-Tab> <C-C>:bn<CR>
noremap <C-Tab> :call <SID>BufNext_SkipSpecialBufs(1)<CR>
inoremap <C-Tab> <C-O>:call <SID>BufNext_SkipSpecialBufs(1)<CR>
"cnoremap <C-Tab> <C-C>:call <SID>BufNext_SkipSpecialBufs(1)<CR>
onoremap <C-Tab> <C-C>:call <SID>BufNext_SkipSpecialBufs(1)<CR>
snoremap <C-Tab> <C-C>:call <SID>BufNext_SkipSpecialBufs(1)<CR>

" This is Ctrl-Shift-Tab to Previous Buffer
"noremap <C-S-Tab> :bN<CR>
"inoremap <C-S-Tab> <C-O>:bN<CR>
""cnoremap <C-S-Tab> <C-C>:bN<CR>
"onoremap <C-S-Tab> <C-C>:bN<CR>
"snoremap <C-S-Tab> <C-C>:bN<CR>
noremap <C-S-Tab> :call <SID>BufNext_SkipSpecialBufs(-1)<CR>
inoremap <C-S-Tab> <C-O>:call <SID>BufNext_SkipSpecialBufs(-1)<CR>
"cnoremap <C-S-Tab> <C-C>:call <SID>BufNext_SkipSpecialBufs(-1)<CR>
onoremap <C-S-Tab> <C-C>:call <SID>BufNext_SkipSpecialBufs(-1)<CR>
snoremap <C-S-Tab> <C-C>:call <SID>BufNext_SkipSpecialBufs(-1)<CR>

"map <silent> <unique> <script> 
"  \ <Plug>BufNextNormal 
"  \ :call <SID>BufNext_SkipSpecialBufs(1)<CR>
"map <silent> <unique> <script> 
"  \ <Plug>BufPrevNormal 
"  \ :call <SID>BufNext_SkipSpecialBufs(-1)<CR>
""   2. Thunk the <Plug>
function s:BufNext_SkipSpecialBufs(direction)
  let start_bufnr = bufnr("%")
  let done = 0
  while done == 0
    if 1 == a:direction
      execute "bn"
    elseif -1 == a:direction
      execute "bN"
    endif
    let n = bufnr("%")
    "echo "n = ".n." / start_bufnr = ".start_bufnr." / buftype = ".getbufvar(n, "&buftype")
    "if (getbufvar(n, "&buftype") == "")
    "    echo "TRUE"
    "endif
     " Just 1 buffer or none are editable
    "if (start_bufnr == n)
    "      \ || ( (getbufvar(n, "&buftype") == "")
    "        \   && ( ((getbufvar(n, "&filetype") != "")
    "        \       && (getbufvar(n, "&fileencoding") != ""))
    "        \     || (getbufvar(n, "&modified") == 1)))
" FIXME Diff against previous impl
" FIXME Doesn't switch to .txt --> so set filetype for *.txt? another way?
    if (start_bufnr == n)
        \ || (getbufvar(n, "&modified") == 1)
        \ || ( (getbufvar(n, "&buftype") == "")
        \   && ((getbufvar(n, "&filetype") != "")
        \     || (getbufvar(n, "&fileencoding") != "")) )
      " (start_bufnr == n) means just 1 buffer or no candidates found
      " (buftype == "") means not quickfix, help, etc., buffer
      " NOTE My .txt files don't have a filetype...
      " (filetype != "" && fileencoding != "") means not a new buffer
      " (modified == "modified") means we don't skip dirty new buffers
      " HACK Make sure previous buffer works
      execute start_bufnr."buffer"
      execute n."buffer"
      let done = 1
    endif
  endwhile
endfunction

" NOTE Change :bn to :tabn and :bN to :tabN 
"      if you'd rather have your tabs back

" Ctrl-Shift-Up/Down Jumps Windows
" --------------------------------

" This is Ctrl-Shift-Down to Next Window
noremap <C-S-Down> <C-W>w
inoremap <C-S-Down> <C-O><C-W>w
cnoremap <C-S-Down> <C-C><C-W>w
onoremap <C-S-Down> <C-C><C-W>w

" And this is Ctrl-Shift-Up to Previous Window
noremap <C-S-Up> <C-W>W
inoremap <C-S-Up> <C-O><C-W>W
cnoremap <C-S-Up> <C-C><C-W>W
onoremap <C-S-Up> <C-C><C-W>W

" Karma's an Itch
" --------------------------------
" We taketh, and we giveth.
" Re-map next and previous tab, since we 
" took away Ctrl-PageUp/Down earlier.

" This is Alt-PageDown to Next Tab Page
" NOTE gt is the Normal mode shortcut
" 2012.06.26: [lb] Does anyone use Tabs ever?
noremap <M-PageDown> :tabn<CR>
inoremap <M-PageDown> <C-O>:tabn<CR>
cnoremap <M-PageDown> <C-C>:tabn<CR>
onoremap <M-PageDown> <C-C>:tabn<CR>

" This is Alt-PageUp to Previous Tab Page
" NOTE gT is the Normal mode shortcut
noremap <M-PageUp> :tabN<CR>
inoremap <M-PageUp> <C-O>:tabN<CR>
cnoremap <M-PageUp> <C-C>:tabN<CR>
onoremap <M-PageUp> <C-C>:tabN<CR>

" --------------------------------
"  EditPlus // Special Windows
" --------------------------------

" EditPlus maps Alt-Shift-1..3 to three special 
" windows:
"   1. The so-called Cliptext window, which shows 
"      a list of ANSI characters;
"   2. The Directory window, which shows you your 
"      files; and
"   3. The Output window, which shows search   
"      results.

" NOTE It's not <M-S-1> or <M-S-2>, etc., 
"      but rather <M-!> and <M-@>, etc.... 

" Alt-Shift-1 // Toggle Cliptext
" --------------------------------
" EditPlus has a cool ANSI chart you can bring up 
" quickly (who isn't always referring to ANSI 
" charts?). Our Vim substitute is an even 
" awesomer interactive ASCII table by Christian 
" Habermann.
" NOTE Does not work: nnoremap <M-!> <Leader>ct
nmap <M-!> <Leader>ct
imap <M-!> <C-o><Leader>ct<ESC>
" TODO imap does not restore i-mode when ct done
" NOTE Modified chartab.vim to alias <ESC> and 
"      <M-!> to 'q'
" NOTE chartab.vim opens in new buffer in same 
"      window, rather than creating new vertical 
"      window on left of view and opening there
"      NOTE You can work-around by opening in 
"           QFix window
"           i.e., Alt-Shift-2 followed by 
"                 Alt-Shift-1

" Alt-Shift-2 // Toggle Mini Buffer Explorer
" --------------------------------
" First, configure MiniBufExplorer
" to show up just above the status line
" (at the bottom of the gVim window, 
"  rather than at the top)
let g:miniBufExplSplitBelow = 1
" The next variable causes MiniBufExplorer to 
" auto-load when N eligble buffers are visible;
" this is distracting in Gvim, so I set it to 
" 1 to auto-open at first, but this also doesn't 
" work well from the command line with just Vim, 
" so we check our environment first
if has("gui_running")
  let g:miniBufExplorerMoreThanOne = 1
else
  let g:miniBufExplorerMoreThanOne = 2
endif
" Instead of double-click, single-click to switch to buffer
let g:miniBufExplUseSingleClick = 1
" Start w/ minibufexpl off
" TODO BROKEN It starts with Command-line Vim, whaddup...?
"      (Meaning you gotta :q twice to exit, since the first 
"       :q just closes the MiniBufExpl window)
let s:MiniBufExplPath = ""
" NOTE I can't find any other place this is used, but 
"      set MiniBufExplLoaded to -1 so MBE loads for gVim
"      but not for terminal Vim (tVim?)
let s:MiniBufExplLoaded = -1
let s:MiniBufExplFile = "minibufexpl.vim"
if filereadable($HOME . "/.vim/plugin/" 
                \ . s:MiniBufExplFile)
  " $HOME/.vim is just *nix
  let s:MiniBufExplPath = $HOME 
    \ . "/.vim/plugin/" . s:MiniBufExplFile
elseif filereadable($USERPROFILE 
                    \ . "/vimfiles/plugin/" 
                    \ . s:MiniBufExplFile)
  " $HOME/vimfiles is just Windows
  let s:MiniBufExplPath = $USERPROFILE 
    \ . "/vimfiles/plugin/" 
    \ . s:MiniBufExplFile
"elseif
  " TODO What about Mac? Probably just 
  "      like *nix, right?
elseif filereadable($VIMRUNTIME 
                    \ . "/plugin/" 
                    \ . s:MiniBufExplFile)
  " $VIMRUNTIME works for both *nix and Windows
  let s:MiniBufExplPath = $VIMRUNTIME 
    \ . "/plugin/" . s:MiniBufExplFile
endif
execute "source " . s:MiniBufExplPath
autocmd VimEnter * nested
    \ let greatest_buf_no = bufnr('$') |
    \ if (greatest_buf_no == 1) 
    \     && (bufname(1) == "") |
    \   execute "CMiniBufExplorer" |
    \ endif

" New 2011.01.13: Smart toggle. If you don't do this and your Quickfix window
" is open, toggling the minibuf window will make the Quickfix window taller.
"   The old way:
"     nmap <M-@> <Plug>TMiniBufExplorer
"     imap <M-@> <C-O><Plug>TMiniBufExplorer
"     "cmap <M-&> <C-C><Plug>HCT_ToggleLookup<ESC>
"     "omap <M-&> <C-C><Plug>HCT_ToggleLookup<ESC>

nmap <M-@> :call <SID>ToggleMiniBufExplorer()<CR>
imap <M-@> <C-O>:call <SID>ToggleMiniBufExplorer()<CR>

" Opening and closing the MiniBufExplorer affects the heights of other
" windows, most notably the QuickFix window (if it's open). Specifically, 
" when the MiniBufExplorer is closed and the QuickFix window is visible, 
" rather than the QuickFix window decreasing it size, it expands to include 
" the rows abandoned by the MiniBufExplorer. Thusly, toggling the
" MiniBufExplorer a number of times causes the QuickFix to grow until it 
" consumes the whole screen, because the QuickFix window isn't resized when
" the MiniBufExplorer window is opened (the windows above it are, which are
" probably the windows your code is in). So we have to toggle smartly -- if 
" we're closing the MiniBufExplorer window, we should restore the height of
" the QuickFix window so that it doesn't grow wildly out of control.

function! s:ToggleMiniBufExplorer()
  let l:mbeBufnr = bufnr('-MiniBufExplorer-')
  let l:restore_quick_fix_height = 0
  if IsQuickFixShowing() && mbeBufnr != -1
    " Both QuickFix and MiniBufExpl are visible; after we 
    " hide MiniBufExpl, we need to fix the QuickFix height
    let save_winnr = winnr()
    copen
    let g:jah_Quickfix_Win_Height = winheight(winnr())
    let l:restore_quick_fix_height = 1
  endif
  " Toggle the MiniBufExpl window
  TMiniBufExplorer
  " Restore the QuickFix window height
  if l:restore_quick_fix_height > 0
    copen
    exe "resize " . g:jah_Quickfix_Win_Height
    execute save_winnr . 'wincmd w'
  endif
endfunction

" FIXME Toggling minibufexplorer in insert mode marks current buffer dirty
"       2011.01.18 I noticed this yesterday but today I'm not seeing it...

" Alt-Shift-3 // Toggle Search Results
" --------------------------------
" Or, in Vim terms, quickfix window
" BUGBUG Sometimes after closing quickfix
"        toggling the window no longer 
"        works (you'll see :QFix in the 
"        command-line window but nothing
"        happens). For now, just use 
"        :copen to force it open, then 
"        toggling works again.
" (Note: It's M-#, not M-S-3)
nnoremap <M-#> :QFix(0)<CR>
inoremap <M-#> <C-O>:QFix(0)<CR>
"cnoremap <M-#> <C-C>:QFix<CR>
"onoremap <M-#> <C-C>:QFix<CR>

" TODO Alt-Shift-4 // Toggle Project Browser
" --------------------------------
" EditPlus doesn't necessarily have an 
" Alt-Shift-4 mapping, but it does have 
" a Project menu. This is similar. But 
" better. =)

"let g:proj_window_width=30 " Default project window width
"let g:proj_window_width=3 " Default project window width
let g:proj_window_width=33 " Default project window width
"let g:proj_window_width=36 " Default project window width
"let g:proj_window_width=39 " Default project window width

" Remove the 'b' project flag, which uses browse() when handling 
" the \C command. Problem is, I cannot select a directory (it 
" always open the directory), so just use a simple edit box instead.
let g:proj_flags='imst' " Default was 'imstb', but browse() in Fedora is wonky

" NOTE noremap does not work
nmap <silent> <M-$> <Plug>ToggleProject_Wrapper
imap <silent> <M-$> <C-O><Plug>ToggleProject_Wrapper
"cmap <silent> <M-$> <C-C><Plug>ToggleProject
"omap <silent> <M-$> <C-C><Plug>ToggleProject

map <silent> <unique> <script> 
  \ <Plug>ToggleProject_Wrapper 
  \ :call <SID>ToggleProject_Wrapper()<CR>
"   2. Thunk the <Plug>
function s:ToggleProject_Wrapper()
  let save_winnr = winnr()
  if !exists('g:proj_running') || bufwinnr(g:proj_running) == -1
    " the Project adds itself as the first window, so 
    " we need to increase winnr by 1 to find our current 
    " window again
    let save_winnr = save_winnr + 1
    "let filename = '~/.vimprojects'
    "Project()
    "Project('~/.vimprojects')
    execute "ToggleProject"
  else
    " Otherwise, we're losing the first window, so 
    " compensate for the loss by subtracting one
    let save_winnr = save_winnr - 1
    " Clear the project buffer
    "execute bufwinnr(g:proj_running) . 'wincmd w'
    "bwipeout
    "
    execute "ToggleProject"
    " 2011.06.14: This is what ToggleProject does:
    "let g:proj_mywindow = winnr()
    "Project
    "hide
    "if(winnr() != g:proj_mywindow)
    "  wincmd p
    "endif
    "unlet g:proj_mywindow
  endif
  "execute "ToggleProject"
  " FIXME This behaviour does not belong here: Use Alt key modifier or another 
  "       key combo to close all folds but the first and jump to the top,
  "       otherwise, save the position the user was at, which supports the 
  "       work flow method of C-S-4'ing to see the list of files, opening a 
  "       file, and then closing the sidebar.
  "if exists('g:proj_running') && bufwinnr(g:proj_running) == 1
  "  " Collapse all folds
  "  execute 'normal ' . 'zM'
  "  " Return to top of window
  "  execute 'normal ' . 'gg'
  "  " Jump to first fold ... 
  "  execute 'normal ' . 'zj'
  "  " ... and open it
  "  execute 'normal ' . 'zA'
  "  " Now when the user closes the first fold, all others are visible
  "endif

  " 2011.01.15 On my laptop, I can't have the project window open and also
  "            look at two buffers side-by-side with at least 80 columns each, 
  "            unless if I dismiss the project window. But that messes up the 
  "            widths of my windows. Hence, we do a little dance.
  "
  " First, see how many columns we have to work with.
  let cols_avail = &columns
  if exists('g:proj_running') && bufwinnr(g:proj_running) == 1
    let cols_avail = cols_avail - g:proj_window_width
  endif
  "
  " Next, see if two buffers are open, and figure out which windows they're in.
  " Hint: the way dubsacks sets it up, the Project window (file browser) is on 
  " the left, and the buffer explorer and quickfix window are on the bottom.
  " That leaves one or two windows that the user is editing in the upper-right.
  " If there are two windows, they're either side-by-side or stacked depending
  " on how much room is available.
  let winnr_lhs = 0
  let winnr_rhs = 0
  if !exists('g:proj_running') || bufwinnr(g:proj_running) == -1
    " The project window is not showing, so the user's windows are the first
    " and maybe the second window (since Vim numbers windows 1, 2, 3, ..., from
    " left to right and top to bottom
    if ( (0 == <SID>IsWindowSpecial(1))
        \ && (0 == <SID>IsWindowSpecial(2))
        \ && (0 != <SID>IsWindowSpecial(3)) )
      let winnr_lhs = 1
      let winnr_rhs = 2
    endif
  else
    " The project window is showing, so the user's window(s) are the second and
    " maybe the third window(s)
    if ( (0 == <SID>IsWindowSpecial(2))
        \ && (0 == <SID>IsWindowSpecial(3))
        \ && (0 != <SID>IsWindowSpecial(4)) )
      let winnr_lhs = 2
      let winnr_rhs = 3
    endif
  endif
  "
  " If the user is editing using two windows, resize and reposition the windows
  " to the pleasurement of all
  if winnr_lhs != 0 && winnr_rhs != 0
    " Switch to the second window, remember its buffer, and close the window
    execute winnr_rhs . 'wincmd w'
    let bufnr = winbufnr("%")
    close
    " Switch back to the first window and split it
    execute winnr_lhs . 'wincmd w'
    " Split the window either vertically or horizontally, depending on the
    " amount of room available and if the project window is showing.
    " NOTE We closed a window and use to (v)split to make a new window, 
    "      which automatically sizes each window similarly. If we didn't 
    "      close the window and instead wanted to resize each window
    "      manually, we'd call
    "         let half_width = &columns / 2
    "         execute 'vertical resize ' . half_width
    " Hack alert! winnr_lhs is 1 if project window isn't showing, 2 otherwise
    if winnr_lhs == 1 || cols_avail > 160
      " Split vertically
      execute 'vsplit'
    else
      " Split horizontally
      execute 'split'
    endif
    " Switch back to the (newly-created) second window and load the
    " remembered buffer
    execute winnr_rhs . 'wincmd w'
    execute "buffer " . bufnr
  endif

  " Move cursor back to window it was just in
  execute save_winnr . 'wincmd w'

endfunction

" Test if a window is the Help, Quickfix, MiniBufExplorer, or Project window
function! s:IsWindowSpecial(window_nr)
  let is_special = 0
  if (-1 == winbufnr(a:window_nr))
    let is_special = -1
  else
    let buffer_nr = winbufnr(a:window_nr)
    if ( (-1 != buffer_nr)
        \ && ( (getbufvar(buffer_nr, "&buftype") == "help")
          \ || (getbufvar(buffer_nr, "&buftype") == "quickfix")
          \ || (bufname(buffer_nr) == "-MiniBufExplorer-")
          \ || ( (exists('g:proj_running')) 
              \ && (a:window_nr == bufwinnr(g:proj_running)) ) ) )
      " FIXME There's probably an easy way to check if a window/buffer is normal
      let is_special = 1
    endif
  endif
  return is_special
endfunction

" Alt-Shift-5 // Toggle HTML Char Table
" --------------------------------
" This also isn't in EditPlus, but it's 
" similar to the Alt-Shift-1 Cliptext 
" window, only this window shows you 
" HTML Character Entity translations.
" (Note: It's M-%, not M-S-5)
nmap <M-%> <Plug>HCT_ToggleLookup
imap <M-%> <C-O><Plug>HCT_ToggleLookup<ESC>
"cmap <M-%> <C-C><Plug>HCT_ToggleLookup<ESC>
"omap <M-%> <C-C><Plug>HCT_ToggleLookup<ESC>

" Alt-Shift-6 // Toggle Tag List
" --------------------------------
" Show the ctags list.
nmap <M-^> :TlistToggle<CR>
imap <M-^> <C-O>:TlistToggle<CR>
"cmap <M-^> <C-C>TlistToggle<ESC>
"omap <M-^> <C-C>TlistToggle<ESC>

" Alt-Shift-7 // Toggle File Browser
" --------------------------------
" NERDTree to the rescue.
" (Note: It's M-@, not M-S-2)
" NOTE Disabled; I don't use NERDTree! 2010.06.14
"      I've been grooving on the Project plugin instead.
"noremap <M-@> :NERDTreeToggle<CR>
"inoremap <M-@> <C-O>:NERDTreeToggle<CR>
""cnoremap <M-@> <C-C>:NERDTreeToggle<CR>
""onoremap <M-@> <C-C>:NERDTreeToggle<CR>

" ------------------------------------------
" ----------------------------------- EOF --

" http://www.moolenaar.net/habits.html
" * Use % to jump from an open brace to its matching closing brace. Or from a "#if" to the matching "#endif". Actually, % can jump to many different matching items. It is very useful to check if () and {} constructs are balanced properly.
" * Use [{ to jump back to the "{" at the start of the current code block.
" * Use gd to jump from the use of a variable to its local declaration.
" Very often you will want to change one word into another. If this is to be done in the whole file, you can use the :s (substitute) command. If only a few locations needs changing, a quick method is to use the *  command to find the next occurrence of the word and use cw  to change the word. Then type n to find the next word and .  (dot) to repeat the cw command.


" FIXME Search/replace all quickfix files
"       This might be like :Vimgrep?
"       You can use :cnf to get close to easily opening all qf, then use :gr to
"       find/replace
"function Openall()
"  edit <cfile>
"  bfirst
"endfunction

