# Brogue

_Lua libraries to create micro-servers based on 0MQ and SQLite._

Brogue consists of primary modules (_rascal_) along with supporting libraries (_core_ and _dweeb_) to create Lua based micro servers. The intention is to provide a structure to easily prototype server based game logic, with mobile, social and casual games in mind.

Each micro server runs in its own thread or process, driven by the 0MQ (ZeroMQ) event loop. This architecture has the potential to combine the benefits of multi-threading and single threaded event loops or perhaps all the drawbacks.

Aside from communication and a timer, each thread is not pervasively asynchronous and event based like Node.JS. Most user code will run in synchronous blocks, relying on the separate 0MQ networking thread and buffering strategies, such as push/pull and pub/sub channels to keep things flowing.

Game logic and rules can execute in an in-process, single threaded fashion, with IO to the network published via side channels. SQLite works well as an appropriate data store to use within each micro server. The _dweeb_ module wraps access to SQLite, as well as providing a very loose ORM layer in keeping with Lua's dynamic objects.

_Rascal_ uses a registry to publish APIs across micro server boundaries and resolve dependencies. A 0MQ raw socket HTTP server provides an access point to the outside world, along with worker threads, support for long polling and JSON.


## Dependencies

* Lua 5.1 or LuaJIT 2
* SQLite 3
* 0MQ 4
* llthreads2
* lzmq (Moteus)
* lua-cjson
* lua-csmgpack
* lsqlite3

## Configuration

See configuration folders for known platforms.