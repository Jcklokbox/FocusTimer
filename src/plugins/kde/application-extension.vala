/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Kde
{
    public class ApplicationExtension : Ft.ApplicationExtension
    {
        private GLib.Settings?      settings = null;
        private Ft.SessionManager?  session_manager = null;
        private uint                notifications_watcher_id = 0;
        private Kde.Notifications?  notifications_proxy = null;
        private uint32              notifications_inhibitor_id = 0;
        private GLib.Cancellable?   cancellable = null;

        construct
        {
            this.cancellable = new GLib.Cancellable ();
            this.session_manager = Ft.SessionManager.get_default ();
            this.session_manager.notify["current-state"].connect (this.on_notify_current_state);

            this.settings = new GLib.Settings ("io.github.focustimerhq.FocusTimer.plugins.kde");
            this.settings.changed.connect (this.on_settings_changed);

            this.notifications_watcher_id = GLib.Bus.watch_name (
                    GLib.BusType.SESSION,
                    "org.freedesktop.Notifications",
                    GLib.BusNameWatcherFlags.NONE,
                    this.on_notifications_proxy_name_appeared,
                    this.on_notifications_proxy_name_vanished);
        }

        private void update_notifications_inhibitor ()
        {
            var proxy = this.notifications_proxy;
            if (proxy == null) {
                return;
            }

            var should_inhibit = this.session_manager != null
                    ? this.session_manager.current_state != Ft.State.STOPPED &&
                      this.settings.get_boolean ("manage-notifications")
                    : false;
            var notifications_inhibitor_id = this.notifications_inhibitor_id;

            if (should_inhibit &&
                notifications_inhibitor_id == 0 &&
                this.cancellable != null)
            {
                var inhibit_hints = new GLib.HashTable<string, GLib.Variant> (GLib.str_hash,
                                                                              GLib.str_equal);
                proxy.inhibit.begin (
                    Config.APPLICATION_ID,
                    "",
                    inhibit_hints,
                    this.cancellable,
                    (obj, res) => {
                        try {
                            this.notifications_inhibitor_id = proxy.inhibit.end (res);
                        }
                        catch (GLib.Error error) {
                            GLib.warning ("Unable to add notifications inhibitor: %s",
                                          error.message);
                        }
                    });
            }

            if (!should_inhibit && notifications_inhibitor_id != 0 ||
                this.cancellable == null)
            {
                proxy.uninhibit.begin (
                    notifications_inhibitor_id,
                    (obj, res) => {
                        try {
                            proxy.uninhibit.end (res);

                            if (this.notifications_inhibitor_id == notifications_inhibitor_id) {
                                this.notifications_inhibitor_id = 0U;
                            }
                        }
                        catch (GLib.Error error) {
                            GLib.warning ("Unable to remove notifications inhibitor: %s",
                                          error.message);
                        }
                    });
            }
        }

        private void on_notifications_proxy_name_appeared (GLib.DBusConnection connection,
                                                           string              name,
                                                           string              name_owner)
        {
            string server_name;
            string server_vendor;
            string version;
            string spec_version;

            if (this.notifications_proxy != null) {
                return;
            }

            try {
                var proxy = GLib.Bus.get_proxy_sync<Kde.Notifications> (
                        GLib.BusType.SESSION,
                        "org.freedesktop.Notifications",
                        "/org/freedesktop/Notifications",
                        GLib.DBusProxyFlags.DO_NOT_AUTO_START |
                        GLib.DBusProxyFlags.DO_NOT_CONNECT_SIGNALS,
                        this.cancellable);
                proxy.get_server_information (out server_name,
                                              out server_vendor,
                                              out version,
                                              out spec_version);

                if (server_name != "Plasma" || server_vendor != "KDE") {
                    GLib.debug ("Notifications proxy is not from KDE: %s (%s)", server_name, server_vendor);
                    return;
                }

                this.notifications_proxy = proxy;
                this.update_notifications_inhibitor ();
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while initializing notifications proxy: %s", error.message);
            }
        }

        private void on_notifications_proxy_name_vanished (GLib.DBusConnection? connection,
                                                           string               name)
        {
            this.notifications_proxy = null;
        }

        private void on_notify_current_state ()
        {
            this.update_notifications_inhibitor ();
        }

        private void on_settings_changed (GLib.Settings settings,
                                          string        key)
        {
            switch (key)
            {
                case "manage-notifications":
                    this.update_notifications_inhibitor ();
                    break;

                default:
                    break;
            }
        }

        public override void dispose ()
        {
            if (this.cancellable != null) {
                this.cancellable.cancel ();
                this.cancellable = null;
            }

            if (this.notifications_watcher_id != 0) {
                GLib.Bus.unwatch_name (this.notifications_watcher_id);
                this.notifications_watcher_id = 0;
            }

            if (this.settings != null)
            {
                this.update_notifications_inhibitor ();

                this.settings.changed.disconnect (this.on_settings_changed);
                this.settings = null;
            }

            this.notifications_proxy = null;

            base.dispose ();
        }
    }
}
