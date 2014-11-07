" This script modifies Vim for use in a Cyclopath development environment

" Cyclopath Shiftwidth
" --------------------------------
" Cyclopath uses trips! 321 Polo? 321 Cyclopath!
autocmd BufEnter,BufRead *.as set tabstop=3
autocmd BufEnter,BufRead *.mxml set tabstop=3
autocmd BufEnter,BufRead *.py set tabstop=3
autocmd BufEnter,BufRead *.sql set tabstop=3
autocmd BufEnter,BufRead *.as set shiftwidth=3
autocmd BufEnter,BufRead *.mxml set shiftwidth=3
autocmd BufEnter,BufRead *.py set shiftwidth=3
autocmd BufEnter,BufRead *.sql set shiftwidth=3
" Cyclopath also enforces a 79 character line max
" NOTE Not sure why set doesn't work, but autocmd does...
"set textwidth=79
"set wrapmargin=79
autocmd BufEnter,BufRead *.as set tw=79
autocmd BufEnter,BufRead *.mxml set tw=79
autocmd BufEnter,BufRead *.py set tw=79
autocmd BufEnter,BufRead *.sql set tw=79

"autocmd BufEnter,BufRead *.as :match ErrorMsg '\%>79v.\+'
"autocmd BufEnter,BufRead *.mxml :match ErrorMsg '\%>79v.\+'
"autocmd BufEnter,BufRead *.py :match ErrorMsg '\%>79v.\+'
"autocmd BufEnter,BufRead *.sql :match ErrorMsg '\%>79v.\+'

autocmd BufEnter,BufRead * call s:CP_ToggleStyleGuides_SetMatch(0)

autocmd BufEnter,BufRead *.as call s:CP_ToggleStyleGuides_SetMatch(0)
autocmd BufEnter,BufRead *.mxml call s:CP_ToggleStyleGuides_SetMatch(0)
autocmd BufEnter,BufRead *.py call s:CP_ToggleStyleGuides_SetMatch(0)
autocmd BufEnter,BufRead *.sql call s:CP_ToggleStyleGuides_SetMatch(0)

" Bash scripts and Vim scripts follow Retrosoft style
autocmd BufEnter,BufRead *.vim set tabstop=2 shiftwidth=2 tw=79
"autocmd BufEnter,BufRead *.vim match ErrorMsg '\%>79v.\+'
autocmd BufEnter,BufRead .bashrc* set tabstop=2 shiftwidth=2 tw=79
"autocmd BufEnter,BufRead .bashrc* match ErrorMsg '\%>79v.\+'
"
autocmd BufEnter,BufRead *.vim call s:CP_ToggleStyleGuides_SetMatch(2)
autocmd BufEnter,BufRead *.bashrc call s:CP_ToggleStyleGuides_SetMatch(2)

" YAML. Using tabstop=2 because of the way dashes are used, three is too much.
autocmd BufEnter,BufRead *.ya?ml set tabstop=2 shiftwidth=2 tw=79
"
autocmd BufEnter,BufRead *.ya?ml call s:CP_ToggleStyleGuides_SetMatch(2)

" 2013.05.14: How have I not noticed this not working for so long??
"             FIXME: If CP_ToggleStyleGuides_SetMatch is not called,
"                    \e does not work for switching tab and width styles.
autocmd BufEnter,BufRead *.sh call s:CP_ToggleStyleGuides_SetMatch(2)
autocmd BufEnter,BufRead *.txt call s:CP_ToggleStyleGuides_SetMatch(2)
autocmd BufEnter,BufRead *.conf call s:CP_ToggleStyleGuides_SetMatch(2)
" FIXME: Expand this list...


" FIXME Above is very redundant; can I make a fcn.?

" Cyclopath Grep
" --------------------------------
" Exclude Cyclopath's build directory from grep.
" See dubsacks.vim for what all these options mean.
" Also see dubsacks.vim because we cxpx from there.
" NOTE: There are two build directories: build/ and build-print/.
if filereadable(
    \ $HOME . "/.vim/grep-exclude")
  " *nix
  set grepprg=egrep\ -n\ -R\ -i\ --exclude-from=\"$HOME/.vim/grep-exclude\"\ --exclude-dir=\"build\"\ --exclude-dir=\"build-print\"\ --exclude-dir=\"winpdb\"
elseif filereadable(
    \ $USERPROFILE . 
    \ "/vimfiles/grep-exclude")
  " Windows
  set grepprg=egrep\ -n\ -R\ -i\ --exclude-from=\"$USERPROFILE/vimfiles/grep-exclude\"\ --exclude-dir=\"build\"\ --exclude-dir=\"build-print\"\ --exclude-dir=\"winpdb\"
else
  call confirm('dubsacks.vim: Cannot find grep-xclude file', 'OK')
endif

" ======================================================
" ======================================================

function s:CP_ToggleStyleGuides_SetMatch(style_index)
  " NOTE: By checking exists, the style is only applied the very first time a
  "       buffer is opened (so you'll have to reload Vim to have it default
  "       back, as opposed to us not checking exists here but always resetting
  "       the style whenever the user re-enters a buffer).
  if !exists('b:cyclopath_style_index')
    let b:cyclopath_style_index = a:style_index
  endif
endfunction

" FIXME Where's this belong?

" ---------------
" Map <Leader>e to Toggling Style Guide [E]nforcement
if !hasmapto('<Plug>CP_ToggleStyleGuides')
  map <silent> <unique> <Leader>e
    \ <Plug>CP_ToggleStyleGuides
endif
" Map <Plug> to an <SID> function
map <silent> <unique> <script> 
  \ <Plug>CP_ToggleStyleGuides 
  \ :call <SID>CP_ToggleStyleGuides(0)<CR>
" And finally thunk to the script fcn.
""function <SID>CP_ToggleStyleGuides()
""  call s:CP_ToggleStyleGuides()
""endfunction

" 2012.10.03: I rarely use the style guide toggle, instead usually 
" just typing :match none, but it'd be nice to have a shortcut...
" but one that I'll use, like Ctrl-e. In default Vim, Ctrl-e, in
" command and select mode, moves the buffer one line up in
" the window; it doesn't do anything in insert mode.
" Ug, this command is too important to remap... there's no alternative
" way to call Ctrl-e (see :h Ctrl-e and you'll see it's only mapped to
" one key-combo).
" NO: noremap <C-e> :call <SID>CP_ToggleStyleGuides()<CR><CR>
" NO: inoremap <C-e> <C-O>:call <SID>CP_ToggleStyleGuides()<CR><CR>

