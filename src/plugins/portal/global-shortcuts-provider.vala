/*
 * Copyright (c) 2025-2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using GLib;


namespace Portal
{
    private errordomain GlobalShortcutsError
    {
        REQUEST,
        CREATE_SESSION,
        BIND_SHORTCUTS,
        CONFIGURE_SHORTCUTS,
        LIST_SHORTCUTS
    }


    private GLib.Variant serialize_shortcut (Portal.Shortcut shortcut)
    {
        var properties = new GLib.VariantBuilder (GLib.VariantType.VARDICT);
        properties.add ("{sv}", "description", new GLib.Variant.string (shortcut.description));
        properties.add ("{sv}", "preferred_trigger", new GLib.Variant.string (shortcut.preferred_trigger));

        return new GLib.Variant.tuple ({
            new GLib.Variant.string (shortcut.id),
            properties.end (),
        });
    }


    private GLib.Variant serialize_shortcuts (Portal.Shortcut[] shortcuts)
    {
        GLib.Variant[] serialized_shortcuts = {};

        foreach (var shortcut in shortcuts) {
            serialized_shortcuts += serialize_shortcut (shortcut);
        }

        return new GLib.Variant.array (new GLib.VariantType ("(sa{sv})"), serialized_shortcuts);
    }


    private Portal.Shortcut[] deserialize_shortcuts (GLib.Variant shortcuts_variant)
    {
        var shortcuts = new Portal.Shortcut[0];
        var shortcuts_iterator = shortcuts_variant.iterator ();
        GLib.Variant? tuple_variant;

        while ((tuple_variant = shortcuts_iterator.next_value ()) != null)
        {
            var shortcut = Portal.Shortcut () {
                id                  = tuple_variant.get_child_value (0).get_string (),
                description         = "",
                preferred_trigger   = "",
                trigger_description = "",
            };
            var properties = tuple_variant.get_child_value (1);
            var properties_iterator = properties.iterator ();

            string key;
            GLib.Variant variant;

            while (properties_iterator.next ("{sv}", out key, out variant))
            {
                switch (key)
                {
                    case "description":
                        shortcut.description = variant.get_string ();
                        break;

                    case "preferred_trigger":
                        shortcut.preferred_trigger = variant.get_string ();
                        break;

                    case "trigger_description":
                        shortcut.trigger_description = variant.get_string ();
                        break;

                    default:
                        GLib.debug ("Unhandled shortcut property %s=%s", key, variant.print (true));
                        break;
                }
            }

            shortcuts += shortcut;
        }

        return shortcuts;
    }


    private bool is_kde ()
    {
        switch (Ft.get_desktop_name ())
        {
            case "kde":
            case "lxqt":
                return true;

            default:
                return false;
        }
    }


    /**
     * `GlobalShortcuts` API doesn't expose the accelerator_string value in a standardized way,
     * we need to extract it from text.
     */
    private string parse_trigger_description (string? trigger_description)
    {
        if (trigger_description != null &&
            trigger_description.length > 0)
        {
            var position_start = 0;
            var position_end = trigger_description.length;

            // If there are multiple accelerators, pick first
            var comma_position = trigger_description.index_of (", ");
            if (comma_position > 0) {
                position_end = comma_position;
            }

            // GNOME format
            var accelerator_position = trigger_description.index_of ("<");
            if (accelerator_position >= 0 || !is_kde ()) {
                position_start = int.max (position_start, accelerator_position);
                return trigger_description.slice (position_start, position_end);
            }

            // KDE format
            var accelerator_string = new GLib.StringBuilder ();

            foreach (var key in trigger_description.slice (position_start, position_end).split ("+"))
            {
                key = key.strip ();

                switch (key)
                {
                    case "Meta":
                    case "Super":
                        accelerator_string.append (@"<Super>");
                        break;

                    case "Ctrl":
                    case "Control":
                        accelerator_string.append (@"<Control>");
                        break;

                    case "Alt":
                    case "Shift":
                        accelerator_string.append (@"<$(key)>");
                        break;

                    case "PgUp":
                        accelerator_string.append ("Page_Up");
                        break;

                    case "PgDown":
                        accelerator_string.append ("Page_Down");
                        break;

                    default:
                        accelerator_string.append (key.length == 1 ? key.down () : key);
                        break;
                }
            }

            return accelerator_string.str;
        }

        return "";
    }


    private string to_pascal_case (string key_name)
    {
        var builder = new GLib.StringBuilder ();
        var uppercase_next = true;
        var index = 0;
        unichar chr;

        while (key_name.get_next_char (ref index, out chr))
        {
            if (chr == '_') {
                uppercase_next = true;
                continue;
            }

            builder.append_unichar (uppercase_next ? chr.toupper () : chr);
            uppercase_next = false;
        }

        return builder.str;
    }


    private string format_accelerator_kde (Ft.Accelerator accelerator)
    {
        string[] labels = {};

        if (Gdk.ModifierType.SUPER_MASK in accelerator.modifiers) {
            labels += "Meta";
        }

        if (Gdk.ModifierType.CONTROL_MASK in accelerator.modifiers) {
            labels += "Ctrl";
        }

        if (Gdk.ModifierType.ALT_MASK in accelerator.modifiers) {
            labels += "Alt";
        }

        if (Gdk.ModifierType.SHIFT_MASK in accelerator.modifiers) {
            labels += "Shift";
        }

        var chr = (unichar) Gdk.keyval_to_unicode (accelerator.keyval);

        if (chr != '\x00' && chr < '\x80' && chr.isgraph ())
        {
            labels += chr.toupper ().to_string ();
        }
        else
        {
            switch (accelerator.keyval)
            {
                case Gdk.Key.Page_Up:
                    labels += "PgUp";
                    break;

                case Gdk.Key.Page_Down:
                    labels += "PgDown";
                    break;

                default:
                    var keyval_name = Gdk.keyval_name (accelerator.keyval);

                    if (keyval_name != null) {
                        labels += to_pascal_case (keyval_name);
                    }

                    break;
            }
        }

        return string.joinv ("+", labels);
    }


    private string format_accelerator (string accelerator_string)
    {
        if (accelerator_string == "") {
            return "";
        }

        if (is_kde ()) {
            var accelerator = Ft.Accelerator.from_string (accelerator_string);

            return !accelerator.is_empty ()
                    ? format_accelerator_kde (accelerator)
                    : "";
        }
        else {
            return accelerator_string;
        }
    }


    public class GlobalShortcutsProvider : Ft.Provider, Ft.GlobalShortcutsProvider
    {
        private GLib.DBusConnection?            connection = null;
        private Portal.GlobalShortcuts?         proxy = null;
        private Portal.Shortcut[]               shortcuts = null;
        private GLib.Cancellable?               cancellable = null;
        private GLib.ObjectPath?                session_handle = null;
        private GLib.HashTable<string, string>? accelerators = null;
        private uint                            dbus_watcher_id = 0U;
        private uint                            bind_shortcuts_idle_id = 0U;
        private bool                            is_configured = false;
        private bool                            bound_shortcuts = false;
        private ulong                           shortcuts_changed_id = 0;

        private void mark_as_configured ()
        {
            if (!this.is_configured)
            {
                var settings = Ft.get_settings ();
                settings.set_boolean ("global-shortcuts-configured", true);

                this.is_configured = true;
            }
        }

        private void update_accelerators (GLib.Variant shortcuts)
        {
            var changed_ids      = new GLib.GenericSet<string> (GLib.str_hash, GLib.str_equal);
            var new_accelerators = new GLib.HashTable<string, string> (GLib.str_hash, GLib.str_equal);
            var is_initialized   = this.accelerators != null;

            foreach (var shortcut in this.shortcuts)
            {
                if (this.accelerators != null &&
                    this.accelerators.contains (shortcut.id) &&
                    this.accelerators.lookup (shortcut.id) != "")
                {
                    changed_ids.add (shortcut.id);
                }

                new_accelerators.insert (shortcut.id, "");
            }

            foreach (var shortcut in deserialize_shortcuts (shortcuts))
            {
                var existing_accelerator = this.accelerators != null && this.accelerators.contains (shortcut.id)
                        ? this.accelerators.lookup (shortcut.id)
                        : "";
                var accelerator = parse_trigger_description (shortcut.trigger_description);

                if (accelerator == existing_accelerator) {
                    changed_ids.remove (shortcut.id);
                }
                else if (accelerator != "") {
                    changed_ids.add (shortcut.id);
                }

                new_accelerators.insert (shortcut.id, accelerator);
            }

            this.accelerators = new_accelerators;

            if (is_initialized) {
                changed_ids.@foreach (
                    (shortcut_id) => {
                        this.accelerator_changed (shortcut_id);
                    });
            }
        }

        /**
         * GlobalShortcuts API doesn't standardize the format of the shortcuts.
         *
         * App uses Gdk/GNOME format. We may need to convert it to local format.
         */
        private Portal.Shortcut[] format_shortcuts (Portal.Shortcut[] shortcuts)
        {
            Portal.Shortcut[] result = {};

            foreach (unowned var shortcut in shortcuts)
            {
                result += Portal.Shortcut () {
                    id                  = shortcut.id,
                    description         = shortcut.description,
                    preferred_trigger   = format_accelerator (shortcut.preferred_trigger),
                    trigger_description = shortcut.trigger_description,
                };
            }

            return result;
        }

        private Portal.Shortcut create_extra_shortcut ()
        {
            var timestamp = Ft.Timestamp.to_seconds_uint32 (Ft.Timestamp.from_now ());

            return Portal.Shortcut () {
                id                  = @"unused-$(timestamp)",
                description         = _("Unused"),
                preferred_trigger   = "",
                trigger_description = "",
            };
        }

        private int find_shortcut (string name)
        {
            for (var index = 0; index < this.shortcuts.length; index++)
            {
                if (this.shortcuts[index].id == name) {
                    return index;
                }
            }

            return -1;
        }

        private async void create_session () throws GlobalShortcutsError
        {
            var timestamp = Ft.Timestamp.to_seconds_uint32 (Ft.Timestamp.from_now ());

            try {
                var handle_token = yield Portal.create_request (
                    this.connection,
                    (response, results) => {
                        var session_handle_variant = results.lookup_value ("session_handle", null);

                        if (session_handle_variant != null) {
                            this.session_handle = new GLib.ObjectPath (
                                    session_handle_variant.get_string ());
                            this.bound_shortcuts = false;
                        }

                        this.create_session.callback ();
                    });

                if (this.proxy == null) {
                    Portal.destroy_request (handle_token);
                    throw new GlobalShortcutsError.CREATE_SESSION ("Provider disabled during request");
                }

                var options = new GLib.VariantDict ();
                options.insert_value ("handle_token",
                                      new GLib.Variant.string (handle_token));
                options.insert_value ("session_handle_token",
                                      new GLib.Variant.string (@"focustimer_$(timestamp)"));

                yield this.proxy.create_session (options.end ());

                yield;  // wait for response
            }
            catch (GLib.Error error) {
                throw new GlobalShortcutsError.CREATE_SESSION (error.message);
            }

            if (this.session_handle == null) {
                throw new GlobalShortcutsError.CREATE_SESSION ("No session_handle in response");
            }
        }

        /**
         * Bind (register) shortcuts
         *
         * It needs to be called once per session for the shortcuts to work, even if they have been
         * registered before.
         *
         * Binding shortcuts may show a dialog. Initially, we delay it until `open_edit_dialog()`
         * is used. Once `mark_as_configured()` is called, we may use `bind_shortcuts` at app
         * startup and enjoy the shortcuts without seeing the dialog. It will still show up when
         * new shortcuts are introduced.
         */
        private async void bind_shortcuts () throws GlobalShortcutsError
        {
            string handle_token;
            GLib.Variant? shortcuts_variant = null;

            if (this.shortcuts.length == 0) {
                return;
            }

            if (this.bind_shortcuts_idle_id != 0) {
                GLib.Source.remove (this.bind_shortcuts_idle_id);
                this.bind_shortcuts_idle_id = 0;
            }

            // We can only bind shortcuts once per session
            if (this.session_handle == null || this.bound_shortcuts) {
                yield this.create_session ();
            }

            try {
                handle_token = yield Portal.create_request (
                    this.connection,
                    (response, results) => {
                        shortcuts_variant = results.lookup_value ("shortcuts", null);

                        this.bind_shortcuts.callback ();
                    });
            }
            catch (GLib.Error error) {
                throw new GlobalShortcutsError.REQUEST (error.message);
            }

            // `ShortcutsChanged` signal is redundant with the response.
            //  Prefer `BindShortcuts` response as technically nothing has changed.
            GLib.SignalHandler.block (this.proxy, this.shortcuts_changed_id);

            try {
                var options = new GLib.VariantDict ();
                options.insert_value ("handle_token", new GLib.Variant.string (handle_token));

                var shortcuts = this.format_shortcuts (this.shortcuts);

                yield this.proxy.bind_shortcuts (this.session_handle,
                                                 serialize_shortcuts (shortcuts),
                                                 "",
                                                 options.end ());
                this.bound_shortcuts = true;

                yield;  // wait for response

                this.mark_as_configured ();

                if (shortcuts_variant != null) {
                    this.update_accelerators (shortcuts_variant);
                }
            }
            catch (GLib.Error error) {
                throw new GlobalShortcutsError.BIND_SHORTCUTS (error.message);
            }
            finally {
                GLib.SignalHandler.unblock (this.proxy, this.shortcuts_changed_id);
            }
        }

        private void schedule_bind_shortcuts ()
        {
            if (this.bind_shortcuts_idle_id != 0) {
                return;
            }

            this.bind_shortcuts_idle_id = GLib.Idle.add (
                () => {
                    this.bind_shortcuts_idle_id = 0;

                    this.bind_shortcuts.begin (
                        (obj, res) => {
                            try {
                                this.bind_shortcuts.end (res);
                            }
                            catch (GLib.Error error) {
                                GLib.warning ("Error while binding shortcuts: %s", error.message);
                            }
                        });

                    return GLib.Source.REMOVE;
                });
            GLib.Source.set_name_by_id (this.bind_shortcuts_idle_id,
                                        "Portal.GlobalShortcutsProvider.bind_shortcuts");
        }

        private void on_name_appeared (GLib.DBusConnection connection,
                                       string              name,
                                       string              name_owner)
        {
            if (has_dbus_interface (connection,
                                    name,
                                    "/org/freedesktop/portal/desktop",
                                    "org.freedesktop.portal.GlobalShortcuts"))
            {
                this.available = true;
                this.connection = connection;
            }
        }

        private void on_name_vanished (GLib.DBusConnection? connection,
                                       string               name)
        {
            this.available = false;
            this.connection = null;
        }

        private void on_activated (GLib.ObjectPath session_handle,
                                   string          shortcut_id,
                                   uint64          timestamp,
                                   GLib.Variant    options)
        {
            this.shortcut_activated (shortcut_id);
        }

        /**
         * `ShortcutsChanged` handler
         *
         * `shortcuts` is the list of currently active shortcuts.
         */
        private void on_shortcuts_changed (GLib.ObjectPath session_handle,
                                           GLib.Variant    shortcuts)
        {
            this.update_accelerators (shortcuts);
        }

        public void add_shortcut (string name,
                                  string description,
                                  string default_accelerator = "")
                                  requires (this.session_handle != null)
        {
            var shortcut = Portal.Shortcut () {
                id                = name,
                description       = description,
                preferred_trigger = default_accelerator,
            };
            var index = this.find_shortcut (shortcut.id);

            if (index >= 0) {
                this.shortcuts[index] = shortcut;
            }
            else {
                this.shortcuts += shortcut;
            }

            if (this.is_configured) {
                this.schedule_bind_shortcuts ();
            }
        }

        public string lookup_accelerator (string name)
        {
            return this.accelerators != null
                    ? this.accelerators.lookup (name) ?? ""
                    : "";
        }

        public async void open_edit_dialog (string window_identifier) throws GLib.Error
        {
            string handle_token;

            if (this.proxy == null || this.shortcuts.length == 0) {
                return;
            }

            if (this.bind_shortcuts_idle_id != 0) {
                GLib.Source.remove (this.bind_shortcuts_idle_id);
                this.bind_shortcuts_idle_id = 0;
            }

            try {
                handle_token = yield Portal.create_request (
                    this.connection,
                    (response, results) => {
                        this.open_edit_dialog.callback ();
                    });
            }
            catch (GLib.Error error) {
                throw new GlobalShortcutsError.REQUEST (error.message);
            }

            var options = new GLib.VariantDict ();
            options.insert_value ("handle_token", new GLib.Variant.string (handle_token));
            var options_variant = options.end ();

            var has_configure_shortcuts = (
                    this.proxy.version >= 2 &&
                    has_dbus_method ((GLib.DBusProxy) this.proxy, "ConfigureShortcuts"));

            if (has_configure_shortcuts && this.is_configured)
            {
                if (this.session_handle == null) {
                    yield this.create_session ();
                }

                if (!this.bound_shortcuts) {
                    yield this.bind_shortcuts ();
                }

                try {
                    yield this.proxy.configure_shortcuts (this.session_handle,
                                                          window_identifier,
                                                          options_variant);
                }
                catch (GLib.Error error) {
                    yield new GlobalShortcutsError.CONFIGURE_SHORTCUTS (error.message);
                }
            }
            else {
                // `BindShortcuts` may be called once per session.
                if (this.session_handle == null || this.bound_shortcuts) {
                    yield this.create_session ();
                }

                try {
                    var shortcuts = this.format_shortcuts (this.shortcuts);

                    // HACK: Force the edit dialog to open (protocol version=1)
                    if (!has_configure_shortcuts) {
                        shortcuts += this.create_extra_shortcut ();
                    }

                    yield this.proxy.bind_shortcuts (this.session_handle,
                                                     serialize_shortcuts (shortcuts),
                                                     window_identifier,
                                                     options_variant);
                    this.bound_shortcuts = true;

                    this.mark_as_configured ();
                }
                catch (GLib.Error error) {
                    yield new GlobalShortcutsError.BIND_SHORTCUTS (error.message);
                }
            }

            yield;  // wait for response

            // Accelerators are updated through `ShortcutsChanged` signal
        }

        public override async void initialize (GLib.Cancellable? cancellable) throws GLib.Error
        {
            this.shortcuts = {};

            if (this.dbus_watcher_id == 0) {
                this.dbus_watcher_id = GLib.Bus.watch_name (GLib.BusType.SESSION,
                                                            "org.freedesktop.portal.Desktop",
                                                            GLib.BusNameWatcherFlags.NONE,
                                                            this.on_name_appeared,
                                                            this.on_name_vanished);
            }
        }

        public override async void enable (GLib.Cancellable? cancellable) throws GLib.Error
        {
            if (this.proxy != null &&
                this.cancellable != null && !this.cancellable.is_cancelled ())
            {
                return;
            }

            this.cancellable = cancellable != null
                    ? cancellable
                    : new GLib.Cancellable ();

            // We can't check if keyboard shortcuts are initialized using D-Bus API. Our best guess
            // is storing the state, which is not 100% correct.
            this.is_configured = Ft.get_settings ().get_boolean ("global-shortcuts-configured");

            try {
                this.proxy = yield GLib.Bus.get_proxy<Portal.GlobalShortcuts>
                                    (GLib.BusType.SESSION,
                                     "org.freedesktop.portal.Desktop",
                                     "/org/freedesktop/portal/desktop",
                                     GLib.DBusProxyFlags.NONE,
                                     this.cancellable);
                this.proxy.activated.connect (this.on_activated);
                this.shortcuts_changed_id = this.proxy.shortcuts_changed.connect (
                        this.on_shortcuts_changed);

                GLib.info ("GlobalShortcuts version=%u is_configured=%s",
                           this.proxy.version,
                           this.is_configured.to_string ());

                yield this.create_session ();

                if (this.is_configured) {
                    yield this.bind_shortcuts ();
                }
            }
            catch (GLib.Error error) {
                GLib.warning ("Error while creating global shortcuts session: %s",
                              error.message);
                throw error;
            }
        }

        public override async void disable () throws GLib.Error
        {
            if (this.cancellable != null) {
                this.cancellable.cancel ();
            }

            if (this.bind_shortcuts_idle_id != 0) {
                GLib.Source.remove (this.bind_shortcuts_idle_id);
                this.bind_shortcuts_idle_id = 0;
            }

            if (this.proxy != null) {
                this.proxy.activated.disconnect (this.on_activated);
                this.proxy.shortcuts_changed.disconnect (this.on_shortcuts_changed);
                this.proxy = null;
            }

            this.session_handle = null;
        }

        public override async void uninitialize () throws GLib.Error
        {
            if (this.dbus_watcher_id != 0) {
                GLib.Bus.unwatch_name (this.dbus_watcher_id);
                this.dbus_watcher_id = 0;
            }

            this.cancellable = null;
            this.shortcuts = null;
            this.accelerators = null;
        }
    }
}
