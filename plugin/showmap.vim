
" showmap.vim - help for multiple-key mapping sequences
if exists("g:loaded_showmap") || &cp
  finish
endif
let g:loaded_showmap = 1


"----------------
" Highlight {{{1
"----------------

hi default link ShowmapPrefix    MoreMsg
hi default link ShowmapList      Normal
hi default link ShowmapLHSPrefix SpecialKey
hi default link ShowmapLHSComp   MoreMsg
hi default link ShowmapRHS       String


"-----------
" Init {{{1
"-----------

augroup ShowmapGroup
  au!
  autocmd VimEnter *
    \  if !exists('g:showmap_no_autobind')
    \|   call showmap#autobind(get(g:, 'showmap_autobind_modes', 'n'))
    \| endif
augroup END


" vim: et sw=2:
