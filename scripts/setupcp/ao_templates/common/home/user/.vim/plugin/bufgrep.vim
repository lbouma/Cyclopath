" Author: Michael Geddes ( vimmer at frog.wheelycreek.net )
"
" Created for zorph on IRC
" Version: 0.3
" Date: 4 Aug  2009
"
" Bgrep /{searchexpr}/     -  Vimgrep all buffers.
"   or
" Bgrep {searchword}       -  Vimgrep all buffers for {searchword}
"
" 0.3: Fix up error when there is no //
"      Fix up handling of windows in some edge cases.
fun! s:BufGrep(param)
  let curwin=winnr()
  let curbuf=winbufnr(curwin)
  let curbuftype=&buftype
  if strlen(a:param) == 0
    echoerr "Search parameter required"
    return 1
  endif
  call setqflist([])
  if a:param[0] != a:param[strlen(a:param)-1] || a:param[0] =~# '[a-zA-Z0-9\\"|]'
    let useparam='/'.escape(a:param,'/').'/'
  else
    let useparam=a:param
  endif

  silent bufdo exe "g ".useparam." if &buftype==''| call setqflist([{'type': 'l', 'col':1, 'bufnr': winbufnr('.'), 'lnum': line('.'), 'text':getline('.')}],'a')|endif"

  if curbuftype=='quickfix'
    let lastwin=winnr()
    cw
    if winnr() != lastwin
      let curwin=winnr()
      exe lastwin.'winc w'
      q
      exe curwin.'winc w'

    endif
  else
    if curwin==winnr() && bufexists(curbuf)
      exe curbuf.'buf'
    endif
    cw
  endif
  if len(getqflist())>0
    1cc
  endif

endfun
" toot for testing

com! -nargs=1  Bgrep  :call s:BufGrep(<q-args>)

"vim: ts=2 sw=2 et
