/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Kde
{
    /**
     * Not part of Freedesktop spec
     *
     * See https://invent.kde.org/plasma/plasma-workspace/-/blob/master/libnotificationmanager/server_p.cpp
     */
    [DBus (name = "org.freedesktop.Notifications")]
    public interface Notifications : GLib.Object
    {
        public abstract bool inhibited { get; }

        public abstract void get_server_information (out string name,
                                                     out string vendor,
                                                     out string version,
                                                     out string spec_version) throws GLib.DBusError, GLib.IOError;

        public abstract async uint32 inhibit (string                               desktop_entry,
                                              string                               reason,
                                              GLib.HashTable<string, GLib.Variant> hints,
                                              GLib.Cancellable?                    cancellable = null)
                                              throws GLib.DBusError, GLib.IOError;

        [DBus (name = "UnInhibit")]
        public abstract async void uninhibit (uint32 inhibitor_id)
                                              throws GLib.DBusError, GLib.IOError;
    }
}
