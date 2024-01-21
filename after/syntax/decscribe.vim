" quit if the syntax file has already been loaded:
if exists("b:current_syntax")
  finish
endif

if !exists('main_syntax')
  let main_syntax = 'decscribe'
endif

runtime! syntax/markdown.vim ftplugin/markdown.vim ftplugin/markdown_*.vim ftplugin/markdown/*.vim
unlet! b:current_syntax

let b:current_syntax = "decscribe"
if main_syntax ==# 'decscribe'
  unlet main_syntax
endif
