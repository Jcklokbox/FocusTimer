if get_option('plugin_xfce').enabled()
  xfce_plugin_resources = gnome.compile_resources(
    'xfce-plugin-resources',
    'xfce.gresource.xml',
    c_name: 'xfce_plugin',
  )

  libft_plugin_xfce = static_library(
    'ft_plugin_xfce',
    files(
      'xfce.vala',
      'interfaces.vala',
      'screen-saver-provider.vala',
    ) + xfce_plugin_resources,
    dependencies: [libft_ui_dep],
    include_directories: config_h_dir,
  )

  libft_plugins += [libft_plugin_xfce]
endif