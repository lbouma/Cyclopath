" This file is part of Dubsacks.
" --------------------------------
" Dubsacks is Copyright © 2009, 2010, 2011 Landon Bouma.
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
"  Vim startup script for Windows gVim.
" ------------------------------------------

" Author: Landon Bouma <dubsacks.vim@retrosoft.com>
" Version: 0.0.1 / Summer Aught Nine
" License: What License?

" NOTE!! If you edit this file, be sure to delete
"        ~/.vim/Session.vim or ~/vimfiles/Session.vim
"        (If you have dubsacks.vim loaded, you can 
"         also run <Alt-f>e to close all windows 
"         and then <Alt-f>x to quit; dubsacks will 
"         destroy Session.vim for you.)

" ------------------------------------------

" Once you're done, you're done
" --------------------------------
" NOTE This file gets sourced more than once 
"      when occupying the plugin directory (and 
"      I don't know why, also known as: "Just 
"      when you think you know Vim...!"), so set 
"      a flag telling ourselves when we've already
"      been loaded (a/k/a "had enough!")
if exists("plugin_dubsacks_vim")
  finish
endif
let plugin_dubsacks_vim = 1

" See what OS we're on
" --------------------------------
let s:running_windows = has("win16") || has("win32") || has("win64")

if !s:running_windows
  let s:user_vim_dir = $HOME . "/.vim"
else
  let s:user_vim_dir = $HOME . "/vimfiles"
endif

" Enable syntax highlighting
" --------------------------------
" This is enabled by default in Windows
" but not Linux
syntax enable

" I want Ctrl-C/-V and to be able to 
" highlight text with the shift and 
" arrow keys in insert mode
" --------------------------------
" Caveats
" - Visual mode is CTRL-Q instead of CTRL-V
"   (You can also quadruple-click to select by row,column!)
" - Backspace and cursor keys wrap to previous/next line,
"   rather than sounding the system bell (an-noy'ing!)
" - CTRL-X and SHIFT-Del are Cut
" - CTRL-C and CTRL-Insert are Copy
" - CTRL-V and SHIFT-Insert are Paste
" - Use CTRL-Q to do what CTRL-V used to do
" - Use CTRL-S for saving, also in Insert mode
" - CTRL-Z is Undo; not in cmdline though
" - CTRL-Y is Redo (although not repeat); not in cmdline though
" - Alt-Space is System menu
" - CTRL-A is Select all
" - CTRL-Tab is Next window
" - CTRL-F4 is Close window
if !s:running_windows
  source $VIMRUNTIME/mswin.vim
  behave mswin
endif

" Delete default Vim buffer
" --------------------------------
" If you're not already running gVim and you 
" double-click a file from Explorer, (or run 
" gVim from the command line), gVim opens your 
" file, but also opens a nameless buffer (and 
" then hides it when your file is opened).
" You'd think this wouldn't be the default,
" or there'd be a way to stop it, but, alas...
" I guess we're responsible for cleaning up 
" this mess.
let s:CleansedBufList = 0
function! s:CleanseBufList(bang)
  let last_buffer = bufnr('$')
  let delete_count = 0
  let n = 1
  echomsg "CleansedBufList: last_buffer:" last_buffer
  sleep 2000
  if last_buffer > 0
     while n <= last_buffer
       " NOTE I'm assuming when we restore Session.-
       "      vim that there's just one unnamed 
       "      buffer and that it's the empty one 
       "      created on startup. However, I could 
       "      be wrong (I haven't verified this 
       "      through reading the help), so who 
       "      knows if this ever might fail (if 
       "      which case your documents don't get 
       "      opened -- whatever, so you just fix 
       "      this script and know that I was wrong 
       "      to assume).
       try
         if (buflisted(n))
            \ && (bufname(n) == "")
            \ && (getbufvar(n, "&mod") == 0)
            " You can run the command, &modifed, to check if the current buffer
            " is modified, or you can use getbufvar on any buffer.
            " 2014.02.04: See comments before autocmd SessionLoadPost
            "   call this fcn: This bdelete can cause Vim to enter an
            "   infinite loop if your Session.vim isn't cleared
            "   properly...
           execute "bdelete" . a:bang . ' ' . n
           if ! buflisted(n)
             let delete_count = delete_count + 1
           endif
         endif
       catch /.*/
         echomsg "CleansedBufList thrown.  Value is" v:exception
       endtry
       let n = n + 1
     endwhile
  endif
  " Pretty-print a message 'splaining whaddup
  if delete_count == 1
    let plural = ""
  else
    let plural = "s"
  endif
  echomsg "CleansedBufList: " . delete_count 
    \ . " buffer" . plural . " deleted"
  " Remember that we've cleansed
  let s:CleansedBufList = 1
endfunction

" Run CleanseBufList just once, right 
" after we start and load Session.vim
" 2014.02.04: This doesn't work well.
"   To see it: cd to an svn directory.
"   Run: svn diff | gvim -
"   Type Alt-F+E then Alt-F+X to exit.
"   The Alt-F+E doesn't do it's all because
"   the diff buffer is modified/unsaved.
"   So when you exit without saving and start
"   Vim again, either the file doesn't show,
"   or, worse yet, Vim gets stuck in a loop
"   somewhere...
"autocmd SessionLoadPost * nested
"  \ if 0 == s:CleansedBufList |
"  \   :call <SID>CleanseBufList('') |
"  \ endif |
"  \ let s:CleansedBufList = 1
" And how come I never seen a tip fer this
" on-line, eh, vim.org? eh, vim.wikia.com?
" 'cause usually when I can't Google something... 
" it means I'm wrong! ...but I digress... 
" (seriously, I'm probably just missing a 
"  setting somewhere...)

" Restore previous session on open
" --------------------------------
" Inspired by
"   http://vim.wikia.com/wiki/Open_the_last_edited_file

" Save current session on exit
" --------------------------------
" NOTE Vim's default is to set 
"        sessionoptions=blank,buffers,curdir,
"          \ folds,help,options,tabpages,winsize
"      which means we can't update _this_ file 
"      without first deleting ~/.vim/Session.vim 
"      or ~/vimfiles/Session.vim -- otherwise, 
"      Session.vim overrides any changes we make 
"      here (because it stores mappings, etc., 
"      and is loaded after this file). 
"      Alternatively, we could set 
"      sessionoptions to save only winsize, 
"      buffers, etc., but not options: though I 
"      haven't tested this, so for now: delete 
"      Session.vim if you m*ck w//touch this 
"      fi#e.
" NOTE I still haven't figured out unloaded/
"      hidden buffers, such that :Bclose all and 
"      restarting Vim starts with the buffers
"      you just closed -- as a kludge, we'll 
"      just not re-write the session file if 
"      <Alt-f>e was just called.
autocmd VimLeave * nested 
  \ let last_buffer = bufnr('$') |
  \ let num_buffers = 0 |
  \ let empty_buffers = 0 |
  \ let n = 1 |
  \ while n <= last_buffer |
  \   if (buflisted(n)) |
  \     let num_buffers = num_buffers + 1 |
  \     if (bufname(n)== "") |
  \       let empty_buffers = empty_buffers + 1 |
  \     endif |
  \   endif |
  \   let n = n + 1 |
  \ endwhile |
  \ if (num_buffers == 1) 
  \     && (empty_buffers == 1) |
  \   call delete(
  \     s:user_vim_dir . "/Session.vim") |
  \ else |
  \   if (!isdirectory(s:user_vim_dir)) |
  \     call mkdir(s:user_vim_dir) |
  \   endif |
  \   execute "mksession! " . 
  \     s:user_vim_dir . "/Session.vim" |
  \ endif

