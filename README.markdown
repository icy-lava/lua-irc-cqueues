lua-irc-cqueues
============

This is a fork of [LuaIRC](https://github.com/JakobOvrum/LuaIRC) that uses `cqueues.socket` instead of `luasocket`.
It also uses `luaossl` instead of `LuaSec`.

This will give you the benefits of using cqueues - asynchronous code using coroutines.

Dependencies
-------------

 * [cqueues](https://luarocks.org/modules/daurnimator/cqueues)
 * [luaossl](https://luarocks.org/modules/daurnimator/luaossl)

Documentation
-------------
Documentation can be found on the original repository's [github pages](https://jakobovrum.github.io/LuaIRC/doc/modules/irc.html).

Additionally, `irc:connect` will use a secure connection, unless you pass in a table that has `secure` set to `false`.

Since this uses `cqueues.socket`, you should have seamless integration with cqueues.
