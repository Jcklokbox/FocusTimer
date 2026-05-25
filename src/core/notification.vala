/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

namespace Ft
{
    private struct NotificationButton
    {
        public string        label;
        public string        action;
        public GLib.Variant? target_value;
    }


    public enum NotificationPriority
    {
        LOW,
        NORMAL,
        HIGH,
        URGENT;

        public string to_string ()
        {
            switch (this)
            {
                case LOW:
                    return "low";

                case NORMAL:
                    return "normal";

                case HIGH:
                    return "high";

                case URGENT:
                    return "urgent";

                default:
                    assert_not_reached ();
            }
        }
    }


    public delegate void NotificationForeachButtonFunc (string        label,
                                                        string        action,
                                                        GLib.Variant? target_value);


    /**
     * `GLib.Notification` equivalent, but fully editable and with extra fields.
     */
    public class Notification
    {
        public string                       title;
        public string                       body;
        public string?                      category = null;
        public string?                      event_id = null;
        public GLib.Icon?                   icon = null;
        public bool                         is_transient = false;
        public bool                         suppress_sound = false;
        public Ft.NotificationPriority      priority = Ft.NotificationPriority.NORMAL;
        public string?                      default_action = null;
        public GLib.Variant?                default_target_value = null;
        public int                          expire_timeout = -1;

        private Ft.NotificationButton[]     buttons;

        public Notification (string title,
                             string body)
        {
            this.title = title;
            this.body = body;
            this.buttons = {};
        }

        ~Notification ()
        {
            this.category             = null;
            this.event_id             = null;
            this.icon                 = null;
            this.default_action       = null;
            this.default_target_value = null;
            this.buttons              = null;
        }

        public void set_default_action_and_target_value (string        action,
                                                         GLib.Variant? target_value)
        {
            this.default_action       = action;
            this.default_target_value = target_value;
        }

        public void set_default_action (string detailed_action)
        {
            string        action;
            GLib.Variant? target_value;

            try {
                GLib.Action.parse_detailed_name (detailed_action, out action, out target_value);

                this.set_default_action_and_target_value (action, target_value);
            }
            catch (GLib.Error error) {
                GLib.warning ("Failed to set notification default action: %s", error.message);
            }

        }

        public void add_button_with_target_value (string        label,
                                                  string        action,
                                                  GLib.Variant? target_value)
        {
            this.buttons += Ft.NotificationButton () {
                label         = label,
                action        = action,
                target_value  = target_value,
            };
        }

        public void add_button (string label,
                                string detailed_action)
        {
            string        action;
            GLib.Variant? target_value;

            try {
                GLib.Action.parse_detailed_name (detailed_action, out action, out target_value);

                this.add_button_with_target_value (label, action, target_value);
            }
            catch (GLib.Error error) {
                GLib.warning ("Failed to add notification button: %s", error.message);
            }
        }

        public void foreach_button (Ft.NotificationForeachButtonFunc func)
        {
            foreach (var button in this.buttons) {
                func (button.label, button.action, button.target_value);
            }
        }

        /**
         * Compare visible fields and tell whether notifications are roughly the same.
         */
        public bool is_similar (Ft.Notification other)
        {
            if (this.title != other.title) {
                return false;
            }

            if (this.body != other.body) {
                return false;
            }

            return true;
        }
    }
}
