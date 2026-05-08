/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Xfce
{
    /**
     * https://docs.xfce.org/apps/xfce4-screensaver/dbus
     */
    [DBus (name = "org.xfce.ScreenSaver")]
    public interface ScreenSaver : GLib.Object
    {
        public abstract async bool get_active () throws GLib.DBusError, GLib.IOError;
        [DBus (no_reply = true)]
        public abstract async void @lock () throws GLib.DBusError, GLib.IOError;

        public signal void active_changed (bool new_value);
    }
}
