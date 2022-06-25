#! /bin/bash

# run the debug server in a loop, using fswatch to monitor relevant files and relaunch
# the server if they are updated

# get a reference to the correct folder
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

while [ 1 ]
do
	#! /bin/bash
	echo ""
	echo `date` "- restarting"

	# kill existing servers, bluntly all luajit instances
	killall lua >/dev/null 2>/dev/null
	
	# ensure we're running from the correct folder
	cd $DIR

	# launch luajit in the background
	lua server.lua &

	# monitor for a change then repeat this process
	fswatch -r1 -l 10 classes static server.lua
done
