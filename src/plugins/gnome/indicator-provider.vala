/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Gnome
{
    /**
     * Provider for the indicator when the extension is enabled.
     *
     * Extension manages the indicator. Just prevent other implementations from getting enabled.
     */
    public class IndicatorProvider : Ft.Provider, Ft.IndicatorProvider
    {
        public bool visible {
            get {
                return this.shell_extension != null &&
                       this.shell_extension.enabled;
            }
        }

        private Gnome.ShellExtension? shell_extension = null;

        private void update_available ()
        {
            this.available = this.shell_extension != null &&
                             this.shell_extension.enabled;
        }

        private void on_notify_extension_enabled (GLib.Object    object,
                                                  GLib.ParamSpec pspec)
        {
            this.update_available ();

            this.notify_property ("visible");
        }

        protected override async void initialize (GLib.Cancellable? cancellable) throws GLib.Error
        {
            this.shell_extension = new Gnome.ShellExtension ();
            this.shell_extension.notify["enabled"].connect (this.on_notify_extension_enabled);

            this.update_available ();
        }

        protected override async void uninitialize () throws GLib.Error
        {
            if (this.shell_extension != null) {
                this.shell_extension.notify["enabled"].disconnect (this.on_notify_extension_enabled);
                this.shell_extension = null;

                this.update_available ();
            }
        }

        protected override async void enable (GLib.Cancellable? cancellable) throws GLib.Error
        {
            // Indicator is already enabled by the extension. Nothing to do.
        }

        protected override async void disable () throws GLib.Error
        {
        }
    }
}
