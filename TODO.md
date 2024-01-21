1. [x] list out todos
2. [x] `:Decscribe`
3. [x] clean up the view - too much metadata
4. [x] separate tasks between each other
5. [x] virtual buffer like in Octo/Oil
    * i.e. without corresponding file & with overriden load/save functions
    * [x] implement save (`:w`)
    * [x] save should modify `modified`
    * [x] implement load (`:e!`)
    * [x] custom name (`vim.api.nvim_set_buf_name`)
6. [x] refactor `set_entry` to NOT use `decscribe.py`, but ONLY Lua + FFI
    - [x] attach a todo's vcal form to every todo_json
    - [x] actual refactor
7. [ ] fork libdecsync to silence/redirect Logging
8. [ ] separate collections between each other
9. [ ] remove `decscribe.py` completely | optimize libdecsync calls (too slow currently)
    - is it python?
    - is it ical parsing?
    - is it costly all-entries-recalculations?
10. [ ] edit and save todos (simple view of raw VDIR of given item)
11. [ ] `:Decscribe PATH-TO-COLLECTION`
12. [ ] `:Decscribe NAME-OF-PRECONFIGURED-COLLECTION`
13. [ ] edit many todos simultaneously, *in the list*
14. [ ] complex todo view, like Octo's PR view
15. [ ] categories
16. [ ] subtasks? is it even in iCal spec?
17. [ ] fix `repopulate_buffer` disabling highlighting for some reason
18. [ ] ...
19. [ ] at this point, todos collection view should be like just an MD file with nested lists
20. [ ] ...
21. [ ] similar for calendar?
