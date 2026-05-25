/*
 * Copyright (c) 2023-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Freedesktop
{
    public struct Session
    {
        public string session_id;
        public uint32 user_id;
        public string user_name;
        public string seat_id;
        public string object_path;
    }


    [DBus (name = "org.freedesktop.login1.Manager")]
    public interface LoginManager : GLib.Object
    {
        public abstract async Session[] list_sessions () throws GLib.DBusError, GLib.IOError;

        public signal void prepare_for_sleep (bool active);
    }


    [DBus (name = "org.freedesktop.login1.Session")]
    public interface LoginSession : GLib.Object
    {
        public abstract string id { owned get; }
        public abstract bool active { get; }
        public abstract bool locked_hint { get; }

        [DBus (no_reply = true)]
        public abstract async void @lock () throws GLib.DBusError, GLib.IOError;
    }


    [DBus (name = "org.freedesktop.timedate1")]
    public interface TimeDate : GLib.Object
    {
        public abstract string timezone { owned get; }
    }


    public enum NotificationDestroyedReason
    {
        EXPIRED = 1,
        DISMISSED = 2,
        CLOSED = 3,
        UNKNOWN = 4;

        public static NotificationDestroyedReason from_uint (uint32 value)
        {
            switch (value)
            {
                case EXPIRED:
                    return EXPIRED;

                case DISMISSED:
                    return DISMISSED;

                case CLOSED:
                    return CLOSED;

                default:
                    return UNKNOWN;
            }
        }
    }


    public enum NotificationUrgency
    {
        LOW = 0,
        NORMAL = 1,
        CRITICAL = 2;

        public GLib.Variant to_variant ()
        {
            return new GLib.Variant.byte ((uint8) this);
        }
    }


    /**
     * https://specifications.freedesktop.org/notification/latest/protocol.html
     */
    [DBus (name = "org.freedesktop.Notifications")]
    public interface Notifications : GLib.Object
    {
        public abstract async string[] get_capabilities () throws GLib.DBusError, GLib.IOError;

        public abstract async void get_server_information (out string name,
                                                           out string vendor,
                                                           out string version,
                                                           out string spec_version) throws GLib.DBusError, GLib.IOError;

        public abstract async uint32 notify (string                               app_name,
                                         	 uint32                               replaces_id,
                                         	 string                               app_icon,
                                         	 string                               summary,
                                         	 string                               body,
                                         	 string[]                             actions,
                                         	 GLib.HashTable<string, GLib.Variant> hints,
                                         	 int32                                expire_timeout,  // milliseconds
                                         	 GLib.Cancellable?                    cancellable = null)
                                         	 throws GLib.DBusError, GLib.IOError;

        public abstract async void close_notification (uint32 id) throws GLib.DBusError, GLib.IOError;

        public signal void action_invoked (uint32 id, string action_key);
        public signal void activation_token (uint32 id, string activation_token);
        public signal void notification_closed (uint32 id, uint32 reason);
    }
}
