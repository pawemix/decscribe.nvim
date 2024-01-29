- [x] list out todos
- [x] `:Decscribe`
- [x] clean up the view - too much metadata
- [x] separate tasks between each other
- [x] virtual buffer like in Octo/Oil
    * i.e. without corresponding file & with overriden load/save functions
    * [x] implement save (`:w`)
    * [x] save should modify `modified`
    * [x] implement load (`:e!`)
    * [x] custom name (`vim.api.nvim_set_buf_name`)
- [x] refactor `set_entry` to NOT use `decscribe.py`, but ONLY Lua + FFI
    - [x] attach a todo's vcal form to every todo_json
    - [x] actual refactor
- [x] fork libdecsync to silence/redirect Logging
- [x] remove `decscribe.py` completely | optimize libdecsync calls (too slow currently)
    - is it python?
    - is it ical parsing?
    - is it costly all-entries-recalculations?
    - everything is fast except (some part of decscribe.py) (maybe executing ALL entries too often?)
- [x] what's causing this long lag during first one/several `:w`'s? (buffer changes during BufWriteCmd)
- [ ] handle adding new items
- [ ] separate collections between each other; add `:Decscribe COLLECTION`
- [ ] handle editing many todo items simultaneously
- [ ] handle removing
- [ ] use extmarks for diff-handling
- [ ] subtasks
- [ ] `:Decscribe PATH-TO-DECSYNC-DIR COLLECTION`
- [ ] `:Decscribe NAME-OF-PRECONFIGURED-DECSYNC-DIR COLLECTION`
- [ ] edit and save todos (simple view of raw VDIR of given item)
- [ ] fix `repopulate_buffer` disabling highlighting for some reason
- [ ] don't reestablish libdecsync connection so often (i.e. with every repopulate_buffer) - keep it long living
- [ ] memory leak - free `Decsync*` connections after the buffer is repopulated (a brand new connection is established)
- [ ] with already established libdecsync connection, only refresh *changed* entries, not all
- [ ] complex todo view, like Octo's PR view
- [ ] categories/tags
- [ ] ...
- [ ] at this point, todos collection view should be like just an MD file with nested lists
- [ ] ...
- [ ] similar for calendar?
