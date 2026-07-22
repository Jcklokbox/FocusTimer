/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Mpris
{
    public class PlayerWrapper : GLib.Object
    {
        private const int64 REWIND_INTERVAL = 10 * Ft.Interval.SECOND;

        public Mpris.PlaybackStatus status {
            get {
                return this._status;
            }
        }

        private Mpris.PlaybackStatus    _status = Mpris.PlaybackStatus.UNKNOWN;
        private Mpris.Player?           player_proxy = null;
        private int64                   paused_timestamp = Ft.Timestamp.UNDEFINED;
        private string                  dbus_name;

        internal Ft.State               status_changed_state = Ft.State.STOPPED;
        internal bool                   ignore_status_change = false;
        internal bool                   auto_paused = false;

        public PlayerWrapper (string           dbus_name,
                              GLib.Cancellable cancellable)
        {
            this.dbus_name = dbus_name;

            this.init.begin (cancellable,
                (obj, res) => {
                    this.init.end (res);
                });
        }

        private async void init (GLib.Cancellable cancellable)
        {
            try {
                this.player_proxy = yield GLib.Bus.get_proxy<Mpris.Player> (
                        GLib.BusType.SESSION,
                        this.dbus_name,
                        "/org/mpris/MediaPlayer2",
                        GLib.DBusProxyFlags.DO_NOT_AUTO_START,
                        cancellable);

                var player_proxy = (GLib.DBusProxy) this.player_proxy;
                player_proxy.g_properties_changed.connect (this.on_properties_changed);

                this.update_properties ();
            }
            catch (GLib.Error error)
            {
                if (cancellable.is_cancelled ()) {
                    return;
                }

                GLib.warning ("Failed to initialize player %s: %s", this.dbus_name, error.message);
            }
        }

        private void update_properties ()
        {
            var status = Mpris.PlaybackStatus.from_string (this.player_proxy.playback_status);

            if (this._status != status)
            {
                var previous_status = this._status;

                this._status = status;
                this.notify_property ("status");
                this.status_changed (status, previous_status);
            }
        }

        private void on_properties_changed (GLib.Variant changed_properties,
                                            string[]     invalidated_properties)
        {
            this.update_properties ();
        }

        public async void pause ()
        {
            if (!this.player_proxy.can_pause) {
                return;
            }

            try {
                yield this.player_proxy.pause ();

                this.paused_timestamp = GLib.get_monotonic_time ();
            }
            catch (GLib.Error error) {
                GLib.warning ("Failed to pause player %s: %s", this.dbus_name, error.message);
            }
        }

        public async void resume ()
        {
            if (!this.player_proxy.can_play) {
                return;
            }

            if (Ft.Timestamp.is_undefined (this.paused_timestamp)) {
                return;
            }

            var timestmap = GLib.get_monotonic_time ();
            var elapsed = timestmap - this.paused_timestamp;

            if (elapsed >= Ft.Interval.MINUTE && this.player_proxy.can_seek)
            {
                try {
                    yield this.player_proxy.seek (-REWIND_INTERVAL / Ft.Interval.MICROSECOND);
                }
                catch (GLib.Error error) {
                    GLib.debug ("Failed to rewind player %s: %s", this.dbus_name, error.message);
                }
            }

            try {
                yield this.player_proxy.play ();
            }
            catch (GLib.Error error) {
                GLib.warning ("Failed to rewind player %s: %s", this.dbus_name, error.message);
            }
        }

        public signal void status_changed (Mpris.PlaybackStatus status,
                                           Mpris.PlaybackStatus previous_status);

        public override void dispose ()
        {
            if (this.player_proxy != null)
            {
                var player_proxy = (GLib.DBusProxy) this.player_proxy;
                player_proxy.g_properties_changed.disconnect (this.on_properties_changed);

                this.player_proxy = null;
            }

            base.dispose ();
        }
    }
}