" ---------------
" Let the user map their own command to the
" toggle function by making it a <Plug>
"   1. Make the <Plug>
""map <silent> <unique> <script> 
""  \ <Plug>CP_ToggleStyleGuides 
""  \ :call <SID>CP_ToggleStyleGuides()<CR>
"   2. Thunk the <Plug>
function s:CP_ToggleStyleGuides(dont_cycle)
  " FIXME No longer "toggle", now cycles through multiple

  if !exists('s:style_enforcer_length')
    " FIXME Magic number! Should use array lookup instead of 
    "       hard-coding everything in this fcn.
    let s:style_enforcer_length = 4 - 1
  endif

  let l:use_style = 1
  " NO: \ || (&tw == 0)
  if (!exists('b:cyclopath_style_index')
      \ || (&buftype == 'quickfix')
      \ || (&modifiable == 0)
      \ || (bufname('%') == '-MiniBufExplorer-'))
    let l:use_style = 0
  endif

  if (l:use_style == 1)
    if (a:dont_cycle == 0)
      let b:cyclopath_style_index = b:cyclopath_style_index + 1
      if (b:cyclopath_style_index > s:style_enforcer_length)
        let b:cyclopath_style_index = 0
      endif
    endif
  endif

  " 2011.01.27: Use setlocal, not set, so the command applies just to cur buf.
  " NOTE: match applies to the current window, so this fcn. has to be called
  "       whenever the buffer changes.
  if (0 == l:use_style)
    setlocal tabstop=2
    setlocal shiftwidth=2
    setlocal tw=0
    match none
    if (a:dont_cycle == 0)
      echo "Styleless: 2 sp/t, * ch/l."
    endif
  elseif (0 == b:cyclopath_style_index)
    setlocal tabstop=3
    setlocal shiftwidth=3
    setlocal tw=79
    match ErrorMsg '\%>79v.\+'
    if (a:dont_cycle == 0)
      echo "Cyclopath: 3 sp/t, 80 ch/l."
    endif
  elseif (1 == b:cyclopath_style_index)
    setlocal tabstop=3
    setlocal shiftwidth=3
    setlocal tw=0
    match none
    if (a:dont_cycle == 0)
      echo "Cyclopath: 3 sp/t, * ch/l."
    endif
  elseif (2 == b:cyclopath_style_index)
    setlocal tabstop=2
    setlocal shiftwidth=2
    setlocal tw=79
    match ErrorMsg '\%>79v.\+'
    if (a:dont_cycle == 0)
      echo "Retrosoft: 2 sp/t, 80 ch/l."
    endif
  elseif (3 == b:cyclopath_style_index)
    setlocal tabstop=2
    setlocal shiftwidth=2
    setlocal tw=0
    match none
    if (a:dont_cycle == 0)
      echo "Retrosoft: 2 sp/t, * ch/l."
    endif
  else
    " assert(False)
    call confirm('Cyclopath.vim: Programmer Error!', 'OK')
  endif

endfunction

autocmd BufEnter,BufRead * call s:CP_ToggleStyleGuides_FixMatch()
function s:CP_ToggleStyleGuides_FixMatch()
  if exists('b:cyclopath_style_index')
    call <SID>CP_ToggleStyleGuides(1)
  endif
endfunction

" ======================================================
" ======================================================

" FIXME Where's this belong?

"" ---------------
"" Map <Leader>G0 to the Grep Prompt
"if !hasmapto('<Plug>GrepPrompt_Simple')
"  map <silent> <unique> <Leader>g
"    \ <Plug>GrepPrompt_Simple
"endif

" Map <Plug> to an <SID> function
map <silent> <unique> <script> 
  \ <Plug>GrepPrompt_Simple 
  \ :call <SID>GrepPrompt_Simple("", 0)<CR><CR>

" And finally thunk to the script fcn.
""function <SID>GrepPrompt_Simple()
""  call s:GrepPrompt_Simple()
""endfunction

" ---------------
" Let the user map their own command to the
" toggle function by making it a <Plug>
"   1. Make the <Plug>
""map <silent> <unique> <script> 
""  \ <Plug>GrepPrompt_Simple 
""  \ :call <SID>GrepPrompt_Simple()<CR>
"   2. Thunk the <Plug>
"
" GrepPrompt_Simple: term is the term to search, or 
"                      "" if we should ask the user
"                    locat_index is the location index
"                      to search, or 0 to ask user for it
" If the callee supplies both term and locat_index, we automatically complete
" the search. However, this bypasses input(), which means term doesn't get
" added to the input() history. This is annoying if you auto-search a lot and
" want to go back to a previous search term (though I suppose you could just
" use :cold to jump back in the quickfix history). I don't think we can add to
" the histories, and I can't think of a good solution (we could call input()
" with a default value, but that's probably annoying).
function s:GrepPrompt_Simple(term, locat_index)
  call inputsave()
  let the_term = a:term
  if a:term == ""
    " There's a newline in the buffer, so call inputsave
    "call inputsave()
    let the_term = input("Search for: ")
    "call inputrestore()
    "echo "The term is" . the_term
    "let TBD = input("Hit any key to continue: ")
  endif
  " Check for <ESC> lest we dismiss a help 
  " page (or something not in the buffer list)
  if the_term != ""
    " Ask the user to enter/confirm the search location
    let new_i = a:locat_index
    if new_i == 0
      "call inputsave()
      let new_i = inputlist(s:GrepPrompt_Simple_GetInputlist(
        \ s:simple_grep_last_i))
      "call inputrestore()
    endif
    "echo "=== new_i: " . new_i
    "let TBD = input("Hit any key to continue: ")
    " If the user hits Enter or Escape, inputlist returns 0, which is also the
    " very first item in the list. However, we put "Search in:" as the first
    " item, so we can assume the user hit Enter or Escape. In the past, we
    " interpreted that to mean the user wants us to search in the last used 
    " location. But I [lb] got annoyed that Escape wouldn't cancel the operation. 
    " I considerd making the next row (value 1) say "Cancel", but that seems
    " awkward, and I still want to be able to reclaim Escape, so there's now 
    " a separate keyboard shortcut to search again in the same location.
    " UG. This lasted ten minutes. I can't live without double-return, either!
    " Trying "1" as the cancel indicator
    if new_i == 0
      let new_i = s:simple_grep_last_i
      if new_i == 0
        "call inputsave()
        let new_i = inputlist(s:GrepPrompt_Simple_GetInputlist(
          \ s:simple_grep_last_i))
        "call inputrestore()
      endif
    endif
    "if new_i > 0
    if new_i > 1
      let locat = s:simple_grep_locat_lookup[new_i]
      execute "silent gr! \"" . the_term . "\" " . locat
      let s:simple_grep_last_i = new_i
      :QFix!(0)
      ":QFix(1, 1)
    endif
  endif
  call inputrestore()
endfunction

function s:GrepPrompt_Simple_GetInputlist(i_highlight)
  let ilist = [s:simple_grep_locat_lookup[0]]
  for i in range(1, s:simple_grep_locat_lookup_len - 1)
    let ilist = add(ilist, s:GrepPrompt_Simple_GetInputlistItem(
      \ i, i == a:i_highlight))
  endfor
  return ilist
endfunction

function s:GrepPrompt_Simple_GetInputlistItem(idx, do_highlight)
  let listitem = "    "
  if a:do_highlight
    let listitem = "(*) "
  endif
  let listitem .= a:idx . ". " . s:simple_grep_locat_lookup[a:idx]
  return listitem
endfunction

" FIXME New fcn. 2011.01.08

" Quick-search selected item on last-used search location
" :noremap <Leader>G "sy:call <SID>GrepPrompt_Auto_Prev_Location("<C-r>s")<CR>
" NOTE Extra <CR> to avoid Quickfix's silly prompt,
"      'Press ENTER or type command to continue'
":noremap <Leader>G :call <SID>GrepPrompt_Auto_Prev_Location("<C-R><C-W>")<CR>

"map <silent> <unique> <Leader>g <Plug>GrepPrompt_Simple
noremap <silent> <Leader>g :call <SID>GrepPrompt_Simple("", 0)<CR>
inoremap <silent> <Leader>g <C-O>:call <SID>GrepPrompt_Simple("", 0)<CR>
"cnoremap <silent> <unique> <Leader>g <C-C>:call <SID>GrepPrompt_Simple("", 0)<CR>
" Can't do unique on onoremap 'cause it's already set?
" onoremap <silent> <unique> <Leader>g <C-C>:call <SID>GrepPrompt_Simple("", 0)<CR>
" Selected word
"vnoremap <silent> <Leader>g :<C-U>call <SID>GrepPrompt_Auto_Ask_Location(<C-R>)<CR>
"vnoremap <Leader>g :<C-U>echo "Hello ". @"

" NOTE I'm not sure we need to store registers like this but we do
"vnoremap <Leader>g :<C-U>
"  \ let old_reg=getreg('"')<Bar>let old_regtype=getregtype('"')<CR>
"  \ gvy
"  \ :call <SID>GrepPrompt_Simple(@@, 0)<CR>
"  \ gV
"  \ :call setreg('"', old_reg, old_regtype)<CR>
" Better: (keeps stuff selected)
vnoremap <silent> <Leader>g :<C-U>
  \ <CR>gvy
  \ :call <SID>GrepPrompt_Simple(@@, 0)<CR>

