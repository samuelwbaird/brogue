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
		return _query('post', url, data, successHandler, errorHandler, 30000);
	},
	get: function (url, successHandler, errorHandler) {
		return _query('get', url + '?nocache=' + Date.now(), null, successHandler, errorHandler, 30000);
	},
};

function clone_template (element_id, subs) {
	const element = document.getElementById(element_id);
	const clone = (element.tagName == "TEMPLATE") ? element.content.firstElementChild.cloneNode(true) : element.cloneNode(true);
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

function update_device_list (element_id, app_id) {
	// this one loads immediately and then on a basic polling timer
	const parent = document.getElementById(element_id);
	const update = () => {
		query.get('api/devices/' + app_id, (json_data) => {
			// create table output
			if (Array.isArray(json_data)) {
				parent.innerHTML = '';
				for (const device of json_data) {
					const date = new Date(device.time * 1000);
					const line = clone_template('template_app', [
						[ '.app_id', 'innerText', device.device_id ],
						[ '.date', 'innerText', date ],
						[ 'a', 'href', 'logs.html?app_id=' + app_id + '&device_id=' + device.device_id],
					]);
					parent.appendChild(line);
				}
			}
		}, (failure) => {})		
	}
	update();
	setInterval(update, 3000);
}

function monitor_logs (element_id, app_id, device_id) {
	const parent = document.getElementById(element_id);
	parent.innerHTML = '';

	let last_seen = 0;
	const update = () => {
		query.get('api/logs/' + app_id + '/' + device_id + '/' + last_seen, (json_data) => {
			if (Array.isArray(json_data)) {
				for (const log of json_data) {
					const log_text = (typeof log.log_value == 'string') ? log.log_value : JSON.stringify(log.log_value)
					
					const line = clone_template('template_log', [
						[ '.log', 'innerText', new Date(log.time * 1000) + ' ' + log_text],
					]);
					parent.appendChild(line);
					if (log.no > last_seen) {
						last_seen = log.no;
					}
				}
			}
			// resize and scroll
			const bounds = parent.getBoundingClientRect();			
			parent.style.height = (window.innerHeight - bounds.top - 10) + 'px';
			// scroll to bottom automatically
			parent.scrollTop = parent.scrollHeight;
			setTimeout(update, 100)
		}, (failure) => {
			setTimeout(update, 1000)
		})		
	}
	update();
	
}

export { update_app_list, update_device_list, monitor_logs };