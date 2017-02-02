" showmap.vim - help for multiple-key mapping sequences
" Author:       fcpg
" Version:      1.0


"-----------------------
" Public functions {{{1
"-----------------------

" showmap#helper {{{2
" Code to run on timeout
" 1st arg is a sequence of printable key names
" 2nd optional arg is a letter = mode (n,v,o,x,i,c)
function! showmap#helper(seq, mode)
  if exists('g:showmap_debug')
    echom printf("helper(): [%s] [%s]", a:seq, a:mode)
  endif
  if a:mode != 'n'
    let save_smd = &smd
    let &smd = 0
  endif
  let not_mapped = 0
  let wait       = 1
  let whatis_all = get(g:, 'showmap_auto_whatis_all', 0)
  while wait
    redraw
    if whatis_all
      " auto list all - just once
      let whatis_all = 0
      let do_quit = s:whatis_all(a:seq, a:mode)
      if do_quit | break | else | continue | endif
    else
      call s:prompt(a:seq, a:mode)
      let [rc, c, raw] = s:getcharstr()
      if rc == s:key_quit
        " quit
        echo '' | redraw
        break
      elseif rc == s:key_help
        " help
        let do_quit = s:whatis(a:seq, a:mode)
        if do_quit | break | else | continue | endif
      elseif rc == s:key_help_all
        " list all
        let do_quit = s:whatis_all(a:seq, a:mode)
        if do_quit | break | else | continue | endif
      elseif rc == s:key_multi
        call s:resume_map(a:seq)
        break
      endif
      if c != '' && maparg(a:seq . c, a:mode) != ''
        " map found, exec it
        let rawseq  = s:str2raw(a:seq)
        let feedstr = rawseq . (raw ? rc : c)
        call feedkeys(feedstr, 't')
        echo '' | redraw
      else
        " no map found
        let not_mapped = 1
      endif
    endif
    let wait = 0
  endwhile
  if a:mode != 'n'
    let &smd = save_smd
  endif
  if exists('t:showmap_cmdheight')
    let &cmdheight = t:showmap_cmdheight
    unlet t:showmap_cmdheight
  endif
  if not_mapped
    echo "Not mapped." | redraw
  endif
  if a:mode == 'i'
    return ''
  endif
endfun


" showmap#bind_helper {{{2
" Create mapping on given key sequence
" 1st arg is a sequence of printable key names
" 2nd optional arg is a string with letters = mode (default to 'n')
function! showmap#bind_helper(seq, ...)
  let modes = (a:0 ? a:1 : 'n')
  for mode in split(modes, '\zs')
    if index(s:accepted_modes, mode) == -1
      echoerr "Error: invalid map mode <".mode.">"
      continue
    endif
    let esc_seq = escape(substitute(a:seq, '<', '<lt>', 'g'), '"')
    let exestr  = mode."map <expr> ".a:seq." showmap#helper(".
        \   '"'.esc_seq.'",'.
        \   '"'.mode.'"'.
        \ ")"
    if exists('g:showmap_debug')|echom "bind_helper(): exestr: ".exestr|endif
    exe exestr
  endfor
endfun


