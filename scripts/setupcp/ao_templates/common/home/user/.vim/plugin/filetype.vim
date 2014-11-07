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

" FIXME This file is... Not Very Vim
"       See http://vim.wikia.com/wiki/Keep_your_vimrc_file_clean, and 
"         :help vimfiles, :help ftplugin-overrule, :help after-directory
"       I should use the ~/.vim/ftplugin directory and replace all the 
"       autocmd's below with one file for each filetype.

" ------------------------------------------
"  Filetypes
" ------------------------------------------

" Author: Landon Bouma <dubsacks.vim@retrosoft.com>
" Version: 0.0.1 / Summer Aught Nine
" License: What License?

" NOTE!! If you edit this file, be sure to delete
"        ~/vimfiles/Session.vim

" Startup
" ------------------------

" Load this script just once
if exists("plugin_filetypes_vim")
  finish
endif
let plugin_filetypes_vim = 1

" Markdown Syntax
" --------------------------------
" http://daringfireball.net/projects/markdown/
augroup markdown
  au! BufRead,BufNewFile *.mkd setfiletype mkd
  autocmd BufRead *.mkd set ai formatoptions=tcroqn2 comments=n:>
  " Also map *.txt files, since you 
  " love Markdown so much
  " au! BufRead,BufNewFile *.txt 
  "   \ set nowrap sw=2 sts=2 ts=8
  "au BufRead,BufNewFile *.txt setfiletype mkd
  "autocmd BufRead *.txt set ai formatoptions=tcroqn2 comments=n:>
augroup END
"augroup mkd
"  autocmd BufRead *.mkd set ai formatoptions=tcroqn2 comments=n:>
"augroup END

" I keep waffling on this, but I can get used to 
" naming my text files *.mkd, I suppose...
"au BufRead,BufNewFile *.txt setfiletype mkd

" Textile Syntax
" --------------------------------
" Map *.textile files to the syntax highlighter
augroup textile
  au BufRead,BufNewFile *.textile setf textile
augroup END

" NSIS Installer Script Syntax
" --------------------------------
" The Nullsoft Scriptable Installer System 
" makes Windows .exe executables ('cause  
" Windows isn't cool enough for gems).
" The defauft NSIS file extension is .nsi, 
" but convention says to use .nsh for 
" include (header?) files.
augroup nsis
  au BufRead,BufNewFile *.nsh setfiletype nsis
augroup END

" ActionScript/MXML/Flex Highlighting
" --------------------------------
" (No comment.)
" (Okay, one comment:)
" Specify coments and additional formatoptions 
" so that writing comments is easier (Vim indents 
" and adds the comment prefix).
" FIXME Mayhaps this belongs in the actionscript and 
"       mxml syntax files?
" formatoptions: 
"   c = Auto-wrap comments using textwidth, inserting comment leader
"   r = Automatically insert comment leader after <Enter> in Insert mode
"   o = Automatically insert comment leader after 'o' or 'O' in normal mode
"   q = Allow formatting of comments with "gq"
"       FIXME I have <F1> mapped to !par, so I probably don't care about q
"   l = Long lines are not broken in Insert mode (if already long when edited)
" NOTE The first two sb/m/ex force smart formatting of FIXME and NOTE
"      comments. I'm not quite sure this is the place for it, but it 
"      works quite nicely.
" NOTE The funny ex://- is to get around a problem in Vim: if the string isn't 
"      unique, Vim misinterprets our intention and then auto-commenting doesn't
"      work well. We could use a bunch of spaces (i.e., ex://\ \ \ \ \ \ \ ) to
"      make ex: unique, but then we can't kill our comment with a single 
"      keystroke. So instead we make a bogus ex: so we can kill it with a dot.

" NOTE I tried to get //. to work w/ just :// but it's not having it. That is, 
"          sb://,mb://,ex://.

autocmd BufRead *.as set 
  \ filetype=actionscript 
  \ comments=sb://\ FIXME:,m://\ \ \ \ \ \ \ \ ,ex://.,sb://\ NOTE:,m://\ \ \ \ \ \ \ ,ex://.,sb://\ FIXME,m://\ \ \ \ \ \ \ ,ex://.,sb://\ NOTE,m://\ \ \ \ \ \ ,ex://.,s:/*\ FIXME:,m:*\ \ \ \ \ \ \ \ \ ,ex:*/,s:/*\ NOTE:,m:*\ \ \ \ \ \ \ \ ,ex:*/,://,s:/*\ FIXME,m:*\ \ \ \ \ \ \ \ ,ex:*/,s:/*\ NOTE,m:*\ \ \ \ \ \ \ ,ex:*/,://,s1:/*,mb:**,ex:*/
  \ formatoptions+=croql
  \ smartindent
  \ indentexpr=
  \ indentkeys=0{,0},!^F,o,O,e,<:>,=elif,=except
" This is messing me up: XML indenting causes both lines to re-indent
"    indentexpr=XmlIndentGet(v:lnum,1)
autocmd BufRead *.mxml set
  \ filetype=mxml 
  \ comments=sb://\ FIXME:,m://\ \ \ \ \ \ \ \ ,ex://.,sb://\ NOTE:,m://\ \ \ \ \ \ \ ,ex://.,sb://\ FIXME,m://\ \ \ \ \ \ \ ,ex://.,sb://\ NOTE,m://\ \ \ \ \ \ ,ex://.,s:/*\ FIXME:,m:*\ \ \ \ \ \ \ \ \ ,ex:*/,s:/*\ NOTE:,m:*\ \ \ \ \ \ \ \ ,ex:*/,://,s:/*\ FIXME,m:*\ \ \ \ \ \ \ \ ,ex:*/,s:/*\ NOTE,m:*\ \ \ \ \ \ \ ,ex:*/,sb:<!--\ FIXME:,m:\ \ \ \ \ \ \ \ \ \ \ \ ,ex:-->,sb:<!--\ NOTE:,m:\ \ \ \ \ \ \ \ \ \ \ ,ex:-->,sb:<!--\ FIXME,m:\ \ \ \ \ \ \ \ \ \ \ ,ex:-->,sb:<!--\ NOTE,m:\ \ \ \ \ \ \ \ \ \ ,ex:-->,://,s1:/*,mb:**,ex:*/,sb:<!--,m:\ \ \ \ \ ,ex:-->
  \ formatoptions+=croql
  \ smartindent
  \ indentexpr=MxmlIndentGet(v:lnum)
  \ indentkeys=o,O,<>>,{,}
" 2013.04.16: Added mxml indent fcn., which is the only way to fix mxml
" indenting... (is using a custom indent file). See:
"   /usr/share/vim/vim73/indent/python.vim
"   :h C-indenting
" [lb] notes, here's Vim's MXML default:
"  \ indentexpr=XmlIndentGet(v:lnum,1)
"  \ indentkeys=o,O,*<Return>,<>>,<<>,/,{,}
"
" MAYBE: Should we move mxml-indent.vim to to ~/.vim/indent?

" Add special FIXME and NOTE comments w/ smart indenting to Python and Vim
" FIXME If you reformat w/ par, you lose your special formatting...
" --------------------------------
" Following are the original comments for the specified filetypes
"   for filetype=vim
"     comments=sO:" -,mO:"  ,eO:"",:"
"   You have to escape this string to set it, i.e.,
"     set comments=sO:\"\ -,mO:\"\ \ ,eO:\"\",:\"
autocmd BufRead *.vim set 
  \ comments=sb:\"\ FIXME:,m:\"\ \ \ \ \ \ \ ,ex:\".,sb:\"\ NOTE:,m:\"\ \ \ \ \ \ ,ex:\".,sb:\"\ FIXME,m:\"\ \ \ \ \ \ ,ex:\".,sb:\"\ NOTE,m:\"\ \ \ \ \ ,ex:\".,sO:\"\ -,mO:\"\ \ ,eO:\"\",:\"
  \ formatoptions+=croql
"   for filetype=python
"     comments=s1:/*,mb:*,ex:*/,://,b:#,:XCOMM,n:>,fb:-
" NOTE I'm not sure why python considers /* */ a comment...
autocmd BufRead *.py set 
  \ comments=sb:#\ FIXME:,m:#\ \ \ \ \ \ \ \ ,ex:#.,sb:#\ NOTE:,m:#\ \ \ \ \ \ \ ,ex:#.,sb:#\ FIXME,m:#\ \ \ \ \ \ \ ,ex:#.,sb:#\ NOTE,m:#\ \ \ \ \ \ ,ex:#.,b:#
  \ formatoptions+=croql

autocmd BufRead *.map set
  \ filetype=python 
  \ formatoptions+=croql

" smartindent is too smart for octothorpes: it removes any indentation,
" assuming you're about a write a C-style macro. Nuts to this, I say!
" (Per the documentation (:h 'smartindent'), the ^H you see below is generated
" by typing Ctrl-q Ctrl-h (Ctrl-V if dosmode isn't enabled, which makes Ctrl-V
" paste).) (And you can't copy/paste this command to execute it, if you type :
" you'll have to Ctrl-q Ctrl-h the special character.)
autocmd BufRead *.py inoremap # X#
"inoremap # X#

" Do the same for Bash shell script files
autocmd BufRead *.sh set 
  \ comments=sb:#\ FIXME:,m:#\ \ \ \ \ \ \ ,ex:#.,sb:#\ NOTE:,m:#\ \ \ \ \ \ ,ex:#.,sb:#\ FIXME,m:#\ \ \ \ \ \ ,ex:#.,sb:#\ NOTE,m:#\ \ \ \ \ ,ex:#.,s1:/*,mb:**,ex:*/,://,b:#,:XCOMM,n:>,fb:-
  \ formatoptions+=croql
  \ smartindent

" Specify nosmartindent, else Vim won't tab your octothorpes
autocmd BufEnter,BufRead *.sh setlocal tabstop=2 shiftwidth=2 tw=79 nosmartindent

