/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Sni
{
    public class IndicatorActionGroup : GLib.Object, GLib.ActionGroup, GLib.RemoteActionGroup
    {
        private GLib.ActionGroup?                    application_action_group = null;
        private GLib.ActionGroup?                    timer_action_group = null;
        private GLib.ActionGroup?                    session_manager_action_group = null;
        private GLib.HashTable<string, GLib.Action>? actions;

        construct
        {
            this.application_action_group = (GLib.ActionGroup) GLib.Application.get_default ();
            this.timer_action_group = new Ft.TimerActionGroup ();
            this.session_manager_action_group = new Ft.SessionManagerActionGroup ();

            this.actions = new GLib.HashTable<string, GLib.Action> (GLib.str_hash, GLib.str_equal);

            var quit_action = new GLib.SimpleAction ("quit", null);
            quit_action.activate.connect (this.activate_quit);
            this.add_action (quit_action);
        }

        private inline void split_name (string     action_name,
                                        out string prefix,
                                        out string name)
        {
            var action_name_parts = action_name.split (".", 2);

            if (action_name_parts.length < 2) {
                prefix = "indicator";
                name = action_name;
            }
            else {
                prefix = action_name_parts[0];
                name = action_name_parts[1];
            }
        }

        private unowned GLib.ActionGroup? lookup_group (string prefix)
        {
            switch (prefix)
            {
                case "indicator":
                    return this;

                case "app":
                    return this.application_action_group;

                case "timer":
                    return this.timer_action_group;

                case "session-manager":
                    return this.session_manager_action_group;

                default:
                    return null;
            }
        }

        /*
         * Action Group
         */

        public void activate_action (string        action_name,
                                     GLib.Variant? parameter)
        {
            string prefix;
            string action_name_;

            this.split_name (action_name, out prefix, out action_name_);

            unowned var action_group = this.lookup_group (prefix);

            if (action_group == this) {
                unowned var action = this.actions.lookup (action_name_);
                action?.activate (parameter);
            }
            else if (action_group != null) {
                action_group.activate_action (action_name_, parameter);
            }
        }

        public void change_action_state (string       action_name,
                                         GLib.Variant value)
        {
            string prefix;
            string action_name_;

            this.split_name (action_name, out prefix, out action_name_);

            unowned var action_group = this.lookup_group (prefix);

            if (action_group == this) {
                unowned var action = this.actions.lookup (action_name_);
                action?.change_state (value);
            }
            else if (action_group != null) {
                action_group.change_action_state (action_name_, value);
            }
        }

        /*
         * ActionMap
         */

        public void add_action (GLib.Action action)
        {
            string prefix;
            string action_name;

            this.split_name (action.name, out prefix, out action_name);

            unowned var action_group = this.lookup_group (prefix);

            if (action_group == this) {
                this.actions.insert (action_name, action);
            }
            else if (action_group is GLib.ActionMap) {
                action_group.add_action (action);
            }
            else {
                GLib.warning ("Unable to add action '%s'", action.name);
            }
        }

        public string[] list_actions ()
        {
            var action_names = new string[0];

            foreach (var action_name in this.actions.get_keys_as_array ()) {
                action_names += @"indicator.$(action_name)";
            }

            foreach (var action_name in this.application_action_group.list_actions ()) {
                action_names += @"app.$(action_name)";
            }

            foreach (var action_name in this.timer_action_group.list_actions ()) {
                action_names += @"timer.$(action_name)";
            }

            foreach (var action_name in this.session_manager_action_group.list_actions ()) {
                action_names += @"session-manager.$(action_name)";
            }

            return action_names;
        }

        /*
         * RemoteActionGroup
         */

        private static void activate_action_remote (string            action_name,
                                                    GLib.Variant?     parameter,
                                                    GLib.Variant      platform_data,
                                                    int               timeout = -1,
                                                    GLib.Cancellable? cancellable = null)
        {
            var application = GLib.Application.get_default ();
            var connection = application?.get_dbus_connection ();

            if (connection == null) {
                return;
            }

            var parameters = new GLib.VariantBuilder (new GLib.VariantType ("av"));
            if (parameter != null) {
                parameters.add_value (new GLib.Variant.variant (parameter));
            }

            connection.call.begin (
                    application.get_application_id (),
                    application.get_dbus_object_path (),
                    "org.freedesktop.Application",
                    "ActivateAction",
                    new GLib.Variant.tuple ({
                        new GLib.Variant.string (action_name),
                        parameters.end (),
                        platform_data,
                    }),
                    null,
                    GLib.DBusCallFlags.NONE,
                    timeout,
                    cancellable,
                    (obj, res) => {
                        try {
                            connection.call.end (res);
                        }
                        catch (GLib.Error error) {
                            GLib.warning ("Failed to activate action '%s': %s",
                                          action_name, error.message);
                        }
                    });
        }

        public void activate_action_full (string        action_name,
                                          GLib.Variant? parameter,
                                          GLib.Variant  platform_data)
        {
            var action_name_parts = action_name.split (".", 2);

            if (action_name_parts.length == 1) {
                activate_action_remote (action_name, parameter, platform_data);
                return;
            }

            if (action_name_parts[0] == "app") {
                activate_action_remote (action_name_parts[1], parameter, platform_data);
                return;
            }

            this.activate_action (action_name, parameter);
        }

        public void change_action_state_full (string       action_name,
                                              GLib.Variant value,
                                              GLib.Variant platform_data)
        {
            this.change_action_state (action_name, value);
        }

        /*
         * Indicator actions
         */

        private void activate_quit (GLib.SimpleAction action,
                                    GLib.Variant?     parameter)
        {
            // Delay, so that we return a reply to the D-Bus client.
            GLib.Idle.add (() => {
                this.activate_action ("app.quit", null);

                return GLib.Source.REMOVE;
            });
        }
    }
}
