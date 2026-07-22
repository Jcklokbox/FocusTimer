/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Mpris
{
    [ModuleInit]
    public void peas_register_types (GLib.TypeModule module)
    {
        var object_module = module as Peas.ObjectModule;

        object_module.register_extension_type (typeof (Ft.ApplicationExtension),
                                               typeof (Mpris.ApplicationExtension));

        object_module.register_extension_type (typeof (Ft.PreferencesWindowExtension),
                                               typeof (Mpris.PreferencesWindowExtension));
    }
}
