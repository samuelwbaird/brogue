-- bootstraps the primary services, logging and registry
-- with an explicit semaphore to ensure these required services are ready
-- after this point registry:wait should be sufficient
-- copyright 2014 Samuel Baird MIT Licence

require('rascal.base')

local table = require('table')

-- external modules
local cmsgpack = require('cmsgpack')

-- core modules
local array = require('core.array')
local module = require('core.module')

-- manage synchronisation when starting core services
local thread_semaphore = require('rascal.bootstrap.thread_semaphore')
local thread_startup_semaphore = thread_semaphore('inproc://rascal.thread.startup')

-- core services ------------------------------------------------------

-- logging
detach({
	[[local log_server = require('rascal.log') ()]],
	[[log_server:bind('inproc://log')]],
	[[require('rascal.bootstrap.thread_semaphore').signal('inproc://rascal.thread.startup', 'log')]],
	[[loop:start()]],
})
thread_startup_semaphore:wait('log')

-- registry
detach({
	[[local registry = require('rascal.registry') ()]],
 	[[registry:bind()]],
	[[require('rascal.bootstrap.thread_semaphore').signal('inproc://rascal.thread.startup', 'registry')]],
	[[loop:start()]],
})
thread_startup_semaphore:wait('registry')

-- publish the log service

local registry = require('rascal.registry')
local log = require('rascal.log')
registry.client():publish('log', 'inproc://log', zmq.PUSH, log.api_description)