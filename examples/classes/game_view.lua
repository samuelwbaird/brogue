package.path = '../source/?.lua;' .. package.path

-- a custom handler that's going to serve the game view as dynamic html

local class = require('core.class')
local array = require('core.array')
local rascal = require('rascal.core')

return class(function (game_view)
	
	function game_view:handle(request, context, response)
		-- our custom handler respond with some dynamic content
		response:set_mimetype_from_extension('html')

-- this should probably be some kind of static + dynamic or template thing
		
		local out = array()
		out:push('<html><head><title>Runners vs Blockers</title></head><body>')
		out:push('<h1>You are player ' .. context.session_data.name .. '</h1>')
		-- a central section to display and long-poll the game state
		out:push([[
<div id="content" />
<script type=text/javascript>
// basic ajax JSON request
var getJSON = function(url, data, successHandler, errorHandler) {
  var xhr = typeof XMLHttpRequest != 'undefined'
    ? new XMLHttpRequest()
    : new ActiveXObject('Microsoft.XMLHTTP');
  xhr.open('post', url, true);
  xhr.setRequestHeader("Content-Type", "application/json;charset=UTF-8");

  xhr.onreadystatechange = function() {
    var status;
    var data;
    // http://xhr.spec.whatwg.org/#dom-xmlhttprequest-readystate
    if (xhr.readyState == 4) { // `DONE`
      status = xhr.status;
      if (status == 200) {
        data = JSON.parse(xhr.responseText);
        successHandler && successHandler(data);
      } else {
        errorHandler && errorHandler(status);
      }
    }
  };
  xhr.send(JSON.stringify(data));
};

// set up the polling
var lastSeenId = 0
var poll = function () {
	getJSON('api_poll',
		{
			move : lastSeenId
		},
		function (data) {
			document.getElementById("content").innerHTML = data.content;
			lastSeenId = data.move;
			poll();
		},
		function (status) {
			// poll();
		});
}
window.onload = function () {
	poll()
}
</script>
</div>
]])
		
		
		
		out:push('</body></html>')
		
		response:set_body(out:concat())
			
		-- invoke the rest of the chain
		return true
	end
end)