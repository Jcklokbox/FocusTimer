if get_option('plugin_sni').enabled()
  sni_plugin_resources = gnome.compile_resources(
    'sni-plugin-resources',
    'sni.gresource.xml',
    c_name: 'sni_plugin',
  )

  libft_plugin_sni = static_library(
    'ft_plugin_sni',
    files(
      'capabilities.vala',
      'indicator-action-group.vala',
      'indicator-provider.vala',
      'interfaces.vala',
      'dbus-services.vala',
      'menu-item.vala',
      'preferences-window-extension.vala',
      'sni.vala',
    ) + sni_plugin_resources,
    dependencies: [libft_ui_dep],
    include_directories: config_h_dir,
  )

  libft_plugins += [libft_plugin_sni]

  # GSchema
  install_data(
    'io.github.focustimerhq.FocusTimer.plugins.sni.gschema.xml',
    install_dir: gschema_dir,
  )

  compile_schemas = find_program('glib-compile-schemas', required: false)
  if compile_schemas.found()
    test('Validate sni schema file', compile_schemas,
      args: ['--strict', '--dry-run', meson.current_source_dir()]
    )
  endif

  compiled_schemas = gnome.compile_schemas(
    depend_files: 'io.github.focustimerhq.FocusTimer.plugins.sni.gschema.xml'
  )
endif