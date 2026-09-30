{{flutter_js}}
{{flutter_build_config}}

// Fast boot: no service worker, CanvasKit from Google CDN, cache-busted entrypoint.
(function () {
  var buildId = "BUILD_ID_PLACEHOLDER";
  var cfg = _flutter.buildConfig || {};
  if (cfg.builds && cfg.builds.length) {
    cfg.builds.forEach(function (b) {
      if (b.mainJsPath && b.mainJsPath.indexOf("?") === -1) {
        b.mainJsPath = b.mainJsPath + "?v=" + buildId;
      }
    });
  }

  _flutter.loader.load({
    config: {
      // Prefer Chromium CanvasKit when available (smaller than full).
      canvasKitVariant: "auto",
    },
    onEntrypointLoaded: async function (engineInitializer) {
      var appRunner = await engineInitializer.initializeEngine();
      var splash = document.getElementById("splash");
      if (splash) {
        splash.style.opacity = "0";
        setTimeout(function () {
          if (splash && splash.parentNode) splash.parentNode.removeChild(splash);
        }, 280);
      }
      await appRunner.runApp();
    },
  });
})();
