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

" Convert HTML link to Markdown link
" --------------------------------
" E.g.,
"   http://www.google.com/a/cpanel/domain/new
" becomes
"   [http://www.google.com/a/cpanel/domain/new](http://www.google.com/a/cpanel/domain/new)
noremap <Leader>l :let tmp=@/<CR>:s/\(http[s]\?:\/\/[^ \t()\[\]]\+\)/[\1](\1)/ge<CR>:let @/=tmp<CR>
" TODO In Markdown, surround the link in angle 
"      brackets does the same thing, e.g.,
"        <http://www.google.com/a/cpanel/domain/new>
"      So maybe \L adds brackets
"      and \l converts to 
"        [](http://www.google.com/a/cpanel/domain/new)
"      and puts the cursor in the brackets
"      TODO There's also the [reference][ref-id] format

