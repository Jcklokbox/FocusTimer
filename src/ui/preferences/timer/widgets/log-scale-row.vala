/*
 * Copyright (c) 2023-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

namespace Ft
{
    // TODO: rename to DurationRow
    [GtkTemplate (ui = "/io/github/focustimerhq/FocusTimer/ui/preferences/timer/widgets/log-scale-row.ui")]
    public class LogScaleRow : Adw.ActionRow
    {
        public Gtk.Adjustment adjustment {
            get {
                return this._adjustment;
            }
            set {
                if (this._adjustment != null) {
                    this._adjustment.value_changed.disconnect (this.on_value_changed);
                }

                this._adjustment = value;

                this.value_changed ();
                this.update_value_label ();

                if (this._adjustment != null) {
                    this._adjustment.value_changed.connect (this.on_value_changed);
                }
            }
        }

        [GtkChild]
        private unowned Gtk.Label title_label;
        [GtkChild]
        private unowned Gtk.Label value_label;
        [GtkChild]
        private unowned Ft.LogScale scale;

        private Gtk.Adjustment _adjustment;
        private bool           pending_value_changed = false;

        construct
        {
            this.bind_property ("title", this.title_label, "label", GLib.BindingFlags.SYNC_CREATE);
            this.bind_property ("adjustment", this.scale, "adjustment", GLib.BindingFlags.SYNC_CREATE);

            var scroll_controller = new Gtk.EventControllerScroll (Gtk.EventControllerScrollFlags.VERTICAL);
            scroll_controller.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            scroll_controller.scroll.connect (this.on_scroll);
            this.add_controller (scroll_controller);

            var key_controller = new Gtk.EventControllerKey ();
            key_controller.key_pressed.connect (this.on_key_pressed);
            this.add_controller (key_controller);

            this.update_value_label ();
        }

        private void update_value_label ()
        {
            if (this._adjustment != null) {
                var seconds = (int) Math.round (this._adjustment.value).clamp (0, int.MAX);

                this.value_label.label = Ft.format_time (seconds);
            }
        }

        private void on_value_changed ()
        {
            this.update_value_label ();

            if (this.scale.has_css_class ("dragging")) {
                this.pending_value_changed = true;
            }
            else {
                this.value_changed ();
            }
        }

        private bool on_scroll (double dx,
                                double dy)
        {
            if (this._adjustment == null || dy == 0.0) {
                return false;
            }

            if (dy < 0.0) {
                this.scale.step_forward ();
            }
            else {
                this.scale.step_backward ();
            }

            return true;
        }

        private bool on_key_pressed (uint             keyval,
                                     uint             keycode,
                                     Gdk.ModifierType state)
        {
            if (this._adjustment == null) {
                return false;
            }

            switch (keyval)
            {
                case Gdk.Key.Page_Up:
                    this.scale.step_forward ();
                    return true;

                case Gdk.Key.Page_Down:
                    this.scale.step_backward ();
                    return true;

                default:
                    return false;
            }
        }

        [GtkCallback]
        private void on_notify_css_classes ()
        {
            var is_dragging = this.scale.has_css_class ("dragging");

            if (this.pending_value_changed && !is_dragging) {
                this.value_changed ();
            }
        }

        /**
         * Emitted when user stops dragging the slider unlike `notify["value"]` on the
         * `Gtk.Adjustment`.
         */
        public signal void value_changed ()
        {
            this.pending_value_changed = false;
        }

        public override void dispose ()
        {
            if (this._adjustment != null) {
                this._adjustment.value_changed.disconnect (this.on_value_changed);
                this._adjustment = null;
            }

            base.dispose ();
        }
    }
}
