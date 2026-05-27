/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Portal
{
    /**
     * Return whether notifications portal is "on par" with Freedesktop one.
     */
    private bool have_notifications_portal ()
    {
        switch (Ft.get_desktop_name ())
        {
            case "gnome":
                return !Ft.is_devel ();

            default:
                return false;
        }
    }


    public class NotificationBackendProvider : Ft.Provider, Ft.NotificationBackendProvider
    {
        public Ft.Priority priority {
            get {
                return Ft.Priority.HIGH;
            }
        }

        private uint                                        watcher_id = 0;
        private Portal.Notification?                        proxy = null;
        private GLib.HashTable<string, Ft.Notification>?    notifications = null;
        private GLib.Cancellable?                           cancellable = null;
        private GLib.Application?                           application;

        construct
        {
            this.application = GLib.Application.get_default ();
        }

        private bool activate_action (string?       action,
                                      GLib.Variant? parameter)
        {
            if (parameter != null && parameter.is_floating ()) {
                return false;
            }

            if (action != null && action.has_prefix ("app."))
            {
                var action_name = action.split (".", 2)[1];
                GLib.VariantType? parameter_type = null;

                var action_group = (GLib.ActionGroup) this.application;

                if (action_group.query_action (action_name, null, out parameter_type, null, null, null) &&
                    ((parameter_type == null && parameter == null) ||
                     (parameter_type != null && parameter != null && parameter.is_of_type (parameter_type))))
                {
                    action_group.activate_action (action_name, parameter);
                    return true;
                }
            }
            else if (action == null)
            {
                this.application.activate ();
                return true;
            }

            return false;
        }

        private void on_name_appeared (GLib.DBusConnection connection,
                                       string              name,
                                       string              name_owner)
        {
            if (has_dbus_interface (connection,
                                    name,
                                    "/org/freedesktop/portal/desktop",
                                    "org.freedesktop.portal.Notification"))
            {
                this.available = true;
            }
        }

        private void on_name_vanished (GLib.DBusConnection? connection,
                                       string               name)
        {
            this.available = false;
        }

        private void on_action_invoked (string         id,
                                        string         action,
                                        GLib.Variant[] parameter)
        {
            GLib.Variant? target_value = parameter.length >= 1 ? parameter[0] : null;

            this.activate_action (action, target_value);
        }

        public override async void initialize (GLib.Cancellable? cancellable) throws GLib.Error
        {
            if (!have_notifications_portal ()) {
                this.available = false;
                return;
            }

            this.watcher_id = GLib.Bus.watch_name (GLib.BusType.SESSION,
                                                   "org.freedesktop.portal.Desktop",
                                                   GLib.BusNameWatcherFlags.NONE,
                                                   this.on_name_appeared,
                                                   this.on_name_vanished);
        }

        public override async void uninitialize () throws GLib.Error
        {
            if (this.watcher_id != 0) {
                GLib.Bus.unwatch_name (this.watcher_id);
                this.watcher_id = 0;
            }
        }

        public override async void enable (GLib.Cancellable? cancellable) throws GLib.Error
        {
            if (this.proxy != null) {
                return;
            }

            this.cancellable = cancellable != null
                    ? cancellable
                    : new GLib.Cancellable ();
            this.notifications = new GLib.HashTable<string, Ft.Notification> (GLib.str_hash, GLib.str_equal);

            try {
                this.proxy = yield GLib.Bus.get_proxy<Portal.Notification> (
                        GLib.BusType.SESSION,
                        "org.freedesktop.portal.Desktop",
                        "/org/freedesktop/portal/desktop",
                        GLib.DBusProxyFlags.DO_NOT_AUTO_START,
                        this.cancellable);

                this.proxy.action_invoked.connect (this.on_action_invoked);
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while creating global shortcuts session: %s", error.message);
                throw error;
            }
        }

        public override async void disable () throws GLib.Error
        {
            this.cancellable?.cancel ();

            if (this.proxy != null) {
                this.proxy.action_invoked.disconnect (this.on_action_invoked);
                this.proxy = null;
            }

            this.notifications = null;
            this.cancellable = null;
        }

        public async void send_notification (string          id,
                                             Ft.Notification notification)
                                             requires (this.proxy != null)
        {
            if (this.cancellable == null || this.cancellable.is_cancelled ()) {
                return;
            }

            unowned var existing_notification = this.notifications.lookup (id);
            if (existing_notification != null &&
                existing_notification.is_similar (notification))
            {
                return;
            }

            var notification_properties = new GLib.HashTable<string, GLib.Variant> (GLib.str_hash, GLib.str_equal);
            notification_properties.insert ("title", new GLib.Variant.string (notification.title));
            notification_properties.insert ("body", new GLib.Variant.string (notification.body));
            notification_properties.insert ("priority", new GLib.Variant.string (notification.priority.to_string ()));  // TODO: define serialize_property

            if (notification.icon != null) {
                // TODO
            }

            if (notification.is_transient) {
                notification_properties.insert ("display-hint", new GLib.Variant.strv ({
                    "transient",
                }));
            }

            if (notification.suppress_sound) {
                notification_properties.insert ("sound", new GLib.Variant.string ("silent"));
            }

            if (notification.default_action != null) {
                notification_properties.insert (
                        "default-action",
                        new GLib.Variant.string (notification.default_action));
            }

            if (notification.default_target_value != null) {
                notification_properties.insert (
                        "default-action-target",
                        notification.default_target_value);
            }

            var buttons = new GLib.Variant[0];
            notification.foreach_button (
                (label, action, target_value) => {
                    var button = new GLib.VariantBuilder (GLib.VariantType.VARDICT);
                    button.add ("{sv}", "label", new GLib.Variant.string (label));
                    button.add ("{sv}", "action", new GLib.Variant.string (action));

                    if (target_value != null) {
                        button.add ("{sv}", "target", target_value);
                    }

                    buttons += button.end ();
                });

            if (buttons.length > 0) {
                notification_properties.insert (
                        "buttons",
                        new GLib.Variant.array (GLib.VariantType.VARDICT, buttons));
            }

            try {
                yield this.proxy.add_notification (
                        id,
                        notification_properties,
                        this.cancellable);
            }
            catch (GLib.Error error) {
                GLib.warning ("Failed to add notification [%s.%d]: %s",
                              error.domain.to_string (), error.code, error.message);
            }
        }

        public async void withdraw_notification (string id)
                                                 requires (this.proxy != null)
        {
            if (this.cancellable == null || this.cancellable.is_cancelled ()) {
                return;
            }

            this.notifications.remove (id);

            try {
                yield this.proxy.remove_notification (id);
            }
            catch (GLib.Error error) {
                GLib.warning ("Failed to remove notification [%s.%d]: %s",
                              error.domain.to_string (), error.code, error.message);
            }
        }

        public override void dispose ()
        {
            this.application = null;

            base.dispose ();
        }
    }
}