"xnoremap <silent> <Leader>g <C-U>:call <SID>GrepPrompt_Auto_Ask_Location("<C-R><C-R>")<CR>
"snoremap <silent> <Leader>g <C-U>:call <SID>GrepPrompt_Auto_Ask_Location("<C-R>")<CR>

" FIXME I think F4 is a better match (easier to use)
" Word under cursor
noremap <silent> <F4> :call <SID>GrepPrompt_Auto_Prev_Location("<C-R><C-W>")<CR>
inoremap <silent> <F4> <C-O>:call <SID>GrepPrompt_Auto_Prev_Location("<C-R><C-W>")<CR>
cnoremap <silent> <F4> <C-C>:call <SID>GrepPrompt_Auto_Prev_Location("<C-R><C-W>")<CR>
onoremap <silent> <F4> <C-C>:call <SID>GrepPrompt_Auto_Prev_Location("<C-R><C-W>")<CR>
" Selected word
vnoremap <silent> <F4> :<C-U>
  \ <CR>gvy
  \ :call <SID>GrepPrompt_Auto_Prev_Location(@@)<CR>

" This time, prompt for location
noremap <silent> <S-F4> :call <SID>GrepPrompt_Auto_Ask_Location("<C-R><C-W>")<CR>
inoremap <silent> <S-F4> <C-O>:call <SID>GrepPrompt_Auto_Ask_Location("<C-R><C-W>")<CR>
cnoremap <silent> <S-F4> <C-C>:call <SID>GrepPrompt_Auto_Ask_Location("<C-R><C-W>")<CR>
onoremap <silent> <S-F4> <C-C>:call <SID>GrepPrompt_Auto_Ask_Location("<C-R><C-W>")<CR>

" NOTE Cannot get <C-8> or <C-*> to work (both still call :nohlsearch)
" NOTE <C-R><C-W> is Vim-speak for the word under the cursor
" FIXME Move this to EditPlus.vim or something...
noremap <silent> <C-F4> :call <SID>GrepPrompt_Term_Prev_Location("<C-R><C-W>")<CR>
inoremap <silent> <C-F4> <C-O>:call <SID>GrepPrompt_Term_Prev_Location("<C-R><C-W>")<CR>
cnoremap <silent> <C-F4> <C-C>:call <SID>GrepPrompt_Term_Prev_Location("<C-R><C-W>")<CR>
onoremap <silent> <C-F4> <C-C>:call <SID>GrepPrompt_Term_Prev_Location("<C-R><C-W>")<CR>

function s:GrepPrompt_Term_Prev_Location(term)
  call s:GrepPrompt_Simple("", s:simple_grep_last_i)
endfunction

function s:GrepPrompt_Auto_Prev_Location(term)
  if a:term != ""
    call s:GrepPrompt_Simple(a:term, s:simple_grep_last_i)
  endif
endfunction

function s:GrepPrompt_Auto_Ask_Location(term)
  if a:term != ""
    call s:GrepPrompt_Simple(a:term, 0)
  endif
endfunction

" ------------------------------------------
" Private Interface

" Initialisation
" ------------------------

let s:simple_grep_last_i = 0

" Ten of the first eleven shortcuts are used commonly and should keep their
" rank.
"   1: flashclient
"   2: pyserver
"   3: scripts
"   4: all source
"   5: all sources
"   6: my notes
"   7: installation notes
"   8: vim scripts
"   9: bash scripts
"   10: don't care (typing 10 is annoying)
"   11: dubs trunk
" FIXME Home v. Work paths? Hard-coded? Where to put/config these...

" FIXME What about a machine-specific .vim file?
"         private_$HOSTNAME.vim

let s:simple_grep_locat_lookup = [
  \ "Search in:",
  \ "[Enter 1 to Cancel]",
  \ "/ccp/dev" . "/cp/flashclient",
  \ "/ccp/dev" . "/cp/pyserver",
  \ "/ccp/dev" . "/cp/scripts",
  \ "/ccp/dev" . "/cp",
  \ $HOME . "/dubs/notes",
  \ $HOME . "/dubs/notes/install-notes",
  \ $HOME . "/.vim",
  \ "`echo " . $HOME . "/.bashrc*`",
  \ "/ccp/dev" . "/joust/Joust/joust/model",
  \ "/ccp/bin/ccpdev",
  \ "/ccp/dev" . "/cp/android",
  \ $HOME . "/dubs/setup",
  \ "/ccp/dev" . "/cp_postgis116",
  \ "/ccp/dev" . "/cp/flashclient/items",
  \ "/ccp/dev" . "/cp/flashclient/views",
  \ "/ccp/dev" . "/cp/flashclient/views/commands",
  \ "/ccp/dev" . "/cp/flashclient/views/panels",
  \ "/ccp/dev" . "/cp/mapserver",
  \ "/ccp/dev" . "/cp/flashclient/bettercp",
  \ "/ccp/dev" . "/20_is_not_a_folder_its_a_number",
  \ "/ccp/dev" . "/cp/routing_analytics",
  \ "/ccp/dev",
  \ "/ccp/dev/cp_trunk",
  \ "/ccp/dev/cp_trunk_v2",
  \ "/ccp/opt/.downloads/graphserver_2011.06.15",
  \ "/ccp/dev" . "/cp/services",
  \ "28",
  \ "29",
  \ "30",
  \ "31",
  \ "32",
  \ "/ccp/etc/cp_confs",
  \ "/ccp/dev" . "/cp/pyserver "
  \   . "/ccp/dev" . "/cp/scripts "
  \   . "/ccp/dev" . "/cp/services "
  \   . "/ccp/dev" . "/cp/mapserver "
  \   . "/ccp/dev" . "/cp/mediawiki ",
  \ "/ccp/dev" . "/cp/pyserver "
  \   . "/ccp/dev" . "/cp/services ",
  \ "36"
  \]

let s:simple_grep_locat_lookup_len = 
  \ len(s:simple_grep_locat_lookup)

" ======================================================
" ======================================================

" From .bashrc-cyclopath*

" FIXME This section needs to be cleaned up (cosmetically, that is)

" Build Cyclopath (Incremental)
" -----------------------------
" F5
"
" 2012.10.31: Disabled. Build from CLI and use C-F5 to see output.
""map <F5> <Plug>Cyclopath_Build_Incremental
"noremap <F5> :call <SID>Cyclopath_Build_Project(0)<CR><CR>
"inoremap <F5> <C-O>:call <SID>Cyclopath_Build_Project(0)<CR><CR>
""cnoremap <F5> <C-C>:call <SID>Cyclopath_Build_Incremental()<CR>
""onoremap <F5> <C-C>:call <SID>Cyclopath_Build_Incremental()<CR>
""map <silent> <unique> <script>
""  \ <Plug>Cyclopath_Build_Incremental 
""  \ :call <SID>Cyclopath_Build_Project(0)<CR>
""   2. Thunk the <Plug>
""function s:Cyclopath_Build_Incremental()
""  " FIXME: Sometimes I [lb] sloppilly hit F5 (build Ccp) when I mean to hit F6
""  " (restart Apache). Rather than move the keys further apart, what about
""  " having this fcn. check if fcsh is running or not: I usually debug pyserver 
""  " with fcsh killed, so this fcn. should only run if fcsh is running,
""  " otherwise the mistake wastes a lot of time, since it takes a while to start
""  " fcsh.
""  "!ps aux 
""  "  \| grep -e bin/fcsh$ -e lib/fcsh.jar$ -e "python ./fcsh-wrap"
""  "  \| awk '{print $2}' 
""  " First, save all files
""  :wa
""  " NOTE The tee commands outputs to stdout and saves to a file
""  "!pushd $cp/flashclient ; make | tee /tmp/flashclient_make ; popd
""  !pushd $cp/flashclient ; make ; cd $cp ; ./fixperms.sh ; popd
""  " Clear the flash log?
""  :call <SID>Cyclopath_Flash_Log_Truncate()
""  "!pushd $cp/flashclient ; make | tee /tmp/flashclient_make 2>&1 ; popd
""  "!pushd $cp/flashclient ; make > /tmp/flashclient_make 2>&1 ; popd
""  set errorformat=%A%f(%l):\ col:\ %c\ %m,%Z%m,%A%f(%l):\ %m,%Z%m
""  cgetfile /tmp/flashclient_make
""  :QFix!(1)
""  " FIXME Search for the first error
""  "   /Error:
""endfunction
"" FIXME Need "set errorformat=..." for flex output