" showmap#autobind {{{2
" Automatically create mapping on existing mappings
function! showmap#autobind(modes)
  if exists('g:showmap_debug')
    echom printf("autobind(): [%s]", a:modes)
  endif
  call s:log2file(printf("autobind(): [%s]", a:modes))
  for mode in split(a:modes, '\zs')
    if index(s:accepted_modes, mode) == -1
      echoerr "Error: invalid map mode <".mode.">"
      continue
    endif
    redir => rawlist
    silent exec mode.'map'
    redir END
    let rawlines = split(rawlist, "\n")
    let binds    = {}
    for line in rawlines
      " discard mode indicators
      let without_modes = strpart(line, 3)
      if strpart(without_modes,0,6) ==? '<plug>' 
            \ || strpart(without_modes,0,5) ==? '<snr>'
        " ignore mappings not meant to be typed
        continue
      endif
      let spc_pos = stridx(without_modes, ' ')
      let lhs     = (spc_pos != -1)
            \ ? strpart(without_modes, 0, spc_pos)
            \ : without_modes
      let lhs_tokenize = lhs
      let lhs_tokens   = []
      while lhs_tokenize != ''
        if lhs_tokenize[0] == '<'
          " check special char name
          let str_pos = matchstrpos(lhs_tokenize, '^'.s:char_pattern)
          if str_pos[1] != -1
            " found a special char name
            call add(lhs_tokens, str_pos[0])
            let lhs_tokenize = strpart(lhs_tokenize, str_pos[2])
          else
            " no special char name, the '<' was just the '<' char
            call add(lhs_tokens, strcharpart(lhs_tokenize, 0, 1))
            let lhs_tokenize = strcharpart(lhs_tokenize, 1)
          endif
        else
          " add the single char to tokens and keep tokenizing
          call add(lhs_tokens, strcharpart(lhs_tokenize, 0, 1))
          let lhs_tokenize = strcharpart(lhs_tokenize, 1)
        endif
      endwhile
      let lhs_len = len(lhs_tokens)
      call s:log2file(printf("  count: [%d] %20s %s\n",
            \ lhs_len,lhs,string(lhs_tokens)))
      if lhs_len >= s:autobind_minlen
        let lhs_prefix = join(lhs_tokens[0:s:autobind_minlen-2], '')
        if !has_key(binds, lhs_prefix)
          " don't overwrite map if one exists
          if maparg(lhs_prefix, mode) == ''
            if !exists('g:showmap_autobind_exceptions["'.mode.'"]["'.lhs_prefix.'"]')
              if (!exists('s:autobind_default_exceptions["'.mode.'"]["'.lhs_prefix.'"]')
                  \ || exists('g:showmap_no_autobind_default_exceptions'))
                " the binding is created here
                call showmap#bind_helper(lhs_prefix, mode)
                call s:log2file("showmap#bind_helper(".lhs_prefix.','.mode.')')
              else
                call s:log2file('  autobind_default_exceptions["'.mode.'"]["'.lhs_prefix.'"]')
              endif
            else
              call s:log2file('  autobind_exceptions["'.mode.'"]["'.lhs_prefix.'"]')
            endif
          endif
          let binds[lhs_prefix] = 1
        endif
      endif
    endfor
    call s:log2file("  end of rawlines loop")
  endfor
endfun


"------------------------
" Private functions {{{1
"------------------------

" s:resume_map {{{2
" Wait for a key, quit helper and resume normal typing
function! s:resume_map(seq)
  " put back sequence in the feed and resume
  let rawseq = s:str2raw(a:seq)
  " Wait for next char (to avoid timeouts)
  let [rc, c, raw] = s:getcharstr()
  " clear feed buffer
  call feedkeys('', 'x')
  let feedstr = rawseq . (raw ? rc : c)
  call feedkeys(feedstr, 't')
  echo '' | redraw
endfun


" s:whatis {{{2
" Read a char and show mapping of seq+char
function! s:whatis(seq, mode)
  let [rc, c, raw] = s:getcharstr()
  if rc == s:key_multi
    let c = input("Keys to lookup> ")
  endif
  let map_info = maparg(a:seq.c, a:mode, 0, 1)
  echo '' | redraw
  if empty(map_info)
    echo "Key(s) not mapped."
    exe 'sleep' s:whatis_err_timeout
    return
  endif
  let lhs = map_info['lhs']
  let rhs = map_info['rhs']
  call s:print_map(a:seq, lhs, rhs)
  redraw
  if exists('g:showmap_whatis_timeout')
    exe 'sleep' g:showmap_whatis_timeout
  else
    let [rc, c, raw] = s:getcharstr()
    if rc == s:key_whatis_exec
      if exists('g:showmap_debug')
        echom "  whatis_exec: ".lhs
      endif
      let feedstr = s:str2raw(lhs)
      call feedkeys(feedstr, 't')
      echo '' | redraw
      return 1
    endif
  endif
endfun

