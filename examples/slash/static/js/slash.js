// connect to demos of the slash log service
// copyright 2022 Samuel Baird MIT Licence

function _query (method, url, data, successHandler, errorHandler, timeout) {
	const xhr = new XMLHttpRequest();

	xhr.open(method, url, true);
	xhr.onreadystatechange = function () {
		let status;
		let data;
		if (xhr.readyState == 4) { // `DONE`
			status = xhr.status;
			if (status == 200) {
				if (xhr.responseText != '') {
					data = JSON.parse(xhr.responseText);
				}
				successHandler && successHandler(data);
			} else {
				errorHandler && errorHandler(status);
			}
			successHandler = null;
			errorHandler = null;
		}
	};
	if (timeout != undefined) {
		xhr.timeout = timeout;
	}

	if (data != null) {
		xhr.setRequestHeader('Content-Type', 'application/json;charset=UTF-8');
		xhr.send(JSON.stringify(data));
	} else {
		xhr.send();
	}

	return xhr;
}

// public api
const query = {
	post: function (url, data, successHandler, errorHandler) {
		return _query('post', url, data, successHandler, errorHandler);
	},
	get: function (url, successHandler, errorHandler) {
		return _query('get', url, null, successHandler, errorHandler);
	},
};

function clone_template (element_id, subs) {
	const clone = document.getElementById(element_id).cloneNode(true);
	clone.id = null;
	if (Array.isArray(subs)) {
		for (const sub of subs) {
			if (Array.isArray(sub) && sub.length == 3) {
				clone.querySelector(sub[0])[sub[1]] = sub[2];
			}
		}
	}
	return clone;
}

function update_app_list (element_id) {
	// this one loads immediately and then on a basic polling timer
	const parent = document.getElementById(element_id);
	const update = () => {
		query.get('api/apps', (json_data) => {
			// create table output
			if (Array.isArray(json_data)) {
				parent.innerHTML = '';
				for (const app of json_data) {
					const date = new Date(app.time * 1000);
					const line = clone_template('template_app', [
						[ '.app_id', 'innerText', app.app_id ],
						[ '.date', 'innerText', date ],
						[ 'a', 'href', 'app.html?app_id=' + app.app_id ],
					]);
					parent.appendChild(line);
				}
			}
		}, (failure) => {})		
	}
	update();
	setInterval(update, 3000);
}

function update_device_list (element_id) {
	// this one loads immediately and then on a basic polling timer
}

function monitor_logs (element_id) {
	
}

export { update_app_list, update_device_list, monitor_logs };