# MacOS 14 (M1/M2)

# Homebrew

Visit https://brew.sh to install homebrew

# External libraries and frameworks

	brew install sqlite3
	brew install zeromq

# Lua and Luarocks versions

	brew install lua@5.1
	brew install luarocks

# Luarocks dependencies

	sudo luarocks --lua-dir=/opt/homebrew/opt/lua@5.1 install lua-cmsgpack
	sudo luarocks --lua-dir=/opt/homebrew/opt/lua@5.1 install lua-cjson
	sudo luarocks --lua-dir=/opt/homebrew/opt/lua@5.1 install lsqlite3
	sudo luarocks --lua-dir=/opt/homebrew/opt/lua@5.1 install lua-llthreads2

# LZMQ - problematic dependency

I'm working on a patched version of this rock, though I don't yet understand enough to publish a clean fix.

First download and unzip the code from https://github.com/samuelwbaird/lzmq/archive/refs/heads/master.zip

	# build locally using luarocks make, and setting the lib dir for ZMQ from homebrew
	cd lzmq-master
	sudo luarocks --lua-dir=/opt/homebrew/opt/lua@5.1 make rockspecs/lzmq-0.4.4-1.rockspec ZMQ_LIBDIR=/opt/homebrew/Cellar/zeromq/4.3.5_1/lib


# Run the examples

The slash service allows anonymous logging via basic HTTP requests.

Run the service below to confirm all dependencies are installed. Then visit http://localhost:8080/ to confirm the service is running locally.

	eval "$(luarocks --lua-dir=/opt/homebrew/opt/lua@5.1 path --bin)"
	cd brogue/examples/slash
	lua-5.1 server.lua