{{flutter_js}}
{{flutter_build_config}}

// Carrega o painel e, quando ele começa a desenhar, tira o "Carregando".
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    try {
      const appRunner = await engineInitializer.initializeEngine();
      await appRunner.runApp();
    } finally {
      const aviso = document.getElementById('carregando');
      if (aviso) aviso.remove();
    }
  },
});
