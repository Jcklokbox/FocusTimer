if get_option('plugin_kde').enabled()
  kde_plugin_resources = gnome.compile_resources(
    'kde-plugin-resources',
    'kde.gresource.xml',
    c_name: 'kde_plugin',
  )

  libft_plugin_kde = static_library(
    'ft_plugin_kde',
    files(
      'application-extension.vala',
      'interfaces.vala',
      'kde.vala',
      'preferences-window-extension.vala',
    ) + kde_plugin_resources,
    dependencies: [libft_ui_dep],
    include_directories: config_h_dir,
  )

  libft_plugins += [libft_plugin_kde]

  # GSchema
  install_data(
    'io.github.focustimerhq.FocusTimer.plugins.kde.gschema.xml',
    install_dir: gschema_dir,
  )

  compile_schemas = find_program('glib-compile-schemas', required: false)
  if compile_schemas.found()
    test('Validate kde schema file', compile_schemas,
      args: ['--strict', '--dry-run', meson.current_source_dir()]
    )
  endif

  compiled_schemas = gnome.compile_schemas(
    depend_files: 'io.github.focustimerhq.FocusTimer.plugins.kde.gschema.xml'
  )

  subdir('data')
endif
