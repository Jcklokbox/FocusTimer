mpris_plugin_resources = gnome.compile_resources(
  'mpris-plugin-resources',
  'mpris.gresource.xml',
  c_name: 'mpris_plugin',
)

libft_plugin_mpris = static_library(
  'ft_plugin_mpris',
  files(
    'application-extension.vala',
    'interfaces.vala',
    'mpris.vala',
    'player-wrapper.vala',
    'preferences-window-extension.vala',
  ) + mpris_plugin_resources,
  dependencies: [
    libft_ui_dep,
    gio_dep,
    peas_dep,
  ],
  include_directories: config_h_dir,
)

# GSchema
install_data(
  'io.github.focustimerhq.FocusTimer.plugins.mpris.gschema.xml',
  install_dir: gschema_dir,
)

compile_schemas = find_program('glib-compile-schemas', required: false)
if compile_schemas.found()
  test('Validate mpris schema file', compile_schemas,
    args: ['--strict', '--dry-run', meson.current_source_dir()]
  )
endif

compiled_schemas = gnome.compile_schemas(
  depend_files: 'io.github.focustimerhq.FocusTimer.plugins.mpris.gschema.xml'
)

libft_plugins += [libft_plugin_mpris]