" AS Syntax Errors:
"/ccp/dev/cp_1051/flashclient/build/views/dpanels/Detail_Box_Access_Manage.mxml(25):  Error: Syntax error: expected a definition keyword (such as function) after attribute protected, not static.

" MXML Syntax Errors:
"/ccp/dev/cp_1051/flashclient/build/views/dpanels/Detail_Box_Access_Manage.mxml(61): col: 15 Error: Attribute name "i" must be followed by the ' = ' character.

" Build Cyclopath (Rebuild All)
" -----------------------------
" SHIFT-F5
" 
" FIXME Do silently/in background
"       :execute "!myscript &" | redraw
"       :silent execute "!myscript &" | redraw
" 2012.10.31: Disabled. Build from CLI and use C-F5 to see output.
""map <S-F5> <Plug>Cyclopath_Build_Clean
"noremap <S-F5> :call <SID>Cyclopath_Build_Project(1)<CR><CR>
"inoremap <S-F5> <C-O>:call <SID>Cyclopath_Build_Project(1)<CR><CR>
""map <silent> <unique> <script>
""  \ <Plug>Cyclopath_Build_Clean 
""  \ :call <SID>Cyclopath_Build_Project(1)<CR>
""   2. Thunk the <Plug>
""function s:Cyclopath_Build_Clean()
""  "!killfc ; pushd $cp/flashclient ; make clean ; make ; cd $cp ; ./fixperms.sh ; re ; popd ; killfc
""  " NOTE The tee command hangs (waiting on EOF?) if we redirect stderr to stdout, e.g..,
""  "        pushd $cp/flashclient ; make clean ; make 2>&1 | tee /tmp/flashclient_make ; cd $cp ; ./fixperms.sh ; popd
""  "      I also tried
""  "        !pushd $cp/flashclient ; make clean ; make | tee /tmp/flashclient_make 2>&1 ; cd $cp ; ./fixperms.sh ; popd
""  "        !pushd $cp/flashclient ; make clean ; make |& tee /tmp/flashclient_make 2>&1 ; cd $cp ; ./fixperms.sh ; popd
""  "      So we'll just write straight to the temp file, which is fine, but
""  "      that means there's no live output while the command is being processed
""  :wa
""  call <SID>Cyclopath_Fcsh_Kill()
""  " NOTE The 2>&1, which redirects stderr to stdout, comes _after_ the whole "[command] > [file]"
""  "!pushd $cp/flashclient ; make clean ; make > /tmp/flashclient_make 2>&1 ; cd $cp ; ./fixperms.sh ; popd
""  !pushd $cp/flashclient ; make clean ; make ; cd $cp ; ./fixperms.sh ; popd
""  "call <SID>Cyclopath_Fcsh_Kill()
""  call <SID>Cyclopath_Apache_Restart()
""  " FIXME This is wrong -- Do we need to restore the old errorformat later?
""  " FIXME Should this go in a "autocmd BufRead..." ??
""  set errorformat=%A%f(%l):\ %m,%Z%m
""  cgetfile /tmp/flashclient_make
""  :QFix!(1)
""endfunction

" 2012.10.31: Disabled. Build from CLI and use C-F5 to see output.
"             This fcn. is no longer wired to any shortcut keys.
function s:Cyclopath_Build_Project(make_clean)
  " First, save all files
  :wa
  " NOTE The tee commands outputs to stdout and saves to a file
  "!killfc ; pushd $cp/flashclient ; make clean ; make ; cd $cp ; ./fixperms.sh ; re ; popd ; killfc
  " NOTE The tee command hangs (waiting on EOF?) if we redirect stderr to stdout, e.g..,
  "        pushd $cp/flashclient ; make clean ; make 2>&1 | tee /tmp/flashclient_make ; cd $cp ; ./fixperms.sh ; popd
  "      I also tried
  "        !pushd $cp/flashclient ; make clean ; make | tee /tmp/flashclient_make 2>&1 ; cd $cp ; ./fixperms.sh ; popd
  "        !pushd $cp/flashclient ; make clean ; make |& tee /tmp/flashclient_make 2>&1 ; cd $cp ; ./fixperms.sh ; popd
  "      So now fcsh-wrap just writes the output file for us.
  if (a:make_clean)
    call <SID>Cyclopath_Fcsh_Kill()
    make -C $cp/flashclient clean
  endif
  make --directory=$cp/flashclient
  " fcsh-wrap writes flashclient_make but the paths are to the build directory.
  " NOTE: There are two build directories: build/ and build-print/.
  silent !sed 's/\/flashclient\/build\(-print\)\?\//\/flashclient\//g' 
    \ /tmp/flashclient_make > /tmp/flashclient_make.ccp
  " Fix permissions on the executable.
  !$cp/fixperms.sh
  " Restart the server if we bothered we a big build.
  if (a:make_clean)
    "call <SID>Cyclopath_Fcsh_Kill()
    call <SID>Cyclopath_Apache_Restart()
  endif
  " FIXME This is wrong -- Do we need to restore the old errorformat later?
  " FIXME Should this go in a "autocmd BufRead..." ??
  set errorformat=%A%f(%l):\ col:\ %c\ %m,%Z%m,%A%f(%l):\ %m,%Z%m
  cgetfile /tmp/flashclient_make.ccp
  :QFix!(1)
endfunction

function s:Cyclopath_Fcsh_Kill()
  " Kill the following:
  "   /bin/sh /ccp/opt/flex/bin/fcsh
  "   java ... -jar /ccp/opt/flex/bin/../lib/fcsh.jar
  "   /usr/bin/python ./fcsh-wrap ...
  !ps aux 
    \| grep -e bin/fcsh$ -e lib/fcsh.jar$ -e "python ./fcsh-wrap" 
    \| awk '{print $2}' 
    \| xargs sudo kill -s 9
endfunction

" Restore Make Output (Quickfix) Hack
" -----------------------------------
" CTRL-F5
" 
"map <C-F5> <Plug>Quickfix_Older_Older
noremap <C-F5> :call <SID>Quickfix_Older_Older()<CR>
inoremap <C-F5> <C-O>:call <SID>Quickfix_Older_Older()<CR>
map <silent> <unique> <script> 
  \ <Plug>Quickfix_Older_Older 
  \ :call <SID>Quickfix_Older_Older()<CR>
"   2. Thunk the <Plug>
function s:Quickfix_Older_Older()
  " After running make, you can double-click errors in the quickfix window to
  " fix the compile-time error, but you'll find yourself searching (egrep'ing)
  " the code to fix other things. Unfortunately, there's no easy way I can
  " tell to return to the Make output. Vim does store 10 quickfix "lists" that
  " you can peruse with :colder and :cnewer, and but I don't think you can get
  " the number of the current list. (Though there's probably a way, the answer
  " buried somewhere deep in the Vim docs.) For now, we just back up two lists,
  " which you can do after searching to return to the Make error list. And why
  " do we back up two lists? Because when egrep first returns, the list is
  " unsorted. When we sort it (so the list of files and lines is alphabetical),
  " Vim creates a new quickfix buffer.
  "":cold 2
  " FIXME Duh! Two hours later I realize we just load the tmp file /tmp/...
  set errorformat=%A%f(%l):\ col:\ %c\ %m,%Z%m,%A%f(%l):\ %m,%Z%m
  cgetfile /tmp/flashclient_make
  :QFix!(1)