" s:whatis_all {{{2
" Show all mappings [lhs+rhs] of seq
" Return 0 = continue, 1 = quit helper (after cleanup)
function! s:whatis_all(seq, mode)
  let list_comp = s:list_completions(a:seq, a:mode)
  for compl in list_comp
    let map_info  = maparg(a:seq.compl, a:mode, 0, 1)
    let lhs       = map_info['lhs']
    let rhs       = map_info['rhs']
    call s:print_map(a:seq, lhs, rhs)
    echon "\n"
  endfor
  if exists('g:showmap_whatis_all_timeout')
    exe 'sleep' g:showmap_whatis_all_timeout
  else
    let [rc, c, raw] = s:getcharstr()
    if rc == s:key_quit
      redraw
      return 1
    elseif rc == s:key_help_all || rc == s:key_help
      return 0
    endif
    if c != '' && maparg(a:seq . c, a:mode) != ''
      " map found, exec it
      let rawseq  = s:str2raw(a:seq)
      let feedstr = rawseq . (raw ? rc : c)
      " echom "exec_all: ".string(feedstr)
      call feedkeys(feedstr, 't')
      redraw
      return 1
    else
      " no map found
      echon "Key(s) not mapped."
      exe 'sleep' s:whatis_err_timeout
      return 0
    endif
  endif
endfun


" s:print_map {{{2
" Pretty-print a mapping
function! s:print_map(seq, lhs, rhs)
  let lhs = a:lhs
  let rhs = a:rhs
  let lhslen  = strchars(lhs)
  let rhslen  = strchars(rhs)
  let caplen  = lhslen + strchars(s:map_caption_sep) + rhslen
  let maxlen  = s:cmd_chars_left(a:seq)
  let difflen = maxlen - caplen
  if difflen < 0
    " truncate rhs
    let rhs = strcharpart(rhs, 0, rhslen + difflen - 6) . ' ...'
  endif
  let lhs_comp = strcharpart(lhs, strchars(a:seq))
  echon  " "
  echohl ShowmapLHSPrefix | echon a:seq    | echohl None
  echohl ShowmapLHSComp   | echon lhs_comp | echohl None
  echon  s:map_caption_sep
  echohl ShowmapRHS       | echon rhs      | echohl None
endfun


" s:getcharstr {{{2
" Get char+name from user input
" Return array [raw_char, char_name, is_raw?]
function! s:getcharstr()
  let raw = 0
  let [rc, c] = s:getrealchar()
  if c == ''
    let c = s:raw2str(rc)
    let raw = 1
  endif
  return [rc, c, raw]
endfun


" s:getrealchar {{{2
" Get a char from user input (CursorHold ignored)
" Return array [raw_char, char_name]
function! s:getrealchar()
  let wait = 1
  while wait
    let rc  = getchar()
    let c   = nr2char(rc)
    let raw = 0
    if c == ''
      if rc == "\<CursorHold>"
        " keep waiting
        continue
      endif
    endif
    let wait = 0
  endwhile
  return [rc, c]
endfun


" s:prompt {{{2
" Show prompt
" 1st arg is a sequence of printable key names
" 2nd optional arg is a letter = mode (n,v,o,x,i,c)
function! s:prompt(seq, mode)
  if exists('g:showmap_debug')
    echom printf("prompt(): [%s] [%s]", a:seq, a:mode)
  endif
  if exists('g:showmap_captions["'.a:mode.'"]["'.a:seq.'"]')
    let caption = g:showmap_captions[a:mode][a:seq]
  else
    let lines   = s:list_completions(a:seq, a:mode)
    let caption = join(lines, s:list_separator)
  endif
  let caplen = strchars(caption) 
  let maxlen = s:cmd_chars_left(a:seq)
  if caplen > maxlen
    if exists('g:showmap_prompt_notruncate')
      let numlines = 1 + caplen / maxlen
      if numlines > &cmdheight
        if !exists('t:showmap_cmdheight')
          let t:showmap_cmdheight = &cmdheight
        endif
        let &cmdheight = numlines
      endif
    else
      let caption = strcharpart(caption, 0, maxlen - 5) . ' ...'
    endif
  endif
  echohl ShowmapPrefix
  echon    ' '.a:seq
  echohl None
  echon    s:prompt_sep
  echohl ShowmapList
  echon    caption
  echohl None
  redraw
endfun


" s:cmd_chars_left {{{2
" Return num of remaining chars available for printing on single line of cmd
function! s:cmd_chars_left(seq)
  let seqlen = strchars(a:seq) 
  let seplen = strchars(s:prompt_sep)
  let maxlen = &columns - seqlen - seplen - 4
  return maxlen
endfun


