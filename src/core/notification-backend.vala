/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

namespace Ft
{
    public interface NotificationBackendProvider : Ft.Provider
    {
        public abstract async void send_notification (string          id,
                                                      Ft.Notification notification);

        public abstract async void withdraw_notification (string id);
    }


    private class FallbackNotificationBackendProvider : Ft.Provider, Ft.NotificationBackendProvider
    {
        private GLib.Application? application = null;

        private static GLib.NotificationPriority transform_priority (Ft.NotificationPriority priority)
        {
            switch (priority)
            {
                case Ft.NotificationPriority.LOW:
                    return GLib.NotificationPriority.LOW;

                case Ft.NotificationPriority.NORMAL:
                    return GLib.NotificationPriority.NORMAL;

                case Ft.NotificationPriority.HIGH:
                    return GLib.NotificationPriority.HIGH;

                case Ft.NotificationPriority.URGENT:
                    return GLib.NotificationPriority.URGENT;

                default:
                    assert_not_reached ();
            }
        }

        public async void send_notification (string          id,
                                             Ft.Notification notification)
        {
            var glib_notification = new GLib.Notification (notification.title);
            glib_notification.set_body (notification.body);
            glib_notification.set_priority (transform_priority (notification.priority));

            if (notification.category != null) {
                glib_notification.set_category (notification.category);
            }

            if (notification.icon != null) {
                glib_notification.set_icon (notification.icon);
            }

            if (notification.default_action != null) {
                glib_notification.set_default_action_and_target_value (
                        notification.default_action,
                        notification.default_target_value);
            }

            notification.foreach_button (
                (label, action, target_value) => {
                    glib_notification.add_button_with_target_value (label, action, target_value);
                });

            this.application?.send_notification (id, glib_notification);
        }

        public async void withdraw_notification (string id)
        {
            this.application?.withdraw_notification (id);
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
            this.application = GLib.Application.get_default ();
        }

        public override async void disable () throws GLib.Error
        {
            this.application = null;
        }
    }


    [Compact]
    private class QueuedNotification
    {
        public string           id;
        public Ft.Notification? notification;
        public ulong            serial;

        public QueuedNotification (string           id,
                                   Ft.Notification? notification,
                                   ulong            serial)
        {
            this.id = id;
            this.notification = notification;
            this.serial = serial;
        }

        ~QueuedNotification ()
        {
            this.notification = null;
        }
    }


    public interface NotificationBackendInterface : GLib.Object
    {
        public abstract void send_notification (string          id,
                                                Ft.Notification notification);

        public abstract void withdraw_notification (string id);
    }


    /**
     * `Application.send_notification()` already supports multiple backends, which works fine on
     * GNOME, but not so much on other desktops - especially when using "portal" backend.
     * On top of it, we would like some lower-level access to suppress notification sounds and to
     * handle rate limits. That's why a custom backend is needed in our case.
     */
    [SingleInstance]
    public class NotificationBackend : Ft.ProvidedObject<Ft.NotificationBackendProvider>, Ft.NotificationBackendInterface
    {
        private GLib.Queue<QueuedNotification>  queue;
        private bool                            processing_queue = false;
        private ulong                           next_serial = 1U;

        construct
        {
            this.queue = new GLib.Queue<QueuedNotification> ();
        }

        private void process_queue ()
        {
            var provider = this.provider;
            if (provider == null || !provider.enabled || this.processing_queue) {
                return;
            }

            var item = this.queue.pop_head ();
            if (item != null)
            {
                this.processing_queue = true;

                if (item.notification != null) {
                    provider.send_notification.begin (
                        item.id,
                        item.notification,
                        (obj, res) => {
                            provider.send_notification.end (res);

                            this.processing_queue = false;
                            this.process_queue ();
                        });
                }
                else {
                    provider.withdraw_notification.begin (
                        item.id,
                        (obj, res) => {
                            provider.withdraw_notification.end (res);

                            this.processing_queue = false;
                            this.process_queue ();
                        });
                }
            }
        }

        private void remove_from_queue (string id)
        {
            unowned var link = this.queue.head;

            while (link != null)
            {
                if (link.data.id == id)
                {
                    unowned var next_link = link.next;
                    this.queue.delete_link (link);
                    link = next_link;
                }
                else {
                    link = link.next;
                }
            }
        }

        protected override void initialize ()
        {
        }

        protected override void setup_providers ()
        {
            this.providers.add (new Ft.FallbackNotificationBackendProvider (), Ft.Priority.LOW);
        }

        protected override void provider_enabled (Ft.NotificationBackendProvider provider)
        {
            this.process_queue ();
        }

        protected override void provider_disabled (Ft.NotificationBackendProvider provider)
        {
        }

        public void send_notification (string          id,
                                       Ft.Notification notification)
        {
            this.remove_from_queue (id);
            this.queue.push_tail (new QueuedNotification (id, notification, this.next_serial++));

            this.process_queue ();
        }

        public void withdraw_notification (string id)
        {
            this.remove_from_queue (id);
            this.queue.push_tail (new QueuedNotification (id, null, this.next_serial++));

            // Prioritise withdrawals over sending new notifications
            this.queue.sort (
                (a, b) => {
                    if (a.notification == null && b.notification != null) {
                        return -1;
                    }

                    if (a.notification != null && b.notification == null) {
                        return 1;
                    }

                    return a.serial < b.serial ? -1 : 1;
                });

            this.process_queue ();
        }

        public override void dispose ()
        {
            if (this.queue != null) {
                this.queue.clear ();
                this.queue = null;
            }

            base.dispose ();
        }
    }
}