endfunction

" Restart Apache Service
" ----------------------
" F6
" 
"map <F6> <Plug>Cyclopath_Apache_Restart
noremap <F6> :call <SID>Cyclopath_Apache_Restart()<CR><CR>
inoremap <F6> <C-O>:call <SID>Cyclopath_Apache_Restart()<CR><CR>
map <silent> <unique> <script> 
  \ <Plug>Cyclopath_Apache_Restart 
  \ :call <SID>Cyclopath_Apache_Restart()<CR>
"   2. Thunk the <Plug>
function s:Cyclopath_Apache_Restart()
  :wa " Save all files
  " Clear the apache log?
  !echo > /ccp/var/log/pyserver/minnesota-apache.log
  " Restart the apache service
  if (match(system('cat /proc/version'), 'Red Hat') >= 0)
    !sudo service httpd restart
  elseif (match(system('cat /proc/version'), 'Ubuntu') >= 0)
    !sudo /etc/init.d/apache2 restart
  endif
endfunction
" FIXME Using alias re= for now, but should check if Ubuntu or Fedora and make
"       appropriate call

" Kill Apache Service
" -------------------
" SHIFT-F6
" 
" NOTE This fcn. shouldn't be needed. It was at one time, circa 2010, but I
"      don't remember why.
"map <S-F6> <Plug>Cyclopath_Apache_Kill
noremap <S-F6> :call <SID>Cyclopath_Apache_Kill()<CR><CR>
inoremap <S-F6> <C-O>:call <SID>Cyclopath_Apache_Kill()<CR><CR>
map <silent> <unique> <script> 
  \ <Plug>Cyclopath_Apache_Kill 
  \ :call <SID>Cyclopath_Apache_Kill()<CR>
"   2. Thunk the <Plug>
function s:Cyclopath_Apache_Kill()
  !ps aux | grep /usr/sbin/apache2 | awk '{print $2}' | xargs sudo kill -s 9
endfunction

" Open Flash logfile (in current Vim)
" -----------------------------------
" F7
"
"map <F7> <Plug>Cyclopath_Load_Flash_Log
noremap <F7> :call <SID>Cyclopath_Load_Flash_Log(1)<CR>
inoremap <F7> <C-O>:call <SID>Cyclopath_Load_Flash_Log(1)<CR>
noremap <C-F7> :call <SID>Cyclopath_Load_Flash_Log(0)<CR>
inoremap <C-F7> <C-O>:call <SID>Cyclopath_Load_Flash_Log(0)<CR>
map <silent> <unique> <script> 
  \ <Plug>Cyclopath_Load_Flash_Log 
  \ :call <SID>Cyclopath_Load_Flash_Log(1)<CR>
"   2. Thunk the <Plug>
function s:Cyclopath_Load_Flash_Log(open_in_quickfix)
  if a:open_in_quickfix == 0
    " The Putzy Way is just to open the flashlog in the current window:
    :edit ~/.macromedia/Flash_Player/Logs/flashlog.txt
  else
    " But The Cool Way is to show the flashlog in the error/quickfix window.
    " And we can format file-name-and-line-number lines, too, so you can
    " double-click to jump a file and line.
    " E.g.,
    "    Error: assertion failed: items/Item_Versioned.as:629
    "    at G$/assert()[/ccp/dev/cp_2628/flashclient/build/G.as:304]
    "    ...
    "    ' %.%#' (which stands for the regular expression ' .*'
"    set errorformat=%.%#
"    set errorformat=%m
    set errorformat=%.%#at\ %m[%f:%l]
    let l:curwinnr = winnr()
    " NOTE: There are two build directories: build/ and build-print/.
    silent !sed 's/ccp\/dev\/[^\/]\+\/flashclient\/build\(-print\)\?\//ccp\/dev\/cp\/flashclient\//g' 
      \ ~/.macromedia/Flash_Player/Logs/flashlog.txt 
      \ > ~/.macromedia/Flash_Player/Logs/flashlog-ccp.txt
    cgetfile ~/.macromedia/Flash_Player/Logs/flashlog-ccp.txt
    QFix!(0)
    " autocmd BufEnter doesn't work with quickfix -- trying to use G or <C-End>
    " to bounce to the bottom of the file, we only get as far as the first
    " error. But we can just get around that here. Jump to the quickfix
    " window, jump to the bottom of the file, set autoread so the buffer
    " automatically reloads as the browser appends the file, and then jump back
    " to the window where the user was.
    copen
    normal G
    set autoread
    exe l:curwinnr . "wincmd w"
  endif
endfunction

