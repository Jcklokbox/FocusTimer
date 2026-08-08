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

        private const uint TIMEOUT = 10000;

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
        private uint                    timeout_id = 0U;
        private uint                    emitted_status = Mpris.PlaybackStatus.UNKNOWN;
        private Mpris.PlaybackStatus    pending_status = Mpris.PlaybackStatus.UNKNOWN;

        internal Ft.State               associated_state = Ft.State.STOPPED;
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
                    this.pending_status != Mpris.PlaybackStatus.PAUSED)
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

        private bool on_timeout ()
        {
            this.timeout_id = 0;
            this.pending_status = Mpris.PlaybackStatus.UNKNOWN;

            if (this._status != this.emitted_status) {
                this.status_changed (this._status, this.emitted_status);
            }

            return GLib.Source.REMOVE;
        }

        public bool is_pausing ()
        {
            return this.pending_status == Mpris.PlaybackStatus.PAUSED ||
                   this.pending_status == Mpris.PlaybackStatus.STOPPED;
        }

        public bool is_resuming ()
        {
            return this.pending_status == Mpris.PlaybackStatus.PLAYING;
        }

        /**
         * Returns `true` when status changed due to call.
         */
        public async bool pause ()
        {
            var pending_status = this.player_proxy.can_pause
                    ? Mpris.PlaybackStatus.PAUSED
                    : Mpris.PlaybackStatus.STOPPED;

            if (this._status == pending_status &&
                this.pending_status == Mpris.PlaybackStatus.UNKNOWN)
            {
                return false;  // no change
            }

            if (this.pending_status == pending_status) {
                return true;  // XXX: wait until call ends, return true status
            }

            if (this.timeout_id != 0) {
                GLib.Source.remove (this.timeout_id);
                this.timeout_id = 0;
            }

            this.timeout_id = GLib.Timeout.add (TIMEOUT, this.on_timeout);
            this.pending_status = pending_status;
            this.paused_timestamp = GLib.get_monotonic_time ();

            try {
                if (pending_status != Mpris.PlaybackStatus.STOPPED) {
                    yield this.player_proxy.pause ();
                }
                else {
                    yield this.player_proxy.play_pause ();
                }
            }
            catch (GLib.Error error) {
                GLib.warning ("Failed to pause player %s: %s", this.dbus_name, error.message);

                if (this.timeout_id != 0) {
                    GLib.Source.remove (this.timeout_id);
                    this.on_timeout ();
                }

                return false;
            }

            return true;
        }

        /**
         * Returns `true` when status changed due to call.
         */
        public async bool resume ()
        {
            if (this._status == Mpris.PlaybackStatus.PLAYING &&
                this.pending_status == Mpris.PlaybackStatus.UNKNOWN)
            {
                return false;
            }

            if (!this.player_proxy.can_play || Ft.Timestamp.is_undefined (this.paused_timestamp)) {
                return false;
            }

            if (this.pending_status == Mpris.PlaybackStatus.PLAYING) {
                return true;  // XXX: wait until call ends, return true status
            }

            if (this.timeout_id != 0) {
                GLib.Source.remove (this.timeout_id);
                this.timeout_id = 0;
            }

            this.timeout_id = GLib.Timeout.add (TIMEOUT, this.on_timeout);

            var pause_duration = GLib.get_monotonic_time () - this.paused_timestamp;

            if (pause_duration >= Ft.Interval.MINUTE &&
                this._status == Mpris.PlaybackStatus.PAUSED &&
                this.player_proxy.can_seek)
            {
                try {
                    yield this.player_proxy.seek (-REWIND_INTERVAL / Ft.Interval.MICROSECOND);
                }
                catch (GLib.Error error) {
                    GLib.debug ("Failed to rewind player %s: %s", this.dbus_name, error.message);
                }
            }

            try {
                this.pending_status = Mpris.PlaybackStatus.PLAYING;
                this.paused_timestamp = Ft.Timestamp.UNDEFINED;

                if (this._status != Mpris.PlaybackStatus.STOPPED) {
                    yield this.player_proxy.play ();
                }
                else {
                    yield this.player_proxy.play_pause ();
                }
            }
            catch (GLib.Error error) {
                GLib.warning ("Failed to resume player %s: %s", this.dbus_name, error.message);

                if (this.timeout_id != 0) {
                    GLib.Source.remove (this.timeout_id);
                    this.on_timeout ();
                }

                return false;
            }

            return true;
        }

        [Signal (run = "last")]
        public signal void status_changed (Mpris.PlaybackStatus status,
                                           Mpris.PlaybackStatus previous_status)
        {
            this.emitted_status = status;

            if (status == this.pending_status && this.timeout_id != 0) {
                GLib.Source.remove (this.timeout_id);
                this.timeout_id = 0;
                this.pending_status = Mpris.PlaybackStatus.UNKNOWN;
            }
        }

        public override void dispose ()
        {
            if (this.status_changed_id != 0) {
                GLib.Source.remove (this.status_changed_id);
                this.status_changed_id = 0;
            }

            if (this.timeout_id != 0) {
                GLib.Source.remove (this.timeout_id);
                this.timeout_id = 0;
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