"autocmd BufRead *.sql set
"  \ comments=sb:--\ FIXME:,m:--\ \ \ \ \ \ \ \ ,ex:--.,sb:--\ NOTE:,m:--\ \ \ \ \ \ \ ,ex:--.,sb:--\ FIXME,m:--\ \ \ \ \ \ \ ,ex:--.,sb:--\ NOTE,m:--\ \ \ \ \ \ ,ex:--.,s:/*\ FIXME:,m:*\ \ \ \ \ ,ex:*/,s:/*\ NOTE:,m:*\ \ \ \ ,ex:*/,:--,s:/*\ FIXME,m:*\ \ \ \ ,ex:*/,s:/*\ NOTE,m:*\ \ \ ,ex:*/,:--,s1:/*,mb:*,ex:*/
"  \ formatoptions+=croql
"  \ smartindent
" This one prefixes * to secondary lines in a /* */ comment:
autocmd BufRead *.sql set
  \ comments=sb:--\ FIXME:,m:--\ \ \ \ \ \ \ \ ,ex:--.,sb:--\ NOTE:,m:--\ \ \ \ \ \ \ ,ex:--.,sb:--\ FIXME,m:--\ \ \ \ \ \ \ ,ex:--.,sb:--\ NOTE,m:--\ \ \ \ \ \ ,ex:--.,s:/*\ FIXME:,m:*\ \ \ \ \ ,ex:*/,s:/*\ NOTE:,m:*\ \ \ \ ,ex:*/,s:/*\ FIXME,m:*\ \ \ \ ,ex:*/,s:/*\ NOTE,m:*\ \ \ ,ex:*/,s1:/*,mb:*,ex:*/
  \ formatoptions+=croql
  \ smartindent
" The 'x' in 'ex' means you can type the trailing end-comment character on a
" new comment line to close the comment (and vim will fix the indent, too).
" But [lb] likes the cleaner look of seconday comment lines without asterisks.
" So 'ex' doesn't matter/work.
" 2013.03.26: [lb] finally fixed all the quirks with comments (not all of them
" worked right, and middle lines are ugly with asterisks) and also with
" indentkeys (pressing colon ':' would indent line, which was making writing
" FIXME:s annoying).
autocmd BufRead *.sql set
  \ comments=sb:--\ FIXME:,m:--\ \ \ \ \ \ \ \ ,ex:--.,sb:--\ NOTE:,m:--\ \ \ \ \ \ \ ,ex:--.,sb:--\ FIXME,m:--\ \ \ \ \ \ \ ,ex:--.,sb:--\ NOTE,m:--\ \ \ \ \ \ ,ex:--.,sb:/*\ FIXME:,m:\ \ \ \ \ \ ,e:*/,sb:/*\ NOTE:,m:\ \ \ \ \ ,e:*/,sb:/*\ FIXME,m:\ \ \ \ \ ,e:*/,sb:/*\ NOTE,m:\ \ \ \ ,e:*/,s:/*,m:\ ,e:*/,s:--,m:--\ ,e:--
  \ formatoptions+=croql
  \ smartindent
  \ indentexpr=GetSQLIndent()
  \ indentkeys=!^F,o,O,=elif,=except,=~end,=~else,=~elseif,=~elsif,0=~when,0=)
"  \ indentkeys=!^F,o,O,<:>,=elif,=except,=~end,=~else,=~elseif,=~elsif,0=~when,0=)
"
" 2012.09.30: Trying to fix SQL autocommentindent so it doesn't use leader...
" fo-table
" c: Auto-wrap comments w/ textwidth; insert comment leader automatically.
" n: When formatting text, recognize numbered lists.
" 2: When formatting text, use the indent of the second line of a paragraph.
" NO: formatoptions-=c
" NO: formatoptions+=n2
" See: indentexpr=GetSQLIndent()
" :fu GetSQLIndent
" :echo exists("*GetSQLIndent")
" $ repoquery --list vim-common
" /usr/share/vim/vim73/indent/sqlanywhere.vim

" Wikitext
" --------------------------------
" Because who doesn't love Jimmy Wales?
" Even his name is Super Sexy!
"autocmd BufRead *.wp set filetype=wp
autocmd BufRead,BufNewFile *.wiki setfiletype wikipedia
autocmd BufRead,BufNewFile *.wikipedia.org* setfiletype wikipedia
autocmd BufRead,BufNewFile *.wp setfiletype wikipedia

" Fix Syntax Highlight
" --------------------------------
" Otherwise -- especially w/ the Actionscript syntax 
" highlighter -- files look like all-comments.
autocmd BufNewFile,BufRead * syntax sync fromstart

" Plain Text Files
" --------------------------------

autocmd BufEnter,BufRead *.txt set tw=0 tabstop=2 shiftwidth=2
autocmd BufEnter,BufRead *.txt match none 

autocmd BufEnter,BufRead *.log set tw=0 tabstop=2 shiftwidth=2
autocmd BufEnter,BufRead *.log match none 

" ------------------------------------------
" ----------------------------------- EOF --