"au BufNewfile,BufRead * if &buftype == 'quickfix' 
"  \ | map <buffer> <m-f><m-l> 
"  \ :exec 'call vl#lib#quickfix#filtermod#FilterQFListByRegex('.string(input('qf: keep re: ')).', 0)'<cr>| endif
"
""func filters the quick fix list by this regular expression (only found error
""messages are affected)
"function! vl#lib#quickfix#filtermod#FilterQFListByRegex(regex, ...)
"  exec vl#lib#brief#args#GetOptionalArg("keep",string(1))
"    call vl#lib#quickfix#filtermod#ProcessQuickFixResult(
"      \ {'func': 'vl#lib#quickfix#filtermod#FilterList'
"      \ , 'args' : [ keep, a:regex ] } )
"endfunction
"
"call map(qfl, "( v:val['bufnr'] > 0 ? vl#lib#listdict#dict#SetReturn(v:val,'filename', bufname(v:val['bufnr'])) : v:val)")


" Open Flash logfile (in another Vim)
" -----------------------------------
" SHIFT-F7
"
"map <S-F7> <Plug>Cyclopath_Load_Flash_Log_New_Instance
noremap <S-F7> :call <SID>Cyclopath_Load_Flash_Log_New_Instance()<CR><CR>
inoremap <S-F7> <C-O>:call <SID>Cyclopath_Load_Flash_Log_New_Instance()<CR><CR>
" NOTE Using two <CR>s so the output and the message, 
"      _Press ENTER or type command to continue_, are dismissed
map <silent> <unique> <script> 
  \ <Plug>Cyclopath_Load_Flash_Log_New_Instance 
  \ :call <SID>Cyclopath_Load_Flash_Log_New_Instance()<CR><CR>
"   2. Thunk the <Plug>
function s:Cyclopath_Load_Flash_Log_New_Instance()
  !gvim --servername ALPHA --remote-silent
    \ ~/.macromedia/Flash_Player/Logs/flashlog.txt
endfunction

" The Flash logfile is continuously appended by the Flash plugin, which 
" produces warnings in Vim and reloading. To avoid these messages (e.g.,
" Warning: File "{filename}" has changed since editing started) and the 
" subsequent prompt, set autoread. See :h W11 for more details.
autocmd BufRead ~/.macromedia/Flash_Player/Logs/flashlog.txt set autoread
autocmd BufRead ~/.macromedia/Flash_Player/Logs/flashlog.txt normal G
autocmd BufEnter,BufRead ~/.macromedia/Flash_Player/Logs/flashlog.txt match none
"autocmd BufEnter,BufRead flashlog.txt set autoread
"autocmd BufEnter,BufRead flashlog.txt normal G
"autocmd BufEnter,BufRead flashlog.txt normal <C-End>
" G and <C-End> do the same thing for remote window, but in quickfix, goes to
" first error... hmmmmm

" Truncate Flash logfile
" ----------------------
" CTRL-SHIFT-F7
"
noremap <C-S-F7> :call <SID>Cyclopath_Flash_Log_Truncate()<CR><CR>
inoremap <C-S-F7> <C-O>:call <SID>Cyclopath_Flash_Log_Truncate()<CR><CR>
" NOTE Using two <CR>s so the output and the message, 
"      _Press ENTER or type command to continue_, are dismissed
map <silent> <unique> <script> 
  \ <Plug>Cyclopath_Flash_Log_Truncate 
  \ :call <SID>Cyclopath_Flash_Log_Truncate()<CR><CR>
"   2. Thunk the <Plug>
function s:Cyclopath_Flash_Log_Truncate()
  !echo > ~/.macromedia/Flash_Player/Logs/flashlog.txt
endfunction

" Open the pyserver crash dump and request in the Quickfix window
" ---------------------------------------------------------------
" F8s
"

"Traceback (most recent call last):
"  File "/ccp/dev/cp/pyserver/gwis/request.py", line 136, in process_req
"    self.command_process_req()
"  [...]
"  File "/ccp/dev/cp/pyserver/item/group_item_access.py", line 328, in search_get_sql
"    assert(username)
"AssertionError

"Traceback (most recent call last):
"  File "/ccp/dev/cp/pyserver/gwis/request.py", line 128, in process_req
"    self.command_process_req()
"  [...]
"  File "/ccp/dev/cp/pyserver/gwis/command_/commit.py", line 553
"    b = a + 2
"   ^
"IndentationError: unexpected indent

" NOTE See "set errorformat=..." in dubsacks.vim to the Python Quickfix def'n
"map <F8> <Plug>Cyclopath_Load_Pyserver_Dump
noremap <F8> :call <SID>Cyclopath_Load_Pyserver_Dump()<CR>
inoremap <F8> <C-O>:call <SID>Cyclopath_Load_Pyserver_Dump()<CR>
map <silent> <unique> <script> 
  \ <Plug>Cyclopath_Load_Pyserver_Dump 
  \ :call <SID>Cyclopath_Load_Pyserver_Dump()<CR>
"   2. Thunk the <Plug>
function s:Cyclopath_Load_Pyserver_Dump()
  " FIXME This is wrong -- Do we need to restore the old errorformat later?
  " FIXME Should this go in a "autocmd BufRead..." ??
  " See quickfix.txt.gz for help w/ this string (:h efm & :h errorformat)
  " "%.%#"  (".*")   matches a (possibly empty) string
  set errorformat=%A\ %.%#File\ \"%f\"\\,\ line\ %l\\,\ in\ %m,%Z%m,%A\ %.%#File\ \"%f\"\\,\ line\ %l,%Z%m
  ":cfile /tmp/pyserver_dumps/dump.EXCEPT
  :cgetfile /ccp/var/log/pyserver_dumps/dump.EXCEPT
  ":QFix!
  :QFix!(0)
  ":QFix(1, 1)
endfunction

noremap <C-F8> :call <SID>Cyclopath_Load_Pyserver_Dump_Request()<CR>
inoremap <C-F8> <C-O>:call <SID>Cyclopath_Load_Pyserver_Dump_Request()<CR>
map <silent> <unique> <script> 
  \ <Plug>Cyclopath_Load_Pyserver_Dump_Request 
  \ :call <SID>Cyclopath_Load_Pyserver_Dump_Request()<CR>
"   2. Thunk the <Plug>
function s:Cyclopath_Load_Pyserver_Dump_Request()
  set errorformat=%m
  :cgetfile /ccp/var/log/pyserver_dumps/dump.REQUEST
  :QFix!(0)
endfunction

autocmd BufRead /ccp/var/log/pyserver_dumps/dump.EXCEPT set autoread
autocmd BufRead /ccp/var/log/pyserver_dumps/dump.EXCEPT normal G
autocmd BufEnter,BufRead /ccp/var/log/pyserver_dumps/dump.EXCEPT match none

autocmd BufRead /ccp/var/log/pyserver_dumps/dump.REQUEST set autoread
autocmd BufRead /ccp/var/log/pyserver_dumps/dump.REQUEST normal G
autocmd BufEnter,BufRead /ccp/var/log/pyserver_dumps/dump.REQUEST match none

" Open the apache log file in the Quickfix or current window
" ----------------------------------------------------------
" F9s
"

noremap <F9> :call <SID>Cyclopath_Load_Apache_Log_File(1)<CR>
inoremap <F9> <C-O>:call <SID>Cyclopath_Load_Apache_Log_File(1)<CR>
noremap <C-F9> :call <SID>Cyclopath_Load_Apache_Log_File(0)<CR>
inoremap <C-F9> <C-O>:call <SID>Cyclopath_Load_Apache_Log_File(0)<CR>
map <silent> <unique> <script> 
  \ <Plug>Cyclopath_Load_Apache_Log_File 
  \ :call <SID>Cyclopath_Load_Apache_Log_File(1)<CR>
"   2. Thunk the <Plug>
function s:Cyclopath_Load_Apache_Log_File(open_in_quickfix)
  if a:open_in_quickfix == 0
    " The Putzy Way is just to open the flashlog in the current window:
    :edit /ccp/var/log/pyserver/minnesota-apache.log
  else
    "set errorformat=%m
    " C.f. Cyclopath_Load_Pyserver_Dump, but leading crap ok (i.e., timestamp,
    "      logging level, logger name, and octothorphe).
    set errorformat=%A\%.%#File\ \"%f\"\\,\ line\ %l\\,\ in\ %m,%Z%m,%A\%.%#File\ \"%f\"\\,\ line\ %l,%Z%m
    :cgetfile /ccp/var/log/pyserver/minnesota-apache.log
    :QFix!(0)
  endif
endfunction

autocmd BufRead /ccp/var/log/pyserver/minnesota-apache.log set autoread
autocmd BufRead /ccp/var/log/pyserver/minnesota-apache.log normal G
autocmd BufEnter,BufRead /ccp/var/log/pyserver/minnesota-apache.log match none

" Truncate Apache logfile
" -----------------------
" CTRL-SHIFT-F9
"
noremap <C-S-F9> :call <SID>Cyclopath_Apache_Log_Truncate()<CR><CR>
inoremap <C-S-F9> <C-O>:call <SID>Cyclopath_Apache_Log_Truncate()<CR><CR>
" NOTE Using two <CR>s so the output and the message, 
"      _Press ENTER or type command to continue_, are dismissed
map <silent> <unique> <script> 
  \ <Plug>Cyclopath_Apache_Log_Truncate 
  \ :call <SID>Cyclopath_Apache_Log_Truncate()<CR><CR>
"   2. Thunk the <Plug>
function s:Cyclopath_Apache_Log_Truncate()
  !echo > /ccp/var/log/pyserver/minnesota-apache.log
endfunction

" Open the miscellany log file in the Quickfix or current window
" --------------------------------------------------------------
" F10s
"

noremap <F10> :call <SID>Cyclopath_Load_Misc_Log_File(1)<CR>
inoremap <F10> <C-O>:call <SID>Cyclopath_Load_Misc_Log_File(1)<CR>
noremap <C-F10> :call <SID>Cyclopath_Load_Misc_Log_File(0)<CR>
inoremap <C-F10> <C-O>:call <SID>Cyclopath_Load_Misc_Log_File(0)<CR>
map <silent> <unique> <script> 
  \ <Plug>Cyclopath_Load_Misc_Log_File 
  \ :call <SID>Cyclopath_Load_Misc_Log_File(1)<CR>
"   2. Thunk the <Plug>
function s:Cyclopath_Load_Misc_Log_File(open_in_quickfix)
  if a:open_in_quickfix == 0
    " The Putzy Way is just to open the flashlog in the current window:
    :edit /ccp/var/log/pyserver/minnesota-misc.log
  else
    "set errorformat=%m
    " C.f. Cyclopath_Load_Pyserver_Dump, but leading crap ok (i.e., timestamp,
    "      logging level, logger name, and octothorphe).
    set errorformat=%A\%.%#File\ \"%f\"\\,\ line\ %l\\,\ in\ %m,%Z%m,%A\%.%#File\ \"%f\"\\,\ line\ %l,%Z%m
    :cgetfile /ccp/var/log/pyserver/minnesota-misc.log
    :QFix!(0)
  endif
endfunction

autocmd BufRead /ccp/var/log/pyserver/minnesota-misc.log set autoread
autocmd BufRead /ccp/var/log/pyserver/minnesota-misc.log normal G
autocmd BufEnter,BufRead /ccp/var/log/pyserver/minnesota-misc.log match none

" Truncate miscellany logfile
" ---------------------------
" CTRL-SHIFT-F10
"
noremap <C-S-F10> :call <SID>Cyclopath_Misc_Log_Truncate()<CR><CR>
inoremap <C-S-F10> <C-O>:call <SID>Cyclopath_Misc_Log_Truncate()<CR><CR>
" NOTE Using two <CR>s so the output and the message, 
"      _Press ENTER or type command to continue_, are dismissed
map <silent> <unique> <script> 
  \ <Plug>Cyclopath_Misc_Log_Truncate 
  \ :call <SID>Cyclopath_Misc_Log_Truncate()<CR><CR>
"   2. Thunk the <Plug>
function s:Cyclopath_Misc_Log_Truncate()
  !echo > /ccp/var/log/pyserver/minnesota-misc.log
endfunction


" Open the routed log file in the Quickfix or current window
" --------------------------------------------------------------
" F11s
"

noremap <F11> :call <SID>Cyclopath_Load_Routed_Log_File(1)<CR>
inoremap <F11> <C-O>:call <SID>Cyclopath_Load_Routed_Log_File(1)<CR>
noremap <C-F11> :call <SID>Cyclopath_Load_Routed_Log_File(0)<CR>
inoremap <C-F11> <C-O>:call <SID>Cyclopath_Load_Routed_Log_File(0)<CR>
map <silent> <unique> <script> 
  \ <Plug>Cyclopath_Load_Routed_Log_File 
  \ :call <SID>Cyclopath_Load_Routed_Log_File(1)<CR>
"   2. Thunk the <Plug>
function s:Cyclopath_Load_Routed_Log_File(open_in_quickfix)
  if a:open_in_quickfix == 0
    " The Putzy Way is just to open the flashlog in the current window:
    :edit /ccp/var/log/pyserver/minnesota-routed.log
  else
    "set errorformat=%m
    " C.f. Cyclopath_Load_Pyserver_Dump, but leading crap ok (i.e., timestamp,
    "      logging level, logger name, and octothorphe).
    set errorformat=%A\%.%#File\ \"%f\"\\,\ line\ %l\\,\ in\ %m,%Z%m,%A\%.%#File\ \"%f\"\\,\ line\ %l,%Z%m
    :cgetfile /ccp/var/log/pyserver/minnesota-routed.log
    :QFix!(0)
  endif
endfunction

autocmd BufRead /ccp/var/log/pyserver/minnesota-routed.log set autoread
autocmd BufRead /ccp/var/log/pyserver/minnesota-routed.log normal G
autocmd BufEnter,BufRead /ccp/var/log/pyserver/minnesota-routed.log match none

" Truncate Routed logfile
" -----------------------
" CTRL-SHIFT-F11
"
noremap <C-S-F11> :call <SID>Cyclopath_Routed_Log_Truncate()<CR><CR>
inoremap <C-S-F11> <C-O>:call <SID>Cyclopath_Routed_Log_Truncate()<CR><CR>
" NOTE Using two <CR>s so the output and the message, 
"      _Press ENTER or type command to continue_, are dismissed
map <silent> <unique> <script> 
  \ <Plug>Cyclopath_Routed_Log_Truncate 
  \ :call <SID>Cyclopath_Routed_Log_Truncate()<CR><CR>
"   2. Thunk the <Plug>
function s:Cyclopath_Routed_Log_Truncate()
  !echo > /ccp/var/log/pyserver/minnesota-routed.log
endfunction

" Open the Mr. Do! log file in the Quickfix or current window
" -----------------------------------------------------------
" F12s
"

noremap <F12> :call <SID>Cyclopath_Load_Mr_Do_Log_File(1)<CR>
inoremap <F12> <C-O>:call <SID>Cyclopath_Load_Mr_Do_Log_File(1)<CR>
noremap <C-F12> :call <SID>Cyclopath_Load_Mr_Do_Log_File(0)<CR>
inoremap <C-F12> <C-O>:call <SID>Cyclopath_Load_Mr_Do_Log_File(0)<CR>
map <silent> <unique> <script> 
  \ <Plug>Cyclopath_Load_Mr_Do_Log_File 
  \ :call <SID>Cyclopath_Load_Mr_Do_Log_File(1)<CR>
"   2. Thunk the <Plug>
function s:Cyclopath_Load_Mr_Do_Log_File(open_in_quickfix)
  if a:open_in_quickfix == 0
    " The Putzy Way is just to open the flashlog in the current window:
    :edit /ccp/var/log/pyserver/minnesota-mr_do.log
  else
    "set errorformat=%m
    " C.f. Cyclopath_Load_Pyserver_Dump, but leading crap ok (i.e., timestamp,
    "      logging level, logger name, and octothorphe).
    set errorformat=%A\%.%#File\ \"%f\"\\,\ line\ %l\\,\ in\ %m,%Z%m,%A\%.%#File\ \"%f\"\\,\ line\ %l,%Z%m
    :cgetfile /ccp/var/log/pyserver/minnesota-mr_do.log
    :QFix!(0)
  endif
endfunction

autocmd BufRead /ccp/var/log/pyserver/minnesota-mr_do.log set autoread
autocmd BufRead /ccp/var/log/pyserver/minnesota-mr_do.log normal G
autocmd BufEnter,BufRead /ccp/var/log/pyserver/minnesota-mr_do.log match none

" Truncate Mr_Do logfile
" ----------------------
" CTRL-SHIFT-F12
"
noremap <C-S-F12> :call <SID>Cyclopath_Mr_Do_Log_Truncate()<CR><CR>
inoremap <C-S-F12> <C-O>:call <SID>Cyclopath_Mr_Do_Log_Truncate()<CR><CR>
" NOTE Using two <CR>s so the output and the message, 
"      _Press ENTER or type command to continue_, are dismissed
map <silent> <unique> <script> 
  \ <Plug>Cyclopath_Mr_Do_Log_Truncate 
  \ :call <SID>Cyclopath_Mr_Do_Log_Truncate()<CR><CR>
"   2. Thunk the <Plug>
function s:Cyclopath_Mr_Do_Log_Truncate()
  !echo > /ccp/var/log/pyserver/minnesota-mr_do.log
endfunction

" Save the working project to your work machine
" ---------------------------------------------
" F??
"
" FIXME
" function cpput () {

" Restart the Cyclopath Route Daemon
" ----------------------------------
" F??
"
" FIXME
"rd () {
"  pushd $cp/pyserver
"  sudo -u www-data INSTANCE=minnesota ./routedctl $1
"  popd
"  return 0
"}

" Truncate All Logfiles
" ---------------------
noremap <C-S-F8> :call <SID>Cyclopath_All_Logs_Truncate()<CR><CR>
inoremap <C-S-F8> <C-O>:call <SID>Cyclopath_All_Logs_Truncate()<CR><CR>
" NOTE Using two <CR>s so the output and the message, 
"      _Press ENTER or type command to continue_, are dismissed
map <silent> <unique> <script> 
  \ <Plug>Cyclopath_All_Logs_Truncate 
  \ :call <SID>Cyclopath_All_Logs_Truncate()<CR><CR>
"   2. Thunk the <Plug>
function s:Cyclopath_All_Logs_Truncate()
  " <C-S-F7>
  :call <SID>Cyclopath_Flash_Log_Truncate()
  " <C-S-F9>
  :call <SID>Cyclopath_Misc_Log_Truncate()
  " <C-S-F10>
  :call <SID>Cyclopath_Apache_Log_Truncate()
  " <C-S-F11>
  :call <SID>Cyclopath_Routed_Log_Truncate()
  " <C-S-F12>
  :call <SID>Cyclopath_Mr_Do_Log_Truncate()
endfunction

" ---------------------------------------------------------------------------

" Load the tags files
" ----------------------------------

autocmd BufRead *.py set 
  \ tags=$cp/pyserver/tags,$cp/services/tags,$cp/scripts/tags

autocmd BufRead *.as set 
  \ tags=$cp/flashclient/tags
autocmd BufRead *.mxml set
  \ tags=$cp/flashclient/tags

" Ctrl-] jumps to the tag under the cursor, but only in normal mode. Let's
" make it work in Insert mode, too.
"noremap <silent> <C-]> :call <SID>GrepPrompt_Auto_Prev_Location("<C-R><C-W>")<CR>
inoremap <silent> <C-]> <C-O>:tag <C-R><C-W><CR>
"cnoremap <silent> <C-]> <C-C>:call <SID>GrepPrompt_Auto_Prev_Location("<C-R><C-W>")<CR>
"onoremap <silent> <C-]> <C-C>:call <SID>GrepPrompt_Auto_Prev_Location("<C-R><C-W>")<CR>
" Selected word
vnoremap <silent> <C-]> :<C-U>
  \ <CR>gvy
  \ :execute "tag " . @@<CR>

