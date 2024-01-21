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
- [ ] fork libdecsync to silence/redirect Logging
- [ ] separate collections between each other
- [ ] remove `decscribe.py` completely | optimize libdecsync calls (too slow currently)
    - is it python?
    - is it ical parsing?
    - is it costly all-entries-recalculations?
- [ ] edit and save todos (simple view of raw VDIR of given item)
- [ ] `:Decscribe PATH-TO-COLLECTION`
- [ ] `:Decscribe NAME-OF-PRECONFIGURED-COLLECTION`
- [ ] edit many todos simultaneously, *in the list*
- [ ] complex todo view, like Octo's PR view
- [ ] categories
- [ ] subtasks? is it even in iCal spec?
- [ ] fix `repopulate_buffer` disabling highlighting for some reason
- [ ] ...
- [ ] at this point, todos collection view should be like just an MD file with nested lists
- [ ] ...
- [ ] similar for calendar?