" Restore previous session on startup
" --------------------------------
" ... but not if specifically opening a file; in 
" other words, just restore the previous session 
" if user clicked gVim.exe, but not some dumb 
" text file.
" NOTE (argc() == 0) is true even when double-
"      clicking from Explorer, so it's not a 
"      reliable indicator of whether a file is 
"      being opened (as the aforementioned wikia.
"      com link may lead you to believe); 
"      rather, 
autocmd VimEnter * nested
    \ let greatest_buf_no = bufnr('$') |
    \ if (greatest_buf_no == 1) 
    \     && (bufname(1) == "") 
    \     && filereadable(
    \       s:user_vim_dir . "/Session.vim") |
    \   execute "source " . 
    \     s:user_vim_dir . "/Session.vim" |
    \ endif

" ------------------------------------------
"  The Basics
" ------------------------------------------

" It's Courier New 9, Folks!
" --------------------------------
if has("gui_running")
  " How come Courier New isn't the default?
  if s:running_windows
    set guifont=Courier_New:h9
  else
    " set guifont=Courier\ New\ 9
    " NOTE In Debian, just setting guifont makes 
    "      things look like shit; not sure why this 
    "      doesn't happen in Fedora. Anyway, comment
    "      this out or unset guifont to fix font issues.
    "      ... or don't run Debian!
    set guifont=Bitstream\ Vera\ Sans\ Mono\ 9
  endif
  " Get rid of silly, space-wasting toolbar
  " Default is 'egmrLtT'
  set guioptions=egmrLt
  " Hide the mouse pointer while typing
  " NOTE This does not hide the mouse in
  "      Windows gVim, so it's off! for now
  "set mousehide
endif

" Show line numbers
" --------------------------------
set nu!

" Pretty Print
" --------------------------------
" Change the color of the line numbers
" from deep red (default) to dark grey
" (it's less abusive to the eye this way).
:highlight LineNr term=NONE cterm=NONE
  \ ctermfg=DarkGrey ctermbg=NONE gui=NONE
  \ guifg=DarkGrey guibg=NONE
" 2012.09.21: Add colors for :list. See :h listchars. You can show whitespace.
" Hmmm, the trail:~ puts tildes after the last line number... kinda weird lookn
" set listchars=eol:$,tab:>-,trail:~,extends:>,precedes:<
:highlight SpecialKey term=NONE cterm=NONE
  \ ctermfg=DarkGrey ctermbg=NONE gui=NONE
  \ guifg=DarkGrey guibg=NONE
" FIXME: 2012.09.21: This isn't working from here: you can manually 
" :set list and then :highlight... and the whitespace chars are shown 
" in the same gray as the line numbers, but if you just :set list, the 
" whitespace chars don't appear, even with the same highlight here....
:highlight NonText term=NONE cterm=NONE
  \ ctermfg=DarkGrey ctermbg=NONE gui=NONE
  \ guifg=DarkGrey guibg=NONE
":highlight NonText term=NONE cterm=NONE ctermfg=DarkGrey ctermbg=NONE gui=NONE guifg=DarkGrey guibg=NONE
" Default to not showing whatspace.
set nolist

" What Are You Hiding From Me?
" --------------------------------
" Show new buffers w/ all folds open
" (See http://vim.wikia.com/wiki/Folding)
" TODO can i use autocmd BufAdd * ?? <C-a><C-o>zO
"      'cause foldlevelstart=20 isn't bullet-
"       proof ??
set foldlevelstart=20

" Start Big
" --------------------------------
" Start with a reasonably sized window for GUIs
" (ignore for CLI so we don't change terminal size)
if has("gui_running")
  " winpos 100 100
  " set columns=111 lines=44
  " 2010.06.24 Work config:
  " FIXME Home config; if 'fa', winpos 0 0 ?
  winpos 718 0
  set columns=121 lines=68
endif
" NOTE To start maximized:
"      au GUIEnter * simalt ~x

" Search Behavior
" --------------------------------
" Case-insensitive searches
" 2012.07.15: My old comment says, 
"               NOTE /You can override this with/I
"             But it's really \c or \C that you want,
"               /\CCase Sensitive Incremental Search
"             You can put the '\C' wherever you want.
"             (The \c does lowercase, \CDUH.)
"             See :h ignorecase
set ignorecase
" Better yet, search case sensitive if the
" search term contains a capital letter
set smartcase
" These should be set by default:
"   set hlsearch  " Highlight search terms
"   set incsearch " search dynamically as keyword is typed
" but on my Ubuntu box, unlike Windows, they're not, so
set hlsearch  " Highlight search terms
set incsearch " search dynamically as keyword is typed

" Common Backup file and Swap Directory
" --------------------------------
" Use a common directory for backups and 
" swp files; creates the backup dir if new
let s:backupDir = '"' . $HOME . '/.vim_backups' . '"'
silent execute "let s:backupFtype = getftype(" . s:backupDir . ")"
if "" == s:backupFtype
  silent execute '!mkdir ' . s:backupDir
elseif "dir" != s:backupFtype
  call confirm('Backup directory exists but is not a directory! '
    \ . 'Dir: ' . s:backupDir . ' / Type: ' . s:backupFtype)
endif
set backupdir=$HOME/.vim_backups/
set directory=$HOME/.vim_backups/

" Skip Backups
" --------------------------------
" Backups are only written when you save a 
" file, anyway, so I don't see the point
" (I save all the time: I'm from the old-school
"  '80s and '90s camp, sans journaling file systems,
"  where if ya crashed, ya crashed, and all yer data
"  went away!).
" Additionally, Vim maintains ~/.vim_backups, so
" if Vim crashes, you're fine.
" Basically: use revision control for "backups".
set nobackup

" Drop a Deuce on that Tab
" --------------------------------
" Anyone out there still tabbing?
" How 'bout you spacers using 4?
" Seems the Rubyists have got me 
" down to 2... what's next, reverse
" indenting?
set expandtab
set tabstop=2
set shiftwidth=2
set autoindent
" smartindent is too smart and doesn't 
" indent lines that look like C macros,
" i.e., those that start with an octothorpe;
" if you hit return, get an indent, type '#',
" smartindent moves the pound to the start of 
" the line (this might just be with .py files, 
" not sure...)
" set smartindent
" FIXME 2011.01.17 I think this problem no longer happens...
"       so setting smartindent instead
"set nosmartindent
set smartindent
"set smarttab

autocmd BufRead *.vim set tabstop=2
autocmd BufRead *.vim set shiftwidth=2

" Something Something Something
" --------------------------------
" NOTE I thought autowrite was suppose to 
"      cause the buffer to be written to disk 
"      whenever you changed buffers, but it 
"      doesn't really seem to do anything...
"set autowrite

" Enable Vim Command-line Completion
" --------------------------------
" Can't remember a command's proper name?
" Hit <Tab> (!)
set wildmenu

" Always show a status line
" --------------------------------
au VimEnter * set laststatus=2

" All Quiet on the Vimmer Front
" --------------------------------
" I tried noerrorbells and novisualbell to
" no avail, but this seems to do the trick.
set vb t_vb=

" Windows Grep Complaint Silencer
" ------------------------------------------
" Windows gVim complains when you grep using a path 
" with backslashes in it... not sure why it complains 
" since it doesn't actually do anything about it.
if has("gui_win32")
  silent !set nodosfilewarning=1
endif

" Always sort the Quickfix list
" --------------------------------
" http://vim.wikia.com/wiki/Automatically_sort_Quickfix_list

function! s:CompareQuickfixEntries(i1, i2)
  if bufname(a:i1.bufnr) == bufname(a:i2.bufnr)
    return a:i1.lnum == a:i2.lnum ? 0 : (a:i1.lnum < a:i2.lnum ? -1 : 1)
  else
    return bufname(a:i1.bufnr) < bufname(a:i2.bufnr) ? -1 : 1
  endif
endfunction

function! s:SortUniqQFList()
  let sortedList = sort(getqflist(), 's:CompareQuickfixEntries')
  let uniqedList = []
  let last = ''
  for item in sortedList
    let this = bufname(item.bufnr) . "\t" . item.lnum
    if this !=# last
      call add(uniqedList, item)
      let last = this
    endif
  endfor
  call setqflist(uniqedList)
endfunction

" 2014.01.31: [lb] moved from Vim 7.3 and Vim 7.4, from Fedora 14
"             to Linux Mint 16, and now this fcn. messes up our
"             Cyclopath <F7> function, which is to open the flash
"             log file. In latter Vim, it opens the log, but it
"             _only_ shows matching entries, i.e., errors and
"             their files and line numbers, but the rest of the
"             log file is omitted. How can I debug easily without
"             my trace messages?
"             Anyway, this feature is silly: we don't need to sort
"             the quickfix list and remove duplicates, since we're
"             inspecting log files and not, e.g., well, I don't
"             know what the use case of this feature is.
"autocmd! QuickfixCmdPost * call s:SortUniqQFList()

" ------------------------------------------
"  Dealing with Buffers
" ------------------------------------------

" I tried minibufexpl, bufman, and bufferlist:
"   http://www.vim.org/scripts/script.php?script_id=159
"   http://www.vim.org/scripts/script.php?script_id=875
"   http://www.vim.org/scripts/script.php?script_id=1325
"   :(respectively)
" but this is simply the best
function! s:SimplBuffrListr()
  " Show all buffers, one per line, in the 
  " command-line window (which expands upward 
  " as needed, and disappears when finished)
  " TODO I've never tested w/ more buffers than 
  "      screen lines -- is there a More/Enter-to-
  "      Continue prompt?
  :buffers
  " Ask the user to enter a buffer by its number
  let i = input("Buffer number: ")
  " Check for <ESC> lest we dismiss a help 
  " page (or something not in the buffer list)
  if i != ""
   execute "buffer " . i
  endif
endfunction
" Map a double-underscore to the simpl(e) 
" buffe(r) liste(r)
map <silent> __ :call <SID>SimplBuffrListr()<CR>
" NOTE to the wise: tabs? tabs?! who needs tabs!!?
"      buflists? buflists?! who needs buflists!!?
"      serlussly, pound a double-underscore every
"      once 'n a while, but keep yer doc names 
"      outta me face. #foccers

" ------------------------------------------
"  Quickfix Toggle
" ------------------------------------------
"   http://vim.wikia.com/wiki/Toggle_to_open_or_close_the_quickfix_window
" (Quickfix is Vim's search results 
"  window, among other things.)
" TODO Make height settable or at least 
"      remember/restore between toggles
"let g:jah_Quickfix_Win_Height=14
let g:jah_Quickfix_Win_Height=8

command -bang -nargs=* QFix 
  \ :call <SID>QFixToggle(<bang>0, <args>)
function! <SID>QFixToggle(forced, tail_it)
  "call inputsave()
  "let TBD = input("forced: ". a:forced, " / tail_it: ". a:tail_it)
  "call inputrestore()
  let l:restore_minibufexp = s:IsMiniBufExplorerShowing()
  if (IsQuickFixShowing() && a:forced != 1) || a:forced == -1
    " Already showing and not being forced open, or being force closed
    if IsQuickFixShowing()
      call <SID>QFixToggle_Hide(l:restore_minibufexp)
    endif
  elseif (!IsQuickFixShowing() && a:forced != -1) || a:forced == 1
    " Not showing and not being forced-hidden, or being forced to show
    if !IsQuickFixShowing()
      call <SID>QFixToggle_Show(l:restore_minibufexp)
    endif
  endif
  if IsQuickFixShowing() && a:tail_it == 1
    " Scroll to the bottom of the Quickfix window 
    " (this is useful to see if there are any make errors)
    let save_winnr = winnr()
    copen
    normal G
    execute save_winnr . 'wincmd w'
  endif
endfunction

function! s:QFixToggle_Hide(restore_minibufexp)
  let save_winnr = winnr()
  copen
  let g:jah_Quickfix_Win_Height = winheight(winnr())
  "call inputsave()
  "let TBD = input("g:jah_Quickfix_Win_Height: ". g:jah_Quickfix_Win_Height)
  "call inputrestore()
  execute "CMiniBufExplorer"
  cclose
  if a:restore_minibufexp == 1
    execute "MiniBufExplorer"
  endif
  execute save_winnr . 'wincmd w'
endfunction

function! s:QFixToggle_Show(restore_minibufexp)
  let save_winnr = winnr()
  execute "CMiniBufExplorer"
  " The plain copen command opens the Quickfix window on the bottom of the
  " screen, but it positions itself underneath and makes itself as wide as the
  " right-most window. Fortunately, we can use botright to force copen to use 
  " the full width of the window.
  execute "botright copen " . g:jah_Quickfix_Win_Height
  if a:restore_minibufexp == 1
    execute "MiniBufExplorer"
  endif
  " NOTE For whatever reason, the previous call to MiniBufExplorer adds 4
  "      lines to the quickfix height, so we go back and fix it
  copen
  exe "resize " . g:jah_Quickfix_Win_Height
  execute save_winnr . 'wincmd w'