" Ctrl-t jumps back after a Ctrl-], but I have two issues with this. One,
" I've got Ctrl-t mapped to Transpose Characters in Insert mode. But more
" importantly, Two, Why isn't this Ctrl-[? That seems intuitive, and it's
" closer to the key you just pressed (by default, Ctrl-[ does the same thing as
" <Esc>, and I've already got enough escapes mapped).

" Hmpf. I cannot get this to work right now. It remaps all my other Escapes,
" too... and <C-}>, <C-S-]> and <C-S-}> don't work, either
"cnoremap <C-[> :normal <C-t><CR>
"inoremap <C-[> <C-O>:normal <C-t><CR>
"" NOTE When text selected, C-F3 same as plain-ole F3
"vnoremap <C-[> :<C-U>
"  \ <CR>gvy
"  \ gV
"  \ :normal <C-t><CR>
noremap <M-]> :normal <C-t><CR>
inoremap <M-]> <C-O>:normal <C-t><CR>
" NOTE When text selected, C-F3 same as plain-ole F3
vnoremap <M-]> :<C-U>
  \ <CR>gvy
  \ gV
  \ :normal <C-t><CR>

" ctags
" cd $cp/pyserver
" ctags -R
" cd $cp/flashclient
" # NOTE --exclude=build is all that works, not flashclient/build or 
" #      even /build or build/. I even tried using "./quotes".
" #      But if you run the following command with --verbose=yes
" #        ctags -R --exclude=build --verbose=yes
" #      You can verify that the build directory (and only the build directory)
" #      is excluded by looking for the line
" #        excluding "build"
" ctags -R --exclude=build

