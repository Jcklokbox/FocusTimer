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
    private string build_absolute_path (string path)
    {
        return GLib.Path.build_filename (Config.PACKAGE_DATA_DIR, "sounds", path);
    }


    private string build_absolute_uri (string uri)
    {
        var scheme = GLib.Uri.parse_scheme (uri);

        if (scheme == null && uri != "")
        {
            var preset_filename = uri;
            var preset_path = build_absolute_path (preset_filename);

            try {
                return GLib.Filename.to_uri (preset_path);
            }
            catch (GLib.ConvertError error) {
                GLib.warning ("Failed to convert \"%s\" to URI: %s", preset_path, error.message);
            }
        }

        return uri;
    }


    private bool is_mime_type (string   content_type,
                               string[] mime_types)
    {
        if (GLib.ContentType.is_unknown (content_type)) {
            return false;
        }

        foreach (var mime_type in mime_types)
        {
            if (GLib.ContentType.is_mime_type (content_type, mime_type)) {
                return true;
            }
        }

        return false;
    }


    public errordomain SoundError
    {
        NOT_FOUND,
        NOT_INITIALIZED,
        NOT_SUPPORTED
    }


    /**
     * A sound player instance is intended for playing a single sound multiple times.
     */
    public abstract class Sound : GLib.Object
    {
        [CCode (notify = false)]
        public string uri {
            get {
                return this._uri;
            }
            set {
                var uri = value ?? "";

                if (this._uri != uri)
                {
                    this._uri = uri;
                    this.prepare ();
                    this.notify_property ("uri");
                }
                else if (this.error != null)
                {
                    this.prepare ();  // retry
                }
            }
        }

        public double volume { get; set; default = 1.0; }

        public GLib.Error? error { get; private set; }

        private string            _uri = "";
        protected Ft.SoundPlayer? player = null;

        private void prepare ()
        {
            var uri = build_absolute_uri (this._uri);

            try {
                // Validate file
                if (uri != "")
                {
                    var file = GLib.File.new_for_uri (uri);
                    var content_type = GLib.ContentType.guess (file.get_basename (), null, null);

                    if (!file.query_exists ()) {
                        throw new Ft.SoundError.NOT_FOUND (_("File not found"));
                    }

                    if (!is_mime_type (content_type, Ft.SoundPlayer.get_supported_mime_types ())) {
                        throw new Ft.SoundError.NOT_SUPPORTED (_("File type not supported"));
                    }
                }

                // Initialize player
                var player = uri != ""
                        ? this.player ?? new Ft.SoundPlayer ()
                        : null;

                if (this.player != player)
                {
                    if (this.player != null) {
                        this.destroy_player ();
                    }

                    this.player = player;

                    if (this.player != null) {
                        this.initialize_player ();
                    }
                }

                if (this.error != null) {
                    this.error = null;
                }

                if (player != null) {
                    player.uri = uri;
                }
            }
            catch (GLib.Error error)
            {
                GLib.warning ("Error while initializing sound player for uri=%s: %s",
                              uri,
                              error.message);

                if (this.player != null) {
                    this.destroy_player ();
                    this.player = null;
                }

                this.error = error;
            }
        }

        private void on_playback_error (GLib.Error error)
        {
            GLib.warning ("Playback error for uri=%s: %s", this.player.uri, error.message);
            this.error = error;
        }

        public bool can_play ()
        {
            return this.player != null;
        }

        public bool is_playing ()
        {
            return this.player != null && this.player.is_playing ();
        }

        public void play ()
        {
            if (this.player == null && this._uri != "") {
                this.prepare ();
            }

            if (this.player != null) {
                this.player.play ();
            }
        }

        public void stop ()
        {
            this.player?.stop ();
        }

        protected virtual void initialize_player ()
        {
            this.bind_property ("volume", this.player, "volume", GLib.BindingFlags.SYNC_CREATE);

            this.player.playback_error.connect (this.on_playback_error);
        }

        protected virtual void destroy_player ()
        {
            this.player.playback_error.disconnect (this.on_playback_error);
            this.player.stop ();
        }

        public virtual void destroy ()
        {
            if (this.player != null) {
                this.destroy_player ();
                this.player = null;
            }
        }
    }


    public class AlertSound : Ft.Sound
    {
        public string event_id { get; construct; }

        public AlertSound (string event_id)
        {
            GLib.Object (
                event_id: event_id
            );
        }
    }


    public class BackgroundSound : Ft.Sound
    {
        public bool loop { get; set; default = false; }

        protected override void initialize_player ()
        {
            base.initialize_player ();

            this.bind_property ("loop", this.player, "loop", GLib.BindingFlags.SYNC_CREATE);
        }

        public void fade_in (int64 duration)
        {
            this.player?.fade_in (duration);
        }

        public void fade_out (int64 duration)
        {
            this.player?.fade_out (duration);
        }
    }
}
