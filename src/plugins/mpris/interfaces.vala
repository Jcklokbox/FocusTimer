/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Mpris
{
    public const string DBUS_NAME_PREFIX = "org.mpris.MediaPlayer2.";


    public enum PlaybackStatus
    {
        UNKNOWN,
        STOPPED,
        PLAYING,
        PAUSED;

        public static PlaybackStatus from_string (string? status)
        {
            switch (status)
            {
                case "Stopped":
                    return STOPPED;

                case "Playing":
                    return PLAYING;

                case "Paused":
                    return PAUSED;

                default:
                    return UNKNOWN;
            }
        }
    }


    /**
     * https://specifications.freedesktop.org/mpris/latest/Player_Interface.html
     */
    [DBus (name = "org.mpris.MediaPlayer2.Player")]
    public interface Player: GLib.Object
    {
        public abstract string playback_status { owned get; }
        public abstract bool can_play { get; }
        public abstract bool can_pause { get; }
        public abstract bool can_seek { get; }

        public abstract async void play () throws GLib.DBusError, GLib.IOError;
        public abstract async void play_pause () throws GLib.DBusError, GLib.IOError;
        public abstract async void pause () throws GLib.DBusError, GLib.IOError;
        public abstract async void seek (int64 offset) throws GLib.DBusError, GLib.IOError;
    }


    internal string[] list_dbus_names (GLib.DBusConnection connection,
                                       int                 timeout = -1)  // milliseconds
    {
        string[] dbus_names = {};

        try {
            var result = connection.call_sync (
                    "org.freedesktop.DBus",
                    "/org/freedesktop/DBus",
                    "org.freedesktop.DBus",
                    "ListNames",
                    null,
                    new GLib.VariantType ("(as)"),
                    GLib.DBusCallFlags.NONE,
                    timeout,
                    null);

            foreach (var name in result.get_child_value (0).get_strv ()) {
                dbus_names += name;
            }
        }
        catch (GLib.Error error) {
            GLib.debug ("Failed to list D-Bus names: %s", error.message);
        }

        return dbus_names;
    }


    internal delegate void NameOwnerChangedFunc (GLib.DBusConnection connection,
                                                 string              name,
                                                 string              old_owner,
                                                 string              new_owner);


    internal uint dbus_subscribe_name_owner_changed (GLib.DBusConnection  connection,
                                                     NameOwnerChangedFunc func)
    {
        return connection.signal_subscribe (
            "org.freedesktop.DBus",
            "org.freedesktop.DBus",
            "NameOwnerChanged",
            "/org/freedesktop/DBus",
            null,
            GLib.DBusSignalFlags.NONE,
            (connection_, sender_name, object_path, interface_name, signal_name, parameters) => {
                func (connection_,
                      parameters.get_child_value (0).get_string (),
                      parameters.get_child_value (1).get_string (),
                      parameters.get_child_value (2).get_string ());
            });
    }
}
