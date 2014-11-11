require.config({
    baseUrl: '/resources/',
    paths: {
        'underscore': 'lib/underscore',
    },
    shim: {
        'underscore': {
            exports: '_'
        },
    }
});

// Load the main app module to start the app
requirejs(["app/game"], function (game) {
	game.main();
});