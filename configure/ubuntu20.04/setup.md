# Ubuntu 20.04

# External libraries and frameworks

	sudo apt-get install libzmq3-dev sqlite3 libsqlite3-dev

# Lua and Luarocks versions

	sudo apt-get install lua5.1 luarocks

# Luarocks dependencies

	sudo luarocks install lua-cjson
	# patched version for github issue
	sudo luarocks install https://raw.githubusercontent.com/FHRNet/lua-cmsgpack/master/rockspec/lua-cmsgpack-scm-1.rockspec
	sudo luarocks install lsqlite3
	sudo luarocks install lua-llthreads2
	sudo luarocks install lzmq

# Run the examples

The slash service allows anonymous logging via basic HTTP requests.

Run the service below to confirm all dependencies are installed. Then visit http://localhost:8080/ to confirm the service is running locally.

	cd brogue/examples/slash
	lua server.lua