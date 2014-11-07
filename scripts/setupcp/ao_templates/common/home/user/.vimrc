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
"  Vim startup script for gVim on Windows.
"  (Native gVim, not Cygwin gVim, 'cause 
"   who wants to run X to get mouse?)
" ----------------------------------------

" Author: Landon Bouma <dubsacks.vim@retrosoft.com>
" Version: 0.1 / Summer Aught Nine
" Version: 0.2 / Winter X

" NOTE!! If you edit this file, be sure to delete
"        ~/vimfiles/Session.vim
"        (If you have dubsacks.vim loaded, you can 
"         also run <Alt-f>e to close all windows 
"         and then <Alt-f>x to quit; dubsacks will 
"         destroy Session.vim for you.)

" ----------------------------------------
"  OS Bootstrap
" ----------------------------------------

" The buck stops here.
"      ... or does it?
" Actually, it does; we're responsible for 
" loading the application's startup script 
" if the user's startup script (this script) 
" exists.
if filereadable($VIMRUNTIME . "/../.vimrc")
  " This is where the startup file lives in 
  " 'nix, but in Cygwin, it's not created by 
  " default (but I can't vouch for other 
  " distributions)
  source $VIMRUNTIME/../.vimrc
elseif filereadable($VIMRUNTIME . "/../_vimrc")
  " This file exists and *must* be sourced 
  " for native Windows gVim to work properly
  source $VIMRUNTIME/../_vimrc
else
  " Well, we could complain, but in some 
  " distros the application startup file
  " doesn't exist. So we won't bother with 
  " this, will we?:
  "  call confirm(
  "   \ 'vimrc: Cannot find VIMRUNTIME''s vimrc, '
  "   \ . 'i.e., $VIMRUNTIME/../[\.|_]vimrc', 'OK')
endif

" ----------------------------------------
"  Dubsack's Tool Kit
" ----------------------------------------
" Yes, the DTK is an overlay, or a pretty sizable 
" configuration of Vim. No, it's not Cream
" (http://cream.sourceforge.net/); it's not a 
" simplified Vim meant for the masses. You still 
" have to learn Vim, but that means you still get 
" the power of Vim. The DTK is just here so you 
" don't have to go fishing for all the plugins you 
" want (or didn't know you wanted ;), and so all 
" your favorite commands are mapped to your 
" favorite keystrokes. The DTK keeps remapping of 
" existing keystrokes to a minimum -- in other 
" words, you're not re-learning Vim, you're just 
" learning some new commands for Vim (unless, of 
" course, you've already got your own vimrc file 
" and it conflicts with the DTK, in which case 
" it's up to you to fix any conflicts =).
if filereadable($HOME . "/.vim/plugin/dubsacks.vim")
  source $HOME/.vim/plugin/dubsacks.vim
elseif filereadable($USERPROFILE . "/vimfiles/plugin/dubsacks.vim")
  source $USERPROFILE/vimfiles/plugin/dubsacks.vim
else
  call confirm(
    \ 'vimrc: Cannot find the DTK: '
    \ . 'i.e., ' . $HOME . '/vimfiles/plugin/dubsacks.vim')
endif