endfunction

" Used to track the quickfix window
" [lb] Not sure where I got this from, but 
"      BufWinLeave doesn't always execute, 
"      causing QFixToggle to jam and forcing 
"      the user to :copen manually
"      2011.01.17 Is this problem fixed? I haven't seen it in a while...
augroup <SID>QFixToggle
  autocmd!
  autocmd BufWinEnter quickfix 
    \ :let g:qfix_win = bufnr('$')
  autocmd BufWinLeave * 
    \ if exists("g:qfix_win") 
    \     && expand("<abuf>") == g:qfix_win | 
    \   unlet! g:qfix_win | 
    \ endif
augroup END
" 2010.02.24 Switching to simpler/more realiable

"command -nargs=0 IsQuickFixShowing 
"  \ :call <SID>IsQuickFixShowing()
"function! s:IsQuickFixShowing()
" Make this fcn. so other Vim scripts can use it
function! IsQuickFixShowing()
  let is_showing = 0
  let i = 1
  let currBufNr = winbufnr(i)
  while (currBufNr != -1)
    " If the buffer in window i is the quickfix buffer.
    if (getbufvar(currBufNr, "&buftype") == "quickfix")
      let is_showing = 1
      break
    endif
    let i = i + 1
    let currBufNr = winbufnr(i)
  endwhile
  return is_showing
endfunction

function! s:IsMiniBufExplorerShowing()
  let is_showing = 0
  let i = 1
  let currBufNr = winbufnr(i)
  while (currBufNr != -1)
    " If the buffer in window i is the quickfix buffer.
    if (bufname(currBufNr) == "-MiniBufExplorer-")
      let is_showing = 1
      break
    endif
    let i = i + 1
    let currBufNr = winbufnr(i)
  endwhile
  return is_showing
endfunction

" Toggle Annoyance
" --------------------------------
" When toggling the quickfix window,
" make sure it only increases/decreases
" the height of the window adjacent to 
" it (above it). Default Vim behavior 
" is to resize all window the same size.
set noequalalways

" ------------------------------------------
"  Find/Search/Replace/Substitute
" ------------------------------------------
" How many ways can you spell regexp?

" Ctrl-H Hides Highlighting
" --------------------------------
" Vim's default Ctrl-H is the same as <BS>.
" It's also the same as h, which is the 
" same as <Left>. WE GET IT!! Ctrl-H won't 
" be missed....
" NOTE Highlighting is back next time you search.
" NOTE Ctrl-H should toggle highlighting (not 
"      just turn it off), but nohlsearch doesn't 
"      work that way
noremap <C-h> :nohlsearch<CR>
inoremap <C-h> <C-O>:nohlsearch<CR>
cnoremap <C-h> <C-C>:nohlsearch<CR>
onoremap <C-h> <C-C>:nohlsearch<CR>
" (NEWB|NOTE: From Insert mode, Ctrl-o
"  is used to enter one command and 
"  execute it. If it's a :colon 
"  command, you'll need a <CR>, too.
"  Ctrl-c is used from command and
"  operator-pending modes.)

" Start Substitution Under Cursor
" --------------------------------
" Starts a substitution command on whatever
" the cursor's on.
" Usage: Highlight some text
"        Type Ctrl-o \s
" http://vim.wikia.com/wiki/Search_and_replace_the_word_under_the_cursor
" NOTE .,$ searches from the cursor to end of 
"      file; that's probably the best default...
:noremap <Leader>s "sy:.,$s/<C-r>s//gc<Left><Left><Left>

" Search and replace selected term all files listed in Quickfix
" ------------------------------------------
" This fcn. opens every file in the Quickfix list and does a bufdo, e.g., 
"    :bufdo .,$s/Search/Replace/g

" FIXME We could prompt for the replace term, but for now I just 
"       have the user complete the function call...
:noremap <Leader>S "sy:call <SID>QuickfixSubstituteAll("<C-r>s", "")<Left><Left>

" FIXME This fcn. requires the user to do an initial search. That is, this 
"       fcn. does not search the term being replaced, but rather just uses
"       the existing Quickfix error list
function s:QuickfixSubstituteAll(search, replace)
  "call confirm('Search for: ' . a:search . ' / ' . a:replace)
  " Remember the current buffer so we can jump back to it later
  let l:curwinnr = winnr()
  let l:curbufnr = winbufnr("%")
  " Remember if the Quickfix is currently showing so we can hide it
  let l:hide_quickfix = !(IsQuickFixShowing())
  " Open and jump to the Quickfix/error list
  copen
  " Make sure we're on the first line
  normal gg
  " Get some stats on the error list
  let l:first_line_len = col("$")
  let l:window_last_line = line("w$")
  let l:errors_exist = (l:window_last_line > 1) || (l:first_line_len > 1)
  " Make sure that's at least one error in the list
  if l:errors_exist
    " Open all the files listed, starting with the first file in the list
    cc! 1
    " Open the remaining files using a handy Quickfix command
    let l:line_num_cur = line(".")
    let l:line_num_prev = 0
    while l:line_num_cur != l:line_num_prev
      " The cnf command opens the next file listed in the error list, and it 
      " reports an error if there isn't a next file to open. We can suppress 
      " the error with a banged-silence command, and we can check if we've 
      " opened the last file by checking if the cursor has changed lines.
      silent! cnf
      " Make sure we jump back to the Quickfix window
      copen
      let l:line_num_prev = l:line_num_cur
      let l:line_num_cur = line(".")
    endwhile
    " Run the find/replace command on all the open buffers
    " NOTE If the user has buffers open that aren't in Quickfix, these 
    "      will also be run through this command
    "
    " First show the user how many matches there are
    " NOTE Moved to last call of fcn., otherwise the [b]buffer command 
    "      overwrites it, even with silent! in use
    copen
    normal gg
    " g - global (find all matches, not just one)
    " n - don't replace, just count matches
    " I - don't ignore care
    execute ".,$s/" . a:search . "/" . a:replace . "/gnI"
    "
    " Go back to the window the user was in, otherwise we'll open 
    " the buffers in the Quickfix window
    exe l:curwinnr . "wincmd w"
    " Perform the find/replace operation
    " e - skip errors (else it stops when it tries the Quickfix buffer)
    "execute "silent! bufdo .,$s/" . a:search . "/" . a:replace . "/geI"
    " NOTE The last command fails on "no modifiable", even though I 
    "      though the -e switch should get around that. Alas, it doesn't, 
    "      so go through the buffers the old fashioned way.
    bfirst
    let l:done = 0
    while !l:done
      if getbufvar(bufnr('%'), '&modifiable') == 1
        execute "silent! .,$s/" . a:search . "/" . a:replace . "/gI"
      endif
      bnext
      " We're done once we've processed the last buffer
      let l:done = bufnr("%") == bufnr("$")
    endwhile
  endif
  " Close Quickfix if it was originally closed
  if l:hide_quickfix
    " So, "s:QFixToggle(-1, 0)" does not work, but "call <SID>..." does
    call <SID>QFixToggle(-1, 0)
  endif
  " Go back to the window and buffer the user called us from
  exe l:curwinnr . "wincmd w"
  " Ug. This silent! doesn't work like if does when I just run it myself...
  "execute "silent! buffer! " . l:curbufnr
  silent! execute "buffer " . l:curbufnr
  " Print a status message
  if !l:errors_exist
    echo "Nothing to do: no errors in the Quickfix error list!"
  else
    " This is weird, but it's the only way I can figure out 
    " how to show the user how many changes were made
    " NOTE Calling :messages shows the whole message file, 
    "      which might be larger than a single page. Fortunately, 
    "      we can call g< to see just the last message, which 
    "      handles to be the s//gn call that gave us a count.
    execute "g<"
  endif