"       vi -t tag   Start vi and position the cursor at the  file  and  line
"                   where "tag" is defined.
"
"       :ta tag     Find a tag.
"
"       Ctrl-]      Find the tag under the cursor.
"
"       Ctrl-T      Return  to  previous  location  before  jump to tag

"Jumping to a tag

"    * You can use the 'tag' ex command. For example, the command ':tag <tagname>' will jump to the tag named <tagname>.
 "   * You can position the cursor over a tag name and then press Ctrl-].
 "   * You can visually select a text and then press Ctrl-] to jump to the tag matching the selected text.
 "   * You can click on the tag name using the left mouse button, while pressing the <Ctrl> key.
 "   * You can press the g key and then click on the tag name using the left mouse button.
 "   * You can use the 'stag' ex command, to open the tag in a new window. For example, the command ':stag func1' will open the func1 definition in a new window.
 "   * You can position the cursor over a tag name and then press Ctrl-W ]. This will open the tag location in a new window. 
"
"Help: :tag, Ctrl-], v_CTRL_], <C-LeftMouse>, g<LeftMouse>, :stag, Ctrl-W_] 

"    * You can list all the tags matching a particular regular expression pattern by prepending the tag name with the '/' search character. For example, 
"
":tag /<pattern>
":stag /<pattern>
":ptag /<pattern>
":tselect /<pattern>
":tjump /<pattern>
":ptselect /<pattern>
":ptjump /<pattern>

" Vim Wild Menu (wildmenu)
" ------------------------
" In Insert mode, use Ctrl-P and Ctrl-N to cycle through an auto-completion
" list from your tags file.

" FIXME Do I need this?:
set wildmode=list:longest,full

" From 
" http://vim-taglist.sourceforge.net/extend.html
" actionscript language
let tlist_actionscript_settings = 'actionscript;c:class;f:method;p:property;v:variable'

" FIXME add ctags to Makefile instead of daily.sh
"CTAGLANGS = --langdef=actionscript \
"--langmap=actionscript:.as \
"--regex-actionscript='/^[ \t]*[(private| public|static) ( \t)]*function[\t]+([A-Za-z0-9_]+)[ \t]*\(/\1/f, function, functions/' \
"--regex-actionscript='/^[ \t]*[(public) ( \t)]*function[ \t]+(set|get) [ \t]+([A-Za-z0-9_]+)[ \t]*\(/\1 \2/p,property, properties/' \
"--regex-actionscript='/^[ \t]*[(private| public|static) ( \t)]*var[  \t]+([A-Za-z0-9_]+)[\t]*/\1/v,variable, variables/' \
"--regex-actionscript='/.*\.prototype \.([A-Za-z0-9 ]+)=([ \t]?)function( [  \t]?)*\(/\1/f,function, functions/' \
"--regex-actionscript='/^[ \t]*class[ \t]+([A-Za-z0-9_]+)[ \t]*/\1/c,class, classes/'
"
".PHONY: ctags
"ctags:
"-rm -f TAGS
"find . -name "*.as" -or -name "*.mxml" | ctags -eL - $(CTAGLANGS)
"
" FIXME The article at http://vim-taglist.sourceforge.net/extend.html
"       is wrong
"       Specifically, it doesn't recognize override or protected, and set|get
"       is broken. See my .ctags file for the appropriate command.


"--regex-actionscript=/^[ \t]*[(override)[ \t]+]?[(private|protected|public)][ \t]+[(static)[ \t]+]?function[ \t]+[(set|get)]*[ \t]+([A-Za-z0-9_]+)[ \t]*\(/\1 \2/p,property, properties/

" ***

" Link to bug page of bug number under cursor or selected (open-issue).
" :!firefox http://bugs.cyclopath.org/show_bug.cgi?id=2825 &> /dev/null
" Test the three modes: http://google.com/show_bug.cgi?id=2825 &> /dev/null
noremap <silent> <Leader>i
  \ :!firefox http://bugs.cyclopath.org/show_bug.cgi?id=<C-R><C-W>
  \ &> /dev/null<CR><CR>
inoremap <silent> <Leader>i
  \ <C-O>:!firefox http://bugs.cyclopath.org/show_bug.cgi?id=<C-R><C-W>
  \ &> /dev/null<CR><CR>
" Interesting: C-U clears the command line, which contains cruft, e.g., '<,'>
" gv selects the previous Visual area.
" y yanks the selected text into the default register.
" <Ctrl-R>" puts the yanked text into the command line.
vnoremap <silent> <Leader>i :<C-U>
  \ <CR>gvy
  \ :!firefox http://bugs.cyclopath.org/show_bug.cgi?id=<C-R>"
  \ &> /dev/null<CR><CR>
" Test the three modes using: https://github.com/p6a

" ***

