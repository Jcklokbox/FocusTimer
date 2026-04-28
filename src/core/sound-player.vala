/*
 * Copyright (c) 2016,2024,2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

using GLib;


namespace Ft
{
    [Flags]
    private enum GstPlayFlags {
        VIDEO             = 0x00000001,
        AUDIO             = 0x00000002,
        TEXT              = 0x00000004,
        VIS               = 0x00000008,
        SOFT_VOLUME       = 0x00000010,
        NATIVE_AUDIO      = 0x00000020,
        NATIVE_VIDEO      = 0x00000040,
        DOWNLOAD          = 0x00000080,
        BUFFERING         = 0x00000100,
        DEINTERLACE       = 0x00000200,
        SOFT_COLORBALANCE = 0x00000400,
        FORCE_FILTERS     = 0x00000800
    }


    public class SoundPlayer : GLib.Object
    {
        private const uint LATENCY = 200;  // milliseconds

        public string uri {
            get {
                return this.pipeline.uri;
            }
            set {
                Gst.State state;
                Gst.State pending_state;

                this.pipeline.get_state (out state,
                                         out pending_state,
                                         Gst.CLOCK_TIME_NONE);

                if (pending_state != Gst.State.VOID_PENDING) {
                    state = pending_state;
                }

                if (state == Gst.State.PLAYING) {
                    this.pipeline.set_state (Gst.State.READY);
                    this.pipeline.uri = value;
                    this.pipeline.set_state (Gst.State.PLAYING);
                }
                else {
                    this.pipeline.uri = value;
                    this.pipeline.set_state (Gst.State.READY);
                }
            }
        }

        public double volume {
            get {
                return this.pipeline.volume;
            }
            set {
                this.pipeline.volume = value.clamp (0.0, 1.0);
            }
        }

        public bool loop { get; set; default = false; }

        private dynamic Gst.Element                        pipeline;
        private dynamic Gst.Element                        volume_filter;
        private dynamic Gst.Element                        audio_sink;
        private Gst.Controller.InterpolationControlSource? volume_interpolation;
        private bool                                       _is_playing = false;
        private bool                                       is_about_to_finish = false;
        private double                                     fade_to = 0.0;
        private uint                                       stop_timeout_id = 0;
        private uint                                       park_timeout_id = 0;

        private static bool is_gstreamer_initialized = false;

        public SoundPlayer () throws GLib.Error
        {
            if (!is_gstreamer_initialized)
            {
                unowned string[] args_unowned = null;
                Gst.init (ref args_unowned);

                is_gstreamer_initialized = true;
            }

            dynamic Gst.Element pipeline = Gst.ElementFactory.make ("playbin", "player");
            dynamic Gst.Element volume_filter = Gst.ElementFactory.make ("volume", "volume");
            dynamic Gst.Element audio_sink = Gst.ElementFactory.make ("autoaudiosink", "audio-output");

            if (pipeline == null || volume_filter == null || audio_sink == null) {
                throw new Ft.SoundError.NOT_INITIALIZED (_("Failed to initialize playback"));
            }

            pipeline.flags = GstPlayFlags.AUDIO;
            pipeline.audio_filter = volume_filter;
            pipeline.audio_sink = audio_sink;

            // Keep the audio sink locked at NULL when idle. This forces
            // autoaudiosink to re-probe for the current default device on each
            // play(), while the source/decoder stays warm.
            audio_sink.set_locked_state (true);

            pipeline.about_to_finish.connect (this.on_about_to_finish);
            pipeline.get_bus ().add_watch (GLib.Priority.DEFAULT, this.on_bus_callback);

            this.pipeline = pipeline;
            this.volume_filter = volume_filter;
            this.audio_sink = audio_sink;
        }

        public static string[] get_supported_mime_types ()
        {
            return {
                "audio/*"
            };
        }

        private void finished ()
        {
            string current_uri;

            if (this.loop)
            {
                this.pipeline.@get ("current-uri", out current_uri);

                if (current_uri != "") {
                    this.pipeline.@set ("uri", current_uri);
                }
            }
        }

        private void on_about_to_finish ()
        {
            this.is_about_to_finish = true;

            this.finished ();

            if (this.loop && this.volume_interpolation != null)
            {
                var running_time = this.get_running_time ();
                var current_fade_value = this.get_fade_value (running_time);

                var control_points = new Gst.TimedValue[0];
                this.volume_interpolation.get_all ().@foreach (
                    (control_point) => {
                        if (control_point.timestamp > running_time) {
                            control_points += Gst.TimedValue () {
                                timestamp = control_point.timestamp - running_time,
                                value = control_point.value,
                            };
                        }
                    });

                if (control_points.length > 0)
                {
                    this.volume_interpolation.unset_all ();
                    this.volume_interpolation.@set (0, current_fade_value);

                    foreach (var control_point in control_points) {
                        this.volume_interpolation.@set (control_point.timestamp,
                                                        control_point.value);
                    }
                }
                else {
                    this.volume_interpolation.unset_all ();
                    this.volume_interpolation.@set (0, this.fade_to);
                }
            }
        }

        private bool on_bus_callback (Gst.Bus     bus,
                                      Gst.Message message)
        {
            Gst.State   state;
            Gst.State   pending_state;
            GLib.Error? error = null;
            string?     debug_info = null;

            var src_name = message.src != null ? message.src.name : "<unknown>";

            this.pipeline.get_state (out state,
                                     out pending_state,
                                     Gst.CLOCK_TIME_NONE);

            switch (message.type)
            {
                case Gst.MessageType.STATE_CHANGED:
                    if (!this._is_playing && state == Gst.State.PLAYING) {
                        this._is_playing = true;
                        this.playback_started ();
                    }

                    if (this._is_playing && state != Gst.State.PLAYING) {
                        this._is_playing = false;
                        this.playback_stopped ();
                    }

                    break;

                case Gst.MessageType.EOS:
                    if (this.is_about_to_finish) {
                        this.is_about_to_finish = false;
                    }
                    else {
                        this.finished ();
                    }

                    if (!this.loop && pending_state != Gst.State.PLAYING)
                    {
                        this.pipeline.set_state (Gst.State.READY);
                        this.park_audio_sink ();
                    }

                    break;

                case Gst.MessageType.ERROR:
                    if (this.is_about_to_finish) {
                        this.is_about_to_finish = false;
                    }

                    message.parse_error (out error, out debug_info);
                    GLib.warning ("SoundPlayer error from %s: %s [debug: %s]",
                                  src_name,
                                  error.message,
                                  debug_info ?? "");

                    this.pipeline.set_state (Gst.State.NULL);
                    this.playback_error (error);
                    break;

                case Gst.MessageType.WARNING:
                    message.parse_warning (out error, out debug_info);
                    GLib.warning ("SoundPlayer warning from %s: %s [debug: %s]",
                                  src_name,
                                  error.message,
                                  debug_info ?? "");
                    break;

                default:
                    break;
            }

            return GLib.Source.CONTINUE;
        }

        public Gst.ClockTime get_running_time ()
        {
            var running_time = (Gst.ClockTime) 0;
            pipeline.query_position (Gst.Format.TIME, out running_time);

            return running_time;
        }

        private void park_audio_sink ()
        {
            if (this.park_timeout_id != 0) {
                GLib.Source.remove (this.park_timeout_id);
                this.park_timeout_id = 0;
            }

            this.audio_sink.set_locked_state (true);
            this.audio_sink.set_state (Gst.State.NULL);
        }

        private void ensure_volume_interpolation ()
        {
            if (this.volume_interpolation != null) {
                return;
            }

            var volume_interpolation = new Gst.Controller.InterpolationControlSource ();
            volume_interpolation.mode = Gst.Controller.InterpolationMode.LINEAR;
            volume_interpolation.@set (0, 1.0);

            var binding = new Gst.Controller.DirectControlBinding.with_absolute (
                    this.volume_filter, "volume", volume_interpolation);
            this.volume_filter.add_control_binding (binding);

            this.volume_interpolation = volume_interpolation;
        }

        private double get_fade_value (Gst.ClockTime running_time)
        {
            double fade_value = double.NAN;

            if (running_time == Gst.CLOCK_TIME_NONE) {
                return this.fade_to;
            }

            if (this.volume_interpolation != null &&
                this.volume_interpolation.get_value (running_time, out fade_value))
            {
                return fade_value;
            }

            return this.fade_to;
        }

        private void unschedule_stop ()
        {
            if (this.stop_timeout_id != 0) {
                GLib.Source.remove (this.stop_timeout_id);
                this.stop_timeout_id = 0;
            }
        }

        private bool on_stop_timeout ()
        {
            this.stop_timeout_id = 0;
            this.stop ();
            return GLib.Source.REMOVE;
        }

        public void play ()
                          requires (this.pipeline != null)
        {
            if (this.park_timeout_id != 0) {
                GLib.Source.remove (this.park_timeout_id);
                this.park_timeout_id = 0;
            }

            if (this.uri != "") {
                this.audio_sink.set_locked_state (false);
                this.pipeline.set_state (Gst.State.PLAYING);
            }
        }

        public void stop ()
        {
            Gst.State state;
            Gst.State pending_state;

            if (this.pipeline == null) {
                return;
            }

            this.pipeline.get_state (out state,
                                     out pending_state,
                                     Gst.CLOCK_TIME_NONE);

            if (pending_state != Gst.State.VOID_PENDING) {
                state = pending_state;
            }

            if (state != Gst.State.NULL && state != Gst.State.READY) {
                this.pipeline.set_state (Gst.State.READY);

                // set_state() is async; wait for READY before scheduling
                // the park. Without this wait the audio sink could still be
                // mid-transition when the deferred park fires.
                this.pipeline.get_state (out state,
                                         out pending_state,
                                         Gst.CLOCK_TIME_NONE);
            }

            // Defer the hardware teardown to let the PulseAudio DMA buffer
            // drain to silence before disconnecting the stream. Immediate
            // disconnect (NULL) while samples are still in the DMA buffer
            // causes an occasional pop even when volume is zero.
            if (this.park_timeout_id == 0) {
                this.park_timeout_id = GLib.Timeout.add (LATENCY, () => {
                    this.park_timeout_id = 0;
                    this.park_audio_sink ();
                    return GLib.Source.REMOVE;
                });
            }
        }

        public bool is_playing ()
        {
            return this._is_playing;
        }

        public void fade_in (int64 duration)
        {
            var running_time = this.get_running_time ();
            var current_fade_value = this.get_fade_value (running_time);

            this.unschedule_stop ();
            this.fade_to = 1.0;
            this.ensure_volume_interpolation ();

            if (current_fade_value == 1.0) {
                return;
            }

            if (duration <= 0) {
                this.volume_interpolation.unset_all ();
                this.volume_interpolation.@set (0, this.fade_to);
            }
            else if (running_time == 0 || running_time == Gst.CLOCK_TIME_NONE) {
                this.volume_interpolation.unset_all ();
                this.volume_interpolation.@set (0, current_fade_value);
                this.volume_interpolation.@set (0 + (Gst.ClockTime) duration * 1000, this.fade_to);
            }
            else {
                var latency = LATENCY * Gst.MSECOND;
                var latency_fade_value = this.get_fade_value (running_time + latency);

                this.volume_interpolation.unset_all ();
                this.volume_interpolation.@set (running_time, current_fade_value);
                this.volume_interpolation.@set (running_time + latency, latency_fade_value);
                this.volume_interpolation.@set (running_time + latency + (Gst.ClockTime) duration * 1000, this.fade_to);
            }

            if (!this._is_playing) {
                this.play ();
            }
        }

        public void fade_out (int64 duration)
        {
            var running_time = this.get_running_time ();
            var current_fade_value = this.get_fade_value (running_time);

            this.ensure_volume_interpolation ();
            this.unschedule_stop ();
            this.fade_to = 0.0;

            if (!this._is_playing || running_time == Gst.CLOCK_TIME_NONE || current_fade_value == 0.0) {
                return;
            }

            if (duration <= 0)
            {
                this.volume_interpolation.unset_all ();
                this.volume_interpolation.@set (0, this.fade_to);

                this.stop ();
            }
            else {
                var latency = LATENCY * Gst.MSECOND;
                var latency_fade_value = this.get_fade_value (running_time + latency);

                this.volume_interpolation.unset_all ();
                this.volume_interpolation.@set (running_time, current_fade_value);
                this.volume_interpolation.@set (running_time + latency, latency_fade_value);
                this.volume_interpolation.@set (running_time + latency + (Gst.ClockTime) duration * 1000, this.fade_to);

                // GStreamer doesn't have a signal for when the interpolation is completed.
                // Approximate it with timeout.
                this.stop_timeout_id = GLib.Timeout.add (
                        Ft.Timestamp.to_milliseconds_uint (duration) + LATENCY,
                        this.on_stop_timeout);
            }
        }

        public signal void playback_started ();

        public virtual signal void playback_stopped ()
        {
            this.unschedule_stop ();

            if (this.volume_interpolation != null) {
                this.volume_interpolation.unset_all ();
                this.volume_interpolation.@set (0, 0.0);
            }
        }

        public signal void playback_error (GLib.Error error);

        public override void dispose ()
        {
            this.unschedule_stop ();

            if (this.park_timeout_id != 0) {
                GLib.Source.remove (this.park_timeout_id);
                this.park_timeout_id = 0;
            }

            if (this.pipeline != null) {
                this.audio_sink.set_locked_state (false);
                this.pipeline.set_state (Gst.State.NULL);
            }

            this.audio_sink = null;
            this.volume_filter = null;
            this.pipeline = null;

            base.dispose ();
        }
    }
}
