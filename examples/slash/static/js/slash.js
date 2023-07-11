// connect to demos of the slash log service
// copyright 2022 Samuel Baird MIT Licence

function Query (method, url, data, successHandler, errorHandler, timeout) {
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
		return Query('post', url, data, successHandler, errorHandler, 30000);
	},
	get: function (url, successHandler, errorHandler) {
		return Query('get', url + '?nocache=' + Date.now(), null, successHandler, errorHandler, 30000);
	},
};

function cloneTemplate (elementID, subs) {
	const element = document.getElementById(elementID);
	const clone = (element.tagName == 'TEMPLATE') ? element.content.firstElementChild.cloneNode(true) : element.cloneNode(true);
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

function updateAppList (elementID) {
	// this one loads immediately and then on a basic polling timer
	const parent = document.getElementById(elementID);
	const update = () => {
		query.get('api/apps', (jsonData) => {
			// create table output
			if (Array.isArray(jsonData)) {
				parent.innerHTML = '';
				for (const app of jsonData) {
					const date = new Date(app.time * 1000);
					const line = cloneTemplate('template_app', [
						['.app_id', 'innerText', app.app_id],
						['.date', 'innerText', date],
						['a', 'href', 'app.html?app_id=' + app.app_id],
					]);
					parent.appendChild(line);
				}
			}
		}, (failure) => {});
	};
	update();
	setInterval(update, 3000);
}

function updateDeviceList (elementID, app_id) {
	// this one loads immediately and then on a basic polling timer
	const parent = document.getElementById(elementID);
	const update = () => {
		query.get('api/devices/' + app_id, (jsonData) => {
			// create table output
			if (Array.isArray(jsonData)) {
				parent.innerHTML = '';
				for (const device of jsonData) {
					const date = new Date(device.time * 1000);
					const line = cloneTemplate('template_app', [
						['.app_id', 'innerText', device.device_id],
						['.date', 'innerText', date],
						['a', 'href', 'logs.html?app_id=' + app_id + '&device_id=' + device.device_id],
					]);
					parent.appendChild(line);
				}
			}
		}, (failure) => {});
	};
	update();
	setInterval(update, 3000);
}

function monitorLogs (elementID, app_id, device_id) {
	const parent = document.getElementById(elementID);
	parent.innerHTML = '';

	let lastSeen = 0;
	const update = () => {
		query.get('api/logs/' + app_id + '/' + device_id + '/' + lastSeen, (jsonData) => {
			if (Array.isArray(jsonData)) {
				for (const log of jsonData) {
					const logText = (typeof log.log_value == 'string') ? log.log_value : JSON.stringify(log.log_value);

					const line = cloneTemplate('template_log', [
						['.log', 'innerText', new Date(log.time * 1000) + ' ' + logText],
					]);
					parent.appendChild(line);
					if (log.no > lastSeen) {
						lastSeen = log.no;
					}
				}
			}
			// resize and scroll
			const bounds = parent.getBoundingClientRect();
			parent.style.height = (window.innerHeight - bounds.top - 10) + 'px';
			// scroll to bottom automatically
			parent.scrollTop = parent.scrollHeight;
			setTimeout(update, 100);
		}, (failure) => {
			setTimeout(update, 1000);
		});
	};
	update();

}

export { updateAppList, updateDeviceList, monitorLogs };
