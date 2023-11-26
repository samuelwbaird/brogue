# MacOS 12 and below

# Homebrew

Visit https://brew.sh to install homebrew

# External libraries and frameworks

	brew install sqlite3
	brew install zeromq

# Lua and Luarocks versions

	brew install lua@5.1
	brew install luarocks

# Luarocks dependencies

	sudo luarocks --lua-dir=/opt/homebrew/opt/lua@5.1 install lua-llthreads
	sudo luarocks --lua-dir=/opt/homebrew/opt/lua@5.1 install lzmq
	sudo luarocks --lua-dir=/opt/homebrew/opt/lua@5.1 install lua-cjson
	sudo luarocks --lua-dir=/opt/homebrew/opt/lua@5.1 install lua-cmsgpack
	sudo luarocks --lua-dir=/opt/homebrew/opt/lua@5.1 install lsqlite3

# Run the examples

The slash service allows anonymous logging via basic HTTP requests.

Run the service below to confirm all dependencies are installed. Then visit http://localhost:8080/ to confirm the service is running locally.

	cd brogue/examples/slash
	lua-5.1 server.lua