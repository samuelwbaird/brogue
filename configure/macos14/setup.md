# MacOS 14 (M1/M2)

Under MacOS 14 two additional work arounds are required for install:

 * The sqlite3 library supplied with the OS has missing functionality, and the homebrew version must be link and referenced explicitly
 * The lzmq luarock has an issue compiling with the latest dev tools, I've created a temporarily patched version that can be built instead

These instructions also reflect using Luarocks with a local path.

# Homebrew

Visit https://brew.sh to install homebrew

# External libraries and frameworks

	brew install zeromq
	brew install sqlite3
	# we need to link this to make it available instead of the system version
	brew link sqlite3 --force

# Lua and Luarocks versions

	brew install lua@5.1
	brew install luarocks

# Luarocks dependencies

	luarocks --lua-dir=/opt/homebrew/opt/lua@5.1 install lua-cmsgpack
	luarocks --lua-dir=/opt/homebrew/opt/lua@5.1 install lua-cjson
	luarocks --lua-dir=/opt/homebrew/opt/lua@5.1 install lsqlite3
	luarocks --lua-dir=/opt/homebrew/opt/lua@5.1 install lua-llthreads2

# LZMQ - problematic dependency

I'm working on a patched version of this rock, though I don't yet understand enough to publish a clean fix.

First download and unzip the code from https://github.com/samuelwbaird/lzmq/archive/refs/heads/master.zip

	# build locally using luarocks make, and setting the lib dir for ZMQ from homebrew
	cd lzmq-master
	luarocks --lua-dir=/opt/homebrew/opt/lua@5.1 make rockspecs/lzmq-0.4.4-1.rockspec ZMQ_LIBDIR=/opt/homebrew/Cellar/zeromq/4.3.5_1/lib


# Run the examples

The slash service allows anonymous logging via basic HTTP requests.

Run the service below to confirm all dependencies are installed. Then visit http://localhost:8080/ to confirm the service is running locally.

	# set lua paths automatically using luarocks
	eval "$(luarocks --lua-dir=/opt/homebrew/opt/lua@5.1 path --bin)"
	# force the use of homebrew sqlite as Mac version has restrictions
	export DYLD_LIBRARY_PATH=/opt/homebrew/opt/sqlite/lib:/usr/lib
	
	cd brogue/examples/slash
	lua-5.1 server.lua