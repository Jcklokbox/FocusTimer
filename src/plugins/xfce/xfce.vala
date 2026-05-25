/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Xfce
{
    [ModuleInit]
    public void peas_register_types (GLib.TypeModule module)
    {
        var object_module = module as Peas.ObjectModule;

        if (Ft.get_desktop_name () != "xfce") {
            return;
        }

        object_module.register_extension_type (typeof (Ft.ScreenSaverProvider),
                                               typeof (Xfce.ScreenSaverProvider));
    }
}
