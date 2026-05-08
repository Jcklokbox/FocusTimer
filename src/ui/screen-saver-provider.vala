/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Ft
{
    private class DefaultScreenSaverProvider : Ft.Provider, Ft.ScreenSaverProvider
    {
        public bool active {
            get {
                return this._active;
            }
        }

        private bool             _active = false;
        private Gtk.Application? application = null;

        private void on_notify_screensaver_active (GLib.Object    obj,
                                                   GLib.ParamSpec pspec)
        {
            var active = this.application.screensaver_active;

            if (this._active != active) {
                this._active = active;
                this.notify_property ("active");
            }
        }

        public override async void initialize (GLib.Cancellable? cancellable) throws GLib.Error
        {
            this.available = true;
        }

        public override async void uninitialize () throws GLib.Error
        {
        }

        public override async void enable (GLib.Cancellable? cancellable) throws GLib.Error
        {
            this.application = (Gtk.Application) Ft.Application.get_default ();
            this.application.notify["screensaver-active"].connect (this.on_notify_screensaver_active);
        }

        public override async void disable () throws GLib.Error
        {
            if (this.application != null) {
                this.application.notify["screensaver-active"].disconnect (this.on_notify_screensaver_active);
                this.application = null;
            }
        }
    }
}
