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

        private const uint DEBOUNCE_TIMEOUT = 100;

        public Mpris.PlaybackStatus status {
            get {
                return this._status;
            }
        }

        public bool can_pause {
            get {
                return this.player_proxy != null
                        ? this.player_proxy.can_pause
                        : false;
            }
        }

        private Mpris.PlaybackStatus    _status = Mpris.PlaybackStatus.UNKNOWN;
        private Mpris.Player?           player_proxy = null;
        private int64                   paused_timestamp = Ft.Timestamp.UNDEFINED;
        private string                  dbus_name;
        private uint                    status_changed_id = 0;
        private uint                    emitted_status = Mpris.PlaybackStatus.UNKNOWN;

        internal Ft.State               status_changed_state = Ft.State.STOPPED;
        internal Mpris.PlaybackStatus   ignore_status = Mpris.PlaybackStatus.UNKNOWN;
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

                if (this.status_changed_id != 0) {
                    GLib.Source.remove (this.status_changed_id);
                    this.status_changed_id = 0;
                }

                if (status == Mpris.PlaybackStatus.PAUSED &&
                    previous_status == Mpris.PlaybackStatus.PLAYING &&
                    this.ignore_status != Mpris.PlaybackStatus.PAUSED)
                {
                    // Debounce `signal-changed` signal. The player may pause and resume playback
                    // when seeking.
                    this.status_changed_id = GLib.Timeout.add (
                        DEBOUNCE_TIMEOUT,
                        () => {
                            this.status_changed_id = 0;

                            if (this._status != this.emitted_status) {
                                this.status_changed (this._status, this.emitted_status);
                            }

                            return GLib.Source.REMOVE;
                        });
                }
                else if (status != this.emitted_status) {
                    this.status_changed (status, this.emitted_status);
                }
            }
        }

        private void on_properties_changed (GLib.Variant changed_properties,
                                            string[]     invalidated_properties)
        {
            this.update_properties ();
        }

        public async bool pause ()
        {
            try {
                if (this.player_proxy.can_pause) {
                    this.ignore_status = Mpris.PlaybackStatus.PAUSED;
                    yield this.player_proxy.pause ();
                }
                else {
                    this.ignore_status = Mpris.PlaybackStatus.STOPPED;
                    yield this.player_proxy.play_pause ();
                }

                this.paused_timestamp = GLib.get_monotonic_time ();
            }
            catch (GLib.Error error) {
                GLib.warning ("Failed to pause player %s: %s", this.dbus_name, error.message);
                return false;
            }

            return true;
        }

        public async bool resume ()
        {
            if (!this.player_proxy.can_play) {
                return false;
            }

            if (Ft.Timestamp.is_undefined (this.paused_timestamp)) {
                return false;
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
                this.ignore_status = Mpris.PlaybackStatus.PLAYING;

                if (this.status == Mpris.PlaybackStatus.PAUSED) {
                    yield this.player_proxy.play ();
                }
                else {
                    yield this.player_proxy.play_pause ();
                }
            }
            catch (GLib.Error error) {
                GLib.warning ("Failed to resume player %s: %s", this.dbus_name, error.message);
                return false;
            }

            return true;
        }

        [Signal (run = "first")]
        public signal void status_changed (Mpris.PlaybackStatus status,
                                           Mpris.PlaybackStatus previous_status)
        {
            this.emitted_status = status;
        }

        public override void dispose ()
        {
            if (this.status_changed_id != 0) {
                GLib.Source.remove (this.status_changed_id);
                this.status_changed_id = 0;
            }

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
