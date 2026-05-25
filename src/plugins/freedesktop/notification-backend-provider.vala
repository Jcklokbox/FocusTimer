/*
 * Copyright (c) 2024-2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Freedesktop
{
    /**
     * Whether clicking the notification activates the app.
     */
    private bool have_default_action (string server_name)
    {
        switch (server_name)
        {
            case "Xfce Notify Daemon":
                return false;

            default:
                return true;
        }
    }


    /**
     * Some servers do not read icon name from the .desktop file.
     */
    private string get_application_icon (string server_name)
    {
        switch (server_name)
        {
            case "cinnamon":
            case "cosmic-notifications":
                return @"$(Config.APPLICATION_ID)-symbolic";

            case "Xfce Notify Daemon":
            case "lxqt-notificationd":
                return Config.APPLICATION_ID;

            default:
                return "";
        }
    }


    private Freedesktop.NotificationUrgency priority_to_urgency (Ft.NotificationPriority priority)
    {
        switch (priority)
        {
            case Ft.NotificationPriority.LOW:
                return Freedesktop.NotificationUrgency.LOW;

            case Ft.NotificationPriority.NORMAL:
            case Ft.NotificationPriority.HIGH:
                return Freedesktop.NotificationUrgency.NORMAL;

            case Ft.NotificationPriority.URGENT:
                return Freedesktop.NotificationUrgency.CRITICAL;

            default:
                assert_not_reached ();
        }
    }


    [Compact]
    private class NotificationInfo
    {
        public Ft.Notification  notification;
        public string           id;
        public uint32           external_id = 0U;

        public NotificationInfo (string          id,
                                 Ft.Notification notification)
        {
            this.id = id;
            this.notification = notification;
        }

        ~NotificationInfo ()
        {
            this.notification = null;
        }
    }


    public class NotificationBackendProvider : Ft.Provider, Ft.NotificationBackendProvider
    {
        private const int DEFAULT_EXPIRY = -1;
        private const int NO_EXPIRY = 0;

        private bool                          has_actions = false;
        private bool                          has_persistence;
        private bool                          has_default_action;
        private uint                          watcher_id = 0;
        private Freedesktop.Notifications?    proxy = null;
        private GLib.SList<NotificationInfo>? notifications = null;
        private GLib.Cancellable?             cancellable = null;
        private GLib.Application?             application;
        private string                        application_name;
        private string                        application_icon;

        construct
        {
            this.application = GLib.Application.get_default ();
            this.application_name = GLib.Environment.get_application_name ();
        }

        private void on_name_appeared (GLib.DBusConnection connection,
                                       string              name,
                                       string              name_owner)
        {
            this.available = true;
        }

        private void on_name_vanished (GLib.DBusConnection? connection,
                                       string               name)
        {
            this.available = false;
        }

        public override async void initialize (GLib.Cancellable? cancellable) throws GLib.Error
        {
            this.watcher_id = GLib.Bus.watch_name (GLib.BusType.SESSION,
                                                   "org.freedesktop.Notifications",
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
            this.cancellable = cancellable != null
                    ? cancellable
                    : new GLib.Cancellable ();

            try {
                string name;
                string vendor;
                string version;
                string spec_version;

                var proxy = yield GLib.Bus.get_proxy<Freedesktop.Notifications> (
                            GLib.BusType.SESSION,
                            "org.freedesktop.Notifications",
                            "/org/freedesktop/Notifications",
                            GLib.DBusProxyFlags.DO_NOT_AUTO_START,
                            this.cancellable);

                yield proxy.get_server_information (out name,
                                                    out vendor,
                                                    out version,
                                                    out spec_version);

                var capabilities_strv = yield proxy.get_capabilities ();
                // TODO: move it to about dialog, troubleshooting section
                GLib.debug ("Notification backend:\n  name: %s\n  vendor: %s\n  version: %s\n  spec_version: %s\n  capabilities: %s",
                            name,
                            vendor,
                            version,
                            spec_version,
                            string.joinv (", ",capabilities_strv));

                var capabilities = new GLib.GenericSet<string> (GLib.str_hash, GLib.str_equal);
                foreach (var capability in capabilities_strv) {
                    capabilities.add (capability);
                }

                this.has_actions = capabilities.contains ("actions");
                this.has_persistence = capabilities.contains ("persistence");
                this.has_default_action = have_default_action (name);
                this.application_icon = get_application_icon (name);

                this.notifications = new GLib.SList<NotificationInfo> ();

                this.proxy = proxy;
                this.proxy.action_invoked.connect (this.on_action_invoked);
                this.proxy.notification_closed.connect (this.on_notification_closed);
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while creating notifications proxy: %s", error.message);
                throw error;
            }
        }

        public override async void disable () throws GLib.Error
        {
            this.cancellable?.cancel ();

            unowned var link = this.notifications;

            while (link != null)
            {
                if (link.data.external_id != 0U) {
                    yield this.withdraw_notification_internal (link.data.external_id);
                }

                link = link.next;
            }

            if (this.proxy != null)
            {
                this.proxy.action_invoked.disconnect (this.on_action_invoked);
                this.proxy.notification_closed.disconnect (this.on_notification_closed);
                this.proxy = null;
            }

            this.notifications = null;
            this.cancellable = null;
        }

        private unowned NotificationInfo? lookup_by_id (string id)
        {
            unowned var link = this.notifications;

            while (link != null)
            {
                if (link.data.id == id) {
                    return link.data;
                }

                link = link.next;
            }

            return null;
        }

        private unowned NotificationInfo? lookup_by_external_id (uint32 external_id)
        {
            if (external_id == 0U) {
                return null;
            }

            unowned var link = this.notifications;

            while (link != null)
            {
                if (link.data.external_id == external_id) {
                    return link.data;
                }

                link = link.next;
            }

            return null;
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

        private bool activate_detailed_action (string detailed_action)
        {
            string        action_name;
            GLib.Variant? target_value;

            try {
                GLib.Action.parse_detailed_name (detailed_action,
                                                 out action_name,
                                                 out target_value);

                return this.activate_action (action_name, target_value);
            }
            catch (GLib.Error error) {
                return false;
            }
        }

        private void on_notification_closed (uint32 id,
                                             uint32 reason)
        {
            unowned var notification_info = this.lookup_by_external_id (id);
            if (notification_info == null) {
                return;
            }

            // HACK: Prevent server from putting the notification into history.
            //       It doesn't help if notification hasn't been shown, i.e. in Do Not Disturb mode.
            if (this.has_persistence &&
                reason == Freedesktop.NotificationDestroyedReason.EXPIRED &&
                notification_info.notification.is_transient)
            {
                this.withdraw_notification_internal.begin (notification_info.external_id);
            }

            this.notifications.remove (notification_info);
        }

        private void on_action_invoked (uint32 id,
                                        string action_key)
        {
            unowned var notification_info = this.lookup_by_external_id (id);
            unowned var notification = notification_info?.notification;

            if (notification == null) {
                return;
            }

            var notification_closed = action_key == "default"
                    ? this.activate_action (notification.default_action,
                                            notification.default_target_value)
                    : this.activate_detailed_action (action_key);
            if (notification_closed) {
                this.notifications.remove (notification_info);
            }
        }

        private async void withdraw_notification_internal (uint32 external_id)
        {
            if (external_id == 0U || this.proxy == null) {
                return;
            }

            try {
                yield this.proxy.close_notification (external_id);
            }
            catch (GLib.Error error) {
                GLib.warning ("Failed to withdraw notification [%s.%d]: %s",
                              error.domain.to_string (), error.code, error.message);
            }
        }

        private void remove_by_external_id (uint32 external_id)
        {
            unowned var link = this.notifications;

            while (link != null)
            {
                if (link.data.external_id == external_id) {
                    unowned var next_link = link.next;
                    this.notifications.remove_link (link);
                    link = next_link;
                }
                else {
                    link = link.next;
                }
            }
        }

        public async void send_notification (string          id,
                                             Ft.Notification notification)
                                             requires (this.proxy != null)
        {
            if (this.cancellable == null || this.cancellable.is_cancelled ()) {
                return;
            }

            unowned var existing_notification_info = this.lookup_by_id (id);
            if (existing_notification_info != null &&
                existing_notification_info.notification.is_similar (notification))
            {
                return;
            }

            var replace_id = existing_notification_info != null
                    ? existing_notification_info.external_id
                    : 0U;

            var actions = new string[0];
            if (notification.default_action != null && this.has_default_action) {
                actions += "default";
                actions += "";
            }

            if (this.has_actions) {
                notification.foreach_button (
                    (label, action, target_value) => {
                        actions += GLib.Action.print_detailed_name (action, target_value);
                        actions += label;
                    });
            }

            var hints = new GLib.HashTable<string, GLib.Variant> (GLib.str_hash, GLib.str_equal);
            hints.insert ("desktop-entry", new GLib.Variant.string (Config.APPLICATION_ID));
            hints.insert ("urgency", priority_to_urgency (notification.priority).to_variant ());

            if (notification.is_transient) {
                hints.insert ("transient", new GLib.Variant.boolean (true));
            }

            if (notification.suppress_sound) {
                hints.insert ("suppress-sound", new GLib.Variant.boolean (true));
            }

            if (notification.category != null) {
                hints.insert ("category", new GLib.Variant.string (notification.category));
            }

            if (notification.event_id != null) {
                hints.insert ("event-id", new GLib.Variant.string (notification.event_id));
            }

            var expire_timeout = notification.priority != Ft.NotificationPriority.URGENT
                    ? notification.expire_timeout
                    : NO_EXPIRY;

            var tmp_notification_info = new Freedesktop.NotificationInfo (id, notification);
            unowned var notification_info = tmp_notification_info;
            this.notifications.append ((owned) tmp_notification_info);

            if (existing_notification_info != null) {
                replace_id = existing_notification_info.external_id;
                this.notifications.remove (existing_notification_info);
            }

            try {
                var external_id = yield this.proxy.notify (
                        this.application_name,
                        replace_id,
                        this.application_icon,
                        notification.title,
                        notification.body ?? "",
                        actions,
                        hints,
                        expire_timeout,
                        this.cancellable);

                if (replace_id != 0 && replace_id != external_id) {
                    yield this.withdraw_notification_internal (replace_id);
                }

                if (this.notifications.index (notification_info) >= 0) {
                    notification_info.external_id = external_id;
                }
                else {
                    // Notification got withdrawn while making the call
                    yield this.withdraw_notification_internal (external_id);
                }
            }
            catch (GLib.Error error) {
                GLib.warning ("Failed to send notification [%s.%d]: %s",
                              error.domain.to_string (), error.code, error.message);

                // Couldn't replace the notification, at least invalidate the the old one.
                if (replace_id != 0U) {
                    this.remove_by_external_id (replace_id);
                    yield this.withdraw_notification_internal (replace_id);
                }
            }
        }

        public async void withdraw_notification (string id)
                                                 requires (this.proxy != null)
        {
            if (this.cancellable == null || this.cancellable.is_cancelled ()) {
                return;
            }

            unowned var notification_info = this.lookup_by_id (id);
            if (notification_info == null) {
                return;
            }

            var external_id = notification_info != null
                    ? notification_info.external_id
                    : 0U;
            if (external_id != 0U) {
                this.remove_by_external_id (external_id);
                yield this.withdraw_notification_internal (external_id);
            }
            else {
                this.notifications.remove (notification_info);
            }
        }

        public override void dispose ()
        {
            this.application = null;

            base.dispose ();
        }
    }
}
