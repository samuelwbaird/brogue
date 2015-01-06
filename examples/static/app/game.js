define(['underscore'], function(_) {
	var api_base = 'api_';
	
	// basic ajax JSON request
	var api = function(url, data, successHandler, errorHandler) {
	  var xhr = typeof XMLHttpRequest != 'undefined'
	    ? new XMLHttpRequest()
	    : new ActiveXObject('Microsoft.XMLHTTP');
	  xhr.open('post', api_base + url, true);
	  xhr.setRequestHeader("Content-Type", "application/json;charset=UTF-8");

	  xhr.onreadystatechange = function() {
	    var status;
	    var data;
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
	
	var t_turns = _.template('');
	
	
	var lastSeenId = 0
	var poll = function () {
		api('poll',
			{
				move : lastSeenId
			},
			function (data) {
				var content = ['<pre>'];
				
				// check if there are possible moves
				var moves = {}
				if (data.turns && data.turns[0].type == 'runner' && data.moves) {
					_.each(data.moves, function (move) {
						moves[move.name] = move;
					})
				}
				
				// render the grid
				if (data.grid) {
					content.push('<br><table>');
					_.each(data.grid, function (row) {
						content.push('<tr>');
						_.each(row, function (cell) {
							content.push('<td>')
							if (moves[cell.name]) {
								content.push('<a onclick="do_move(' + data.turn_no + ', \'' + cell.name + '\');" href="javascript:void(0);">')
							}
							
							if (cell.speed) {
								content.push('#')
							} else {
								content.push('.')
							}
							if (cell.runner) {
								content.push(cell.runner);
							} else if (cell.blocker) {
								content.push(cell.blocker);
							} else {
								content.push('..')
							}
							if (moves[cell.name]) {
								content.push('</a>')
							}
							content.push('</td>')
						})
						content.push('</tr>');
					})
					content.push('</table>')
				}				
				
				if (data.messages) {
					content.push('<br>');
					_.each(data.messages, function (message) {
						content.push(message);
						content.push('<br>');
					});
				}
				
				if (data.turns) {
					content.push('<br>');
					content.push(data.turns[0].name + ' then ')
					_.each(_.rest(data.turns), function (turn) {
						content.push(turn.name + ' ');
					});
				}
				
				content.push('</pre>')
				document.getElementById("content").innerHTML = content.join('');
				lastSeenId = data.turn_no;
				
				poll();
				// setTimeout(poll);
			},
			function (status) {
				// poll();
			});
	}
	
	return {
		main : function () {
			
			window.do_move = function (turn_no, position) {
				api('move', {
					turn_no : turn_no,
					position : position
				}, function (data) {
					document.getElementById("notice").innerHTML = "<pre>" + data + "</pre>";
				}, function (status) {
					
				});
			}
			
			poll()
		}
	}
});