endfunction

" Grep Selection Under Cursor
" --------------------------------
" Starts a grep command on whatever
" the cursor's on.
" Usage: Highlight some text
"        Type Ctrl-o \g
" FIXME TODO This path is hard-coded
":noremap <Leader>g "sy:gr! "<C-r>s" "/home/pee/cp/cp"
":noremap <Leader>G "sy:gr! "<C-r>s" "/home/pee/cp/cp"

" Use Cygwin's grep (not Windows' findstr)
" --------------------------------
" Options we use:
"  -n makes grep show line numbers
"  -R recurses directories
"  -i --ignore-case
"  -E uses extended regexp (same as egrep) 
"       so that alternation (|) works, 
"       among other opts
"  --exclude-from specifies a file containing
"                 filename globs used to exclude
"                 files from the search
" Example Vim Grep command:
"  :grep "Sentence fragment" "C:\my\project\path"
if filereadable(
    \ $HOME . "/.vim/grep-exclude")
  " *nix
  set grepprg=egrep\ -n\ -R\ -i\ --exclude-from=\"$HOME/.vim/grep-exclude\"
elseif filereadable(
    \ $USERPROFILE . 
    \ "/vimfiles/grep-exclude")
  " Windows
  set grepprg=egrep\ -n\ -R\ -i\ --exclude-from=\"$USERPROFILE/vimfiles/grep-exclude\"
else
  call confirm('dubsacks.vim: Cannot find grep-xclude file', 'OK')
endif

" NOTE The grep exclude-from file *must* be saved 
"      in unix format 
"      i.e., if :set ff is 'dos', it won't work! 
"      so :set ff=unix
" NOTE The exclude-from file has one file glob 
"      per line, i.e.,
"        *.sql
"        *.skipme
"        *.etc
" TODO Is there a better way to specify filename 
"      globs than using a file? 
" TODO Make it easy to switch btw glob files
" TODO Make a command to manage one or more 
"      filename glob files and switch between
"      them
" TODO Add a command for non-recursive searching
" TODO Multiple Quickfix search results windows?

" ------------------------------------------
"  Macros
" ------------------------------------------
" Think of 'em as personal assistants:
" show 'em it once, then have them repeat.

" Single-Key Replays with Q
" --------------------------------
" This is a shortcut to playback the recording in 
" the q register.
"   1. Start recording with qq
"   2. End recording with q (or with 
"      Ctrl-o q if in Insert mode)
"   3. Playback with Q
noremap Q @q

" ------------------------------------------
"  Color Scheme 
" ------------------------------------------
" I like the White background that the default 
" color scheme uses, but the color scheme still 
" needs a little tweaking.

" Tone down the tildes
" --------------------------------
" Vim displays tildes (~) to represent lines that 
" appear in a window but are not actually part of 
" the buffer (i.e., for visual lines that follow 
" the last line of a buffer). This isn't too 
" distracting unless you verially split a window, 
" then the empty buffer on the right is full of 
" colorful blue tildes. You could tone this done 
" by, say, changing the tildes to pink, i.e.,
"
"   highlight NonText guifg=Pink2
"
" but, really, since Vim is displaying line 
" numbers -- and since line numbers are only 
" displayed for actual lines in the document -- 
" we don't even need the tildes! You can simply 
" infur the end of the document by where the line 
" numbers are no longer displayed. (Note that 
" guifg=NONE seems like the proper way to do 
" this, but it makes the tildes black, not 
" transparent (or maybe I missed something when I 
" tried it).)
highlight NonText guifg=White

" Mock zellner
" --------------------------------
" The zellner color scheme changes the status 
" line for the active window. The default is that 
" each status line (i.e., the line beneath each 
" window) is white text on a black background, 
" save for the active window (the window where 
" the cursor is), which is yellow text on a dark 
" gray background. (For the default color scheme, 
" the active window's status line is bold white 
" on black, and inactive windows' status lines 
" are normal white on black.)
"
" This is what's set in zellner.vim:
"
"    highlight StatusLine 
"    \ term=bold,reverse cterm=NONE |
"    \ ctermfg=Yellow ctermbg=DarkGray |
"    \ gui=NONE guifg=Yellow guibg=DarkGray
"
" Note that zellner does not specify StatusLineNC 
" (for inactive windows), so it remains the 
" default -- white foreground and black 
" background. This is annoying; I don't like some 
" status lines being black and one being dark 
" gray, so let's make them all dark gray. This 
" means using the same settings zellner uses for 
" StatusLine, but also adding StatusLineNC, 
" specifying that inactive windows' status lines 
" use the same background as the active window 
" status line but instead use a white foreground 
" (font) color.
highlight StatusLineNC term=reverse gui=NONE 
  \ guifg=White guibg=DarkGray 
  \ ctermfg=White ctermbg=DarkGray
highlight StatusLine term=bold,reverse gui=NONE 
  \ guifg=Yellow guibg=DarkGray 
  \ cterm=NONE ctermfg=Yellow ctermbg=DarkGray 

