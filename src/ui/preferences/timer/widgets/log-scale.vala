/*
 * Copyright (c) 2013-2025 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

using GLib;


namespace Ft
{
    public class LogScale : Gtk.Scale
    {
        private const GLib.BindingFlags BINDING_FLAGS = GLib.BindingFlags.DEFAULT |
                                                        GLib.BindingFlags.SYNC_CREATE |
                                                        GLib.BindingFlags.BIDIRECTIONAL;

        public double value { get; private set; }

        public new Gtk.Adjustment adjustment {
            get {
                return this._adjustment;
            }
            set {
                if (this._adjustment != null && this.adjustment_value_changed_id != 0) {
                    this._adjustment.disconnect (this.adjustment_value_changed_id);
                    this.adjustment_value_changed_id = 0;
                }

                if (this.value_binding != null) {
                    this.value_binding.unbind ();
                    this.value_binding = null;
                }

                this._adjustment = value;

                if (this._adjustment != null) {
                    this.value_binding = this._adjustment.bind_property ("value",
                                                                         base.adjustment,
                                                                         "value",
                                                                         BINDING_FLAGS,
                                                                         this.transform_to,
                                                                         this.transform_from);
                    // Sync displayed value from the just-applied binding (SYNC_CREATE
                    // already ran transform_from, so _adjustment.value is rounded).
                    this.value = this._adjustment.value;

                    this.adjustment_value_changed_id =
                            this._adjustment.value_changed.connect (this.on_adjustment_value_changed);
                }
            }
        }

        private Gtk.Adjustment?       _adjustment;
        private unowned GLib.Binding? value_binding;
        private ulong                 adjustment_value_changed_id = 0;

        construct
        {
            base.adjustment = new Gtk.Adjustment (0.0, 0.0, 2.0, 0.0, 0.0, 0.0);
        }

        public LogScale ()
        {
            GLib.Object (
                orientation: Gtk.Orientation.HORIZONTAL,
                digits: -1,
                draw_value: false
            );
        }

        /**
         * Round seconds to 30s, 1m, 5m, 10m.
         *
         * Its intended for settings only to have a rounded number.
         */
        private double round_seconds (double seconds)
        {
            if (seconds < 60.0) {
                return 30.0 * Math.round (seconds / 30.0);
            }

            if (seconds < 1800.0) {
                return 60.0 * Math.round (seconds / 60.0);
            }

            if (seconds < 3600.0) {
                return 300.0 * Math.round (seconds / 300.0);
            }

            return 600.0 * Math.round (seconds / 600.0);
        }

        private double get_step_size (double seconds)
        {
            if (seconds < 60.0) {
                return 30.0;
            }

            if (seconds < 1800.0) {
                return 60.0;
            }

            if (seconds < 3600.0) {
                return 300.0;
            }

            return 600.0;
        }

        private inline double func (double x)
        {
            return Math.exp (x) - 1.0;
        }

        private inline double func_inv (double y)
        {
            return Math.log (y + 1.0);
        }

        /**
         * Convert inner adjustment to destination values (seconds).
         */
        private bool transform_from (GLib.Binding   binding,
                                     GLib.Value     source_value,
                                     ref GLib.Value target_value)
        {
            var seconds_lower = this._adjustment.lower;
            var seconds_upper = this._adjustment.upper;
            var base_upper    = base.adjustment.upper;
            var base_value    = source_value.get_double ();

            var t = this.func (base_value) / this.func (base_upper);
            var seconds = t * (seconds_upper - seconds_lower) + seconds_lower;

            target_value.set_double (this.round_seconds (seconds));

            return true;
        }

        /**
         * Convert outer adjustment (seconds) to inner adjustment.
         */
        private bool transform_to (GLib.Binding   binding,
                                   GLib.Value     source_value,
                                   ref GLib.Value target_value)
        {
            var seconds_lower = this._adjustment.lower;
            var seconds_upper = this._adjustment.upper;
            var base_upper    = base.adjustment.upper;
            var seconds       = source_value.get_double ();

            var t = (seconds - seconds_lower) / (seconds_upper - seconds_lower);
            var base_value = this.func_inv (t * this.func (base_upper));

            target_value.set_double (base_value);

            return true;
        }

        private void on_adjustment_value_changed ()
        {
            if (this._adjustment == null) {
                return;
            }

            var new_value = this._adjustment.value;

            if (this.value == new_value) {
                return;
            }

            this.value = new_value;
        }

        public void step_forward ()
        {
            if (this._adjustment == null) {
                return;
            }

            var new_value = this._adjustment.value;
            new_value += this.get_step_size (new_value + 1.0);

            this._adjustment.value = new_value.clamp (this._adjustment.lower, this._adjustment.upper);
        }

        public void step_backward ()
        {
            if (this._adjustment == null) {
                return;
            }

            var new_value = this._adjustment.value;
            new_value -= this.get_step_size (new_value - 1.0);

            this._adjustment.value = new_value.clamp (this._adjustment.lower, this._adjustment.upper);
        }

        public override void dispose ()
        {
            if (this._adjustment != null && this.adjustment_value_changed_id != 0) {
                this._adjustment.disconnect (this.adjustment_value_changed_id);
                this.adjustment_value_changed_id = 0;
            }

            if (this.value_binding != null) {
                this.value_binding.unbind ();
            }

            base.dispose ();

            this._adjustment = null;
        }
    }
}