" s:list_completions {{{2
" Return list of keys completing mappings starting with seq
" 1st arg is a sequence of printable key names
" 2nd arg is a letter = mode (n,v,o,x,i,c)
function! s:list_completions(seq, mode)
  if exists('g:showmap_debug')
    echom printf("list_comp(): [%s] [%s]", a:seq, a:mode)
  endif
  redir => rawlist
  silent exec a:mode.'map '.a:seq
  redir END
  let rawlines = split(rawlist, "\n")
  if exists('g:showmap_debug')|echom "  rawlines: ".string(rawlines)|endif
  let lines = []
  for line in rawlines
    if exists('g:showmap_debug')|echom "  stridx('".line."', '".a:seq.")"|endif
    let pos = stridx(line, a:seq)
    if pos != -1 
      " remaining = lhs without starting a:seq
      let remaining_lhs_to_eol = strpart(line, pos+strlen(a:seq))
      let spc_pos              = stridx(remaining_lhs_to_eol, ' ')
      let remaining_lhs        = (spc_pos != -1)
            \ ? strpart(remaining_lhs_to_eol, 0, spc_pos)
            \ : remaining_lhs_to_eol
      call add(lines, remaining_lhs)
    endif
  endfor
  if s:sort_list_completion
    call sort(lines)
  endif
  return lines
endfun


" s:raw2str {{{2
" Convert raw key to its printable name (eg. ' ' => '<space>')
" 1st arg is the raw key, from getchar() or similar
function! s:raw2str(c)
  if type(a:c) == type(0)
    return nr2char(a:c)
  else
    " input() will eat the content of feedkeys() and stuff will get eval'd
    call feedkeys("\<C-k>".a:c."\<cr>")
    let keyname = input('')
    if exists('g:showmap_debug')|echom "keyname: ".keyname|endif
    return keyname
  endif
endfun


" s:str2raw {{{2
" Convert sequence of key names to raw chars
function! s:str2raw(seq)
  let evalstr = printf('"%s"', escape(substitute(a:seq, '<', '\\<', 'g'), '"'))
  if exists('g:showmap_debug')|echom "  evalstr: ".evalstr|endif
  let rawseq = eval(evalstr)
  if exists('g:showmap_debug')|echom "  rawseq: ".rawseq|endif
  return rawseq
endfun


" s:log2file {{{2
" Debug to logfile
function! s:log2file(msg)
  if !exists('g:showmap_debug_autobind') | return | endif
  call writefile(
        \ ['['.strftime("%T").'] '.a:msg],
        \ s:debug_logfile,
        \ "a")
endfun


"------------------------
" Variables/Options {{{1
"------------------------

let s:char_pattern         = '<\%([CSMAD]-\)*\%([a-zA-Z]\+\d*\|[^>]\)>'
let s:accepted_modes       = ['n', 'v', 'x', 's', 'o', 'i', 'c']
let s:debug_logfile        = get(g:, 'showmap_debug_logfile',
                              \ '/tmp/showmap.log')
let s:prompt_sep           = get(g:, 'showmap_prompt_separator', ' | ')
let s:list_separator       = get(g:, 'showmap_list_separator', ' ')
let s:map_caption_sep      = get(g:, 'showmap_whatis_separator', ' => ')
let s:whatis_err_timeout   = get(g:, 'showmap_whatis_err_timeout', 1)
let s:autobind_minlen      = get(g:, 'showmap_autobind_minlen', 3)
let s:sort_list_completion = get(g:, 'showmap_sort_list_completion', 1)
let s:key_quit             = char2nr(s:str2raw(
                              \ get(g:, 'showmap_quit_key',  "<Esc>")))
let s:key_help             = char2nr(s:str2raw(
                              \ get(g:, 'showmap_help_key',  "<C-h>")))
let s:key_multi            = char2nr(s:str2raw(
                              \ get(g:, 'showmap_multi_key', "<C-x>")))
let s:key_help_all         = char2nr(s:str2raw(
                              \ get(g:, 'showmap_helpall_key', "<C-a>")))
let s:key_whatis_exec      = char2nr(s:str2raw(
                              \ get(g:, 'showmap_whatis_exec', "<Return>")))

" No autobind on mappings that fall back on key-waiting commands
let s:autobind_default_exceptions = {'n': {}}
for k in ['c', 'y', 'd']
  for o in ['f', 'F', 't', 'T']
    let s:autobind_default_exceptions['n'][k.o] = 1
  endfor
endfor


" vim: et sw=2:
