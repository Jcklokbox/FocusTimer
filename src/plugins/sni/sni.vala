/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Sni
{
    [ModuleInit]
    public void peas_register_types (GLib.TypeModule module)
    {
        var object_module = module as Peas.ObjectModule;

        object_module.register_extension_type (typeof (Ft.PreferencesWindowExtension),
                                               typeof (Sni.PreferencesWindowExtension));

        object_module.register_extension_type (typeof (Ft.IndicatorProvider),
                                               typeof (Sni.IndicatorProvider));
    }
}
