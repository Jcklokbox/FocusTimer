if get_option('plugin_kde').enabled()
  kde_plugin_resources = gnome.compile_resources(
    'kde-plugin-resources',
    'kde.gresource.xml',
    c_name: 'kde_plugin',
  )

  libft_plugin_kde = static_library(
    'ft_plugin_kde',
    files(
      'kde.vala',
      'preferences-window-extension.vala',
    ) + kde_plugin_resources,
    dependencies: [libft_ui_dep],
    include_directories: config_h_dir,
  )

  libft_plugins += [libft_plugin_kde]

  subdir('data')
endif