" Visually Appealing Vertical Split
" --------------------------------
" When you split a window vertically, there's a 
" column of black rectangles that runs between 
" the two windows, and each black rectangle has 
" a vertical bar in it. This, to me, is very 
" distracting!
"
" And you really don't need these rectangles- the
" line numbers in each window provide adequate 
" visual separation.
"
" So I like to hide the rectangles.
"
" This is also helpful if you like working with 
" narrow text columns but enjoy having whitespace 
" on the right side of the editor.
"
" Bare with me while I describe this: I like 
" working with two vertical windows, each 50 
" characters wide, with my working buffer in the 
" left window and an empty buffer in the right. 
" Since the buffer in the right window is empty, 
" only line number 1 is displayed, and so you end 
" up with an awesome chunk of whitespace. Why not 
" just work in one window that's 50 characters 
" wide? Well, 'cause then your buffer is squished 
" in a narrow gVim window and your desktop picture 
" is distractingly close to what you're working on.
" Weird, right? Something about how my brain is 
" wired...
"
" So here's what we'll do: we'll set linebreak, 
" which complements wrap by wrapping lines only 
" where visually pleasing, i.e., at the nearest 
" whitespace character or punctuation. 
" Specifically, :set breakat? returns
"
"    breakat= ^I!@*-+;:,./?
"
" We'll also modify the black rectangles with the 
" white vertical tab characters to be white on 
" white, which effectively hides them.
set linebreak
highlight VertSplit term=reverse gui=NONE 
  \ guifg=White guibg=White 
  \ ctermfg=White ctermbg=White

" NOTE When working with two vertically split 
"      windows, the left one container your 
"      document and the right one containing an 
"      empty buffer, the scroll bar for your 
"      document is on the left side of the gVim 
"      window, rather than on the right. You'll
"      probably eventually get used to this....

" ------------------------------------------
" ----------- Random Randomness ------------
" ------------------------------------------

" --------------------------------
" Ctrl-Return is Your Special Friend
" --------------------------------
" Ctrl-<CR> starts a new line without the comment 
" leader
nmap <C-CR> <C-o><Home><Down>i<CR><Up>
imap <C-CR> <C-o><Home><Down><CR><Up>

" --------------------------------
" Correct Ctrl-Z While Text Selected 
" --------------------------------
" Ctrl-Z is mapped to undo in Normal and Insert 
" mode, but in Select mode it just lowercases 
" what's selected!
" NOTE To lowercase in Select mode, type  
"      <Ctrl-o> to start a command, then type 
"        gu{motion},
"      e.g., 
"        <C-o>gu<DOWN>
"      (or <C-o>gu<UP>, it does the same thing). 
"      (And guess what? gU uppercases.)
vnoremap <C-Z> :<C-U>
  \ :undo<CR>
vnoremap <C-Y> :<C-U>
  \ :redo<CR>

" NOTE For whatever reason, trying to map C-S-Z also remaps 
"      C-Z, so I can't make Ctrl-Shift-Z into redo!
" Doesn't work: noremap <C-S-Z> :redo<CR>

" --------------------------------
" Change Path Delimiters Quickly
" --------------------------------
" http://vim.wikia.com/wiki/Change_between_backslash_and_forward_slash

" Press f/ to change every backslash to a 
"          forward slash, in the current line.
" Press f\ to change every forward slash to a 
"          backslash, in the current line.
" The mappings save and restore the search 
" register (@/) so you can continue a previous 
" search, if desired (i.e., the previous search 
" doesn't become '/' or '\').
:nnoremap <silent> f/ 
  \ :let tmp=@/<CR>:s:\\:/:ge<CR>:let @/=tmp<CR>
:nnoremap <silent> f<Bslash>
  \ :let tmp=@/<CR>:s:/:\\:ge<CR>:let @/=tmp<CR>

" --------------------------------
" Capture Ex Output So You Can 
"     Do With It As You Please
" --------------------------------
" http://vim.wikia.com/wiki/Capture_ex_command_output

" --------------------------------
" Basic Ex output Capture
" --------------------------------
"   :redir @a
"   :set all " or other command
"   :redir END
" and use "ap to put the yanked 

" --------------------------------
" Advanced Ex output Capture
" --------------------------------
" TabMessage runs the specified command
" and pastes the output to a new buffer
" in a new tab
function! s:TabMessage(cmd)
  " Redirect Ex output to a varibale
  " we'll call 'message'
	redir => message
	silent execute a:cmd
	redir END
  " Create a new tab and put the 
  " captured output
  tabnew
	silent put=message
  " Tell Vim not to ask us to save
  " when we close the buffer
  setlocal buftype=nowrite
endfunction
" Map our TabMessage function to an Ex :command 
" of the same name
command! -nargs=+ -complete=command 
  \ TabMessage call <SID>TabMessage(<q-args>)
" Usage, e.g.,
"   :TabMessage highlight
"   :TabMessage ec g:
" Shortcut
"   :Ta<TAB> should invoke autocompletion

" --------------------------------
" Start Command w/ Selected Text
" --------------------------------
" For help with Command Line commands, see :h cmdline
" Note that <C-R> is search in Insert mode but starts a 
" put in Command mode. Also note that <Ctrl-R> is 
" interpreted literally and does nothing; use <C-R>.

vnoremap : :<C-U>
  \ <CR>gvy
  \ :<C-R>"

" --------------------------------
" Count of Characters Selected
" --------------------------------
" NOTE I'm using Ctrl-# for now. It hurts my fingers to 
"      combine such keys, but I don't use this command 
"      that often and using the pound key seems intuitive.
" FIXME Make this work on word-under-cursor
" NOTE Cannot get this to work on <C-3>, so using Alt instead
"vnoremap <M-3> :<C-U>
"  \ :.s/\S/&/g<CR>
"  \ :'<,'>s/./&/g<CR>

"vnoremap <M-3> :<C-U>
"  \ <CR>gvy
"  \ gV
"  \ g<C-G>

"noremap <Leader>k :g<C-G>
":noremap <Leader>k "sy:.,$s/<C-r>s//gc<Left><Left><Left>
":noremap <Leader>k g<C-G>

" DO THIS INSTEAD:
" I can't get this to work, so just do this:
" Select your text, type <Ctrl-o>, then g<Ctrl-g>

" ***

" --------------------------------
" Lorem Ipsum Dump
" --------------------------------
" By Harold Giménez
"   http://awesomeful.net/posts/57-small-collection-of-useful-vim-tricks
"   http://github.com/hgimenez/vimfiles/blob/c07ac584cbc477a0619c435df26a590a88c3e5a2/vimrc#L72-122
" Define :Lorem command to dump a paragraph of lorem ipsum
command! -nargs=0 Lorem :normal iLorem ipsum dolor sit amet, consectetur
      \ adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore
      \ magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation
      \ ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute
      \ irure dolor in reprehenderit in voluptate velit esse cillum dolore eu
      \ fugiat nulla pariatur.  Excepteur sint occaecat cupidatat non
      \ proident, sunt in culpa qui officia deserunt mollit anim id est
      \ laborum.

" --------------------------------
" What is this? A silly TODO, I suppose.
" --------------------------------
"set diffexpr=MyDiff()
"function MyDiff()
"  let opt = '-a --binary '
"  if &diffopt =~ 'icase' | let opt = opt . '-i ' | endif
"  if &diffopt =~ 'iwhite' | let opt = opt . '-b ' | endif
"  let arg1 = v:fname_in
"  if arg1 =~ ' ' | let arg1 = '"' . arg1 . '"' | endif
"  let arg2 = v:fname_new
"  if arg2 =~ ' ' | let arg2 = '"' . arg2 . '"' | endif
"  let arg3 = v:fname_out
"  if arg3 =~ ' ' | let arg3 = '"' . arg3 . '"' | endif
"  let eq = ''
"  if $VIMRUNTIME =~ ' '
"    if &sh =~ '\<cmd'
"      let cmd = '""' . $VIMRUNTIME . '\diff"'
"      let eq = '"'
"    else
"      let cmd = substitute($VIMRUNTIME, ' ', '" ', '') . '\diff"'
"    endif
"  else
"    let cmd = $VIMRUNTIME . '\diff'
"  endif
"  silent execute '!' . cmd . ' ' . opt . arg1 . ' ' . arg2 . ' > ' . arg3 . eq
"endfunction

" --------------------------------
" Highlight Characters Past Our Desired Line Width
" --------------------------------
" http://vim.wikia.com/wiki/Highlight_long_lines
"
" See Cyclopath.vim: the user can cycle through a list of 
"                    style convention policies
" 
" In any case, the command is something like the following.
" The :match command changes the color of characters that 
" match the specified pattern
"   :match ErrorMsg '\%>80v.\+'
" You can turn off this feature using
"   :match none
" Lastly, I'm not sure what this command does, though I think 
" I was using it to test. It might split longs lines, I dunno...
"   :g/\%>79v/norm 77|gElC...

" --------------------------------
" Some lame smart-maximize command I don't use...
" --------------------------------

" Remap ,m to make and open error window if there are any errors. If there
" weren't any errors, the current window is maximized.
"map <silent> ,m :mak<CR><CR>:cw<CR>:call MaximizeIfNotQuickfix()<CR>

" Maximizes the current window if it is not the quickfix window.
function MaximizeIfNotQuickfix()
  if (getbufvar(winbufnr(winnr()), "&buftype") != "quickfix")
    wincmd _
  endif
endfunction

" --------------------------------
" Another silly smart-resize command I don't use...
" --------------------------------
" http://vim.wikia.com/wiki/Always_keep_quickfix_window_at_specified_height

" Maximize the window after entering it, be sure to keep the quickfix window
" at the specified height.
"au WinEnter * call MaximizeAndResizeQuickfix(12)

" Maximize current window and set the quickfix window to the specified height.
function MaximizeAndResizeQuickfix(quickfixHeight)
  " Redraw after executing the function.
  let s:restore_lazyredraw = getbufvar("%", "&lazyredraw")
  set lazyredraw
  " Ignore WinEnter events for now.
  "let s:restore_eventignore = getbufvar("%", "&ei")
  set ei=WinEnter
  " Maximize current window.
  wincmd _
  " If the current window is the quickfix window
  if (getbufvar(winbufnr(winnr()), "&buftype") == "quickfix")
    " Maximize previous window, and resize the quickfix window to the
    " specified height.
    wincmd p
    resize
    wincmd p
    exe "resize " . a:quickfixHeight
  else
    " Current window isn't the quickfix window, loop over all windows to
    " find it (if it exists...)
    let i = 1
    let currBufNr = winbufnr(i)
    while (currBufNr != -1)
      " If the buffer in window i is the quickfix buffer.
      if (getbufvar(currBufNr, "&buftype") == "quickfix")
        " Go to the quickfix window, set height to quickfixHeight, and jump to
        " the previous window.
        exe i . "wincmd w"
        exe "resize " . a:quickfixHeight
        wincmd p
        break
      endif
      let i = i + 1
      let currBufNr = winbufnr(i)
    endwhile
  endif
  "set nolazyredraw
  set ei-=WinEnter
  if (!s:restore_lazyredraw)
    set nolazyredraw
  endif
  " this isn't working...
  "set ei=s:restore_eventignore
endfunction

" --------------------------------
" Auto-format selected rows of text
" --------------------------------
" Select the lines you want to reformat into a pretty paragraph and hit F2. 
" NOTE If you select whole lines, back up the cursor one character so the
"      final line isn't selected. Otherwise, par doesn't prepend your new 
"      lines with the common comment from each line, since the last line 
"      appears as an empty line and its beginning doesn't match the other 
"      lines' beginnings, so par doesn't do any prepending.
" NOTE A blog I found online suggests you can use the following command:
"        map <F2> {!}par w81
"      But I couldn't get this to work.
"      Also, I considered mapping from normal and insert mode, but the 
"      selection the command makes extends back to the start of the function
"      I'm in, rather than selecting the paragraph I'm in, so for now we'll 
"      just do a vmap and force the user to highlight the lines s/he wants 
"      formatted.
" NOTE For some reason, I sometimes get a suffix, so explictly set to 0 chars.
"vnoremap <F2> :<C-U>'<,'>!par w79 s0<CR>
vnoremap <F2> :<C-U>'<,'>!par 79gqr<CR>
" For commit files, I like narrower columns, 60 chars in width.
vnoremap <S-F2> :<C-U>'<,'>!par 59gqr<CR>
" NOTE Normal mode and Insert mode <F1> are mapped to toggle-last-user-buffer 
"      (:e #) because my left hand got bored or felt left-out or something 
"      (my right hand's got the choice of BrowRight or F12 to toggle buffers, 
"       which is apparently something I do quite frequently).

" FIXME When reformatting FIXME and NOTE comments, you can run something like
"         :<,'>!par w40 h1 p8 s0
"       or
"         :<,'>!par w40 p8
"       But the p[N] value depends on the current indent...
"         you need to find the " FIXME and add the indent before that to 8...
" NOTE For now, if you run par on the second and subsequent lines (not the
"      FIXME or NOTE line) you can get the formatting you so desire

  " FIXME sdf sdf sdf sdf sdf sdf sdf sdf sf sdf sdf sdfs kj hdskjfh kjdsh kjhfds kjhsd kjhsd kjhsd
  "       kjhsd fkjh skjhds fkjhsd fkjhsdf kjfkjhsf kjhf kjhsfd kjhsd kjhsd kjhsd kjhsd kjhsd kjhsd
  "       kjhskjhs kjhsf f kjhsf kjhsfd kjhdsf kjhdsf

" --------------------------------
" Auto-indent selected code
" --------------------------------
" SEE INSTEAD: Select code, <Ctrl-O>= fixes code indenting (auto-indents).
" [lb] doesn't use this fcnality, ever.

" --------------------------------
" Auto-indent selected code
" --------------------------------
" Switch on cindent automatically for all files
" See comments in filetype.vim; this helps somewhat for Python, but not for
" ActionScript (*.mxml and *.as) files. It also doesn't indent per the
" Cyclopath style guide for function parameters that span multiple lines.
" That is, in python, the auto-indenter produces:
"   def my_func(param_1,
"         param_2):
"      pass
" Whereas the original Cyclopath style guide would rather you do this:
"   def my_func(param_1,
"               param_2):
"      pass
" Personally, I'm a fan of the first style, since it's predictable: the
" second and subsequent parameters lines are indented with two tab stops
" from the first line; then, when you start your function code, you're back to
" one tab stop. This is easy to read, and it's easy to type, since you don't 
" have to waste time spacing your lines (or removing spaces, if you've changed 
" the function header or other parameters).
" 2012.05.17: The comment above about indent not helping mxml/as files is
" wrong, since I like how they format xml data.
filetype indent on

" --------------------------------
" Ctrl-J/Ctrl-K Traverse Buffer History
" --------------------------------
noremap <C-j> :BufSurfBack<CR>
inoremap <C-j> <C-O>:BufSurfBack<CR>
cnoremap <C-j> <C-C>:BufSurfBack<CR>
onoremap <C-j> <C-C>:BufSurfBack<CR>
noremap <C-k> :BufSurfForward<CR>
inoremap <C-k> <C-O>:BufSurfForward<CR>
cnoremap <C-k> <C-C>:BufSurfForward<CR>
onoremap <C-k> <C-C>:BufSurfForward<CR>

" --------------------------------
" Bookmarking
" --------------------------------
" 
"     Any line can be "Book Marked" for a quick cursor return.
" 
"         * Type the letter "m" and any other letter to identify the line.
"         * This "marked" line can be referenced by the keystroke sequence "'" and the identifying letter.
"           Example: "mt" will mark a line by the identifier "t".
"           "'t" will return the cursor to this line at any time.
"           A block of text may be referred to by its marked lines. i.e.'t,'b

" --------------------------------

" FIXME Map VBox host key to Menu key, and screw <Home> (you got <M-Left> now, so...)

" --------------------------------

" http://milan.adamovsky.com/2010/08/contextual-indent.html
" http://www.gnu.org/prep/standards/html_node/Formatting.html

" --------------------------------

" Seriously, do I just want to be different?
":hi Search guibg=Green
:hi Search guibg=LightGreen

" --------------------------------

" FIXME: Applies just to Python, maybe others
" EXPLAIN: You removed colons: because...?
" because in Python it causes an auto-indent? 
" But I still have problems when I type : in python: 
"   it still reformats my line. So I assume these sets
"   are in vain.
" :set cinkeys=0{,0},0),:,!^F,o,O,e
:set cinkeys=0{,0},0),!^F,o,O,e
" :set indentkeys=0{,0},:,!^F,o,O,e,<:>,=elif,=except
:set indentkeys=0{,0},!^F,o,O,e,<:>,=elif,=except

" --------------------------------

" 2012.08.19: Move paragraphs up and down, for managing notes 
"             a la, um, that one note Web site.

" Move the paragraph under the cursor up a paragraph.
function s:MoveParagraphUp()
  " The '.' is the current cursor position.
  let lineno = line('.')
  if lineno != 1
    let a_reg = @a
    " The basic command is: {"ad}{"aP
    " i.e., move the start-of-paragraph:    { 
    "       yank to the 'a' register:       "a
    "       delete to the end-of-paragraph: d}
    "       move up a paragraph:            {
    "       paste from the 'a' register:    "aP
    "       move down a line:               j
    "        (becase the '{' and '}' cmds 
    "         go the line above or below 
    "         the paragraph)
    normal! {"ad}{"aPj
    let @a = a_reg
  endif
endfunction

" Move the paragraph under the cursor down a paragraph.
function! s:MoveParagraphDown()
  " The '.' is the current cursor position.
  let line_1 = line('.')
  " The '$' is the last line in the current buffer.
  " So don't do anything unless not the last line.
  let line_n = line('$')
  if line_1 != line_n
    let a_reg = @a
    " Go to top of paragraph:               {
    " yank and delete to the EOP:           a"d}
    " drop down another paragraph:          }
    " paste the yanked buffer:              "aP
    " move to the end of the paragraph:     }
    " move to the SOP (somehow this works): {
    " move down a line to be at SOP:        j
    normal! {"ad}}"aP}{j
    let @a = a_reg
  endif
endfunction

" --------------------------------
" Ctrl-P/Ctrl-L Moves Paragraphs
" --------------------------------
noremap <C-p> :call <sid>MoveParagraphUp()<CR>
inoremap <C-p> <C-O>:call <sid>MoveParagraphUp()<CR>
cnoremap <C-p> <C-C>:call <sid>MoveParagraphUp()<CR>
onoremap <C-p> <C-C>:call <sid>MoveParagraphUp()<CR>
noremap <C-l> :call <sid>MoveParagraphDown()<CR>
inoremap <C-l> <C-O>:call <sid>MoveParagraphDown()<CR>
cnoremap <C-l> <C-C>:call <sid>MoveParagraphDown()<CR>
onoremap <C-l> <C-C>:call <sid>MoveParagraphDown()<CR>

" ----------------------------------------------------
" <Leader>-O opens hyperlink under cursor or selected.
" ----------------------------------------------------

" Link to Web page under cursor.
" :!firefox cycloplan.cyclopath.org &> /dev/null
noremap <silent> <Leader>o :!firefox <C-R><C-A> &> /dev/null<CR><CR>
inoremap <silent> <Leader>o <C-O>:!firefox <C-R><C-A> &> /dev/null<CR><CR>
" Interesting: C-U clears the command line, which contains cruft, e.g., '<,'>
" gv selects the previous Visual area.
" y yanks the selected text into the default register.
" <Ctrl-R>" puts the yanked text into the command line.
vnoremap <silent> <Leader>o :<C-U>
  \ <CR>gvy
  \ :!firefox <C-R>" &> /dev/null<CR><CR>
" Test the three modes using: https://github.com/p6a

" ----------------------------------------------------
" Recover from accidental Ctrl-U
" ----------------------------------------------------

" http://vim.wikia.com/wiki/Recover_from_accidental_Ctrl-U

inoremap <c-u> <c-g>u<c-u>
inoremap <c-w> <c-g>u<c-w>

" ----------------------------------------------------
" From /usr/share/vim/vim74/vimrc_example.vim
"      /usr/share/vim/vim74/gvimrc_example.vim
" ----------------------------------------------------

" Convenient command to see the difference between the current buffer and the
" file it was loaded from, thus the changes you made.
" Only define it when not defined already.
if !exists(":DiffOrig")
  command DiffOrig vert new | set bt=nofile | r ++edit # | 0d_ | diffthis
    \ | wincmd p | diffthis
endif

" When editing a file, always jump to the last known cursor position.
" Don't do it when the position is invalid or when inside an event handler
" (happens when dropping a file on gvim).
" Also don't do it when the mark is in the first line, that is the default
" position when opening a file.
autocmd BufReadPost *
  \ if line("'\"") > 1 && line("'\"") <= line("$") |
  \   exe "normal! g`\"" |
  \ endif

" ------------------------------------------
" ----------------------------------- EOF --

