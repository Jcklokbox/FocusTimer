/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Sni
{
    private inline GLib.Variant empty_vardict ()
    {
        return new GLib.Variant.array (new GLib.VariantType ("{sv}"), {});
    }


    private GLib.Variant serialize_pixmaps (Pixmap[] pixmaps)
    {
        GLib.Variant[] serialized_pixmaps = {};

        foreach (var pixmap in pixmaps) {
            serialized_pixmaps += pixmap.to_variant ();
        }

        return new GLib.Variant.array (new GLib.VariantType ("(iiay)"), serialized_pixmaps);
    }


    /**
     * Build response for `GetLayout` method.
     *
     * The result value is recursive - it contains same structure for menu item children.
     */
    private GLib.Variant serialize_layout (Sni.MenuItem           menu_item,
                                           Sni.MenuItemProperty[] properties,
                                           int                    max_depth = -1)
    {
        var serialized_properties = menu_item.serialize_properties (
                filter_properties (menu_item, properties));
        var serialized_children = new GLib.Variant[0];

        if (max_depth != 0)
        {
            var child_max_depth = max_depth > 0 ? max_depth - 1 : -1;
            menu_item.@foreach (
                (child) => {
                    serialized_children += new GLib.Variant.variant (
                        serialize_layout (child, properties, child_max_depth));
                });
        }

        return new GLib.Variant.tuple ({
            new GLib.Variant.int32 ((int32) menu_item.id),
            serialized_properties ?? empty_vardict (),
            new GLib.Variant.array (GLib.VariantType.VARIANT, serialized_children),
        });
    }


    /**
     * Filter-out properties with default values, unless the property has been modified.
     */
    private Sni.MenuItemProperty[] filter_properties (Sni.MenuItem           menu_item,
                                                      Sni.MenuItemProperty[] properties)
    {
        var filtered_properties = new Sni.MenuItemProperty[0];

        foreach (var property in properties)
        {
            if (!menu_item.has_modified_property (property) &&
                 menu_item.has_default_property (property))
            {
                continue;
            }

            filtered_properties += property;
        }

        return filtered_properties;
    }


    private static Sni.MenuItemProperty[] unpack_properties (uint properties_mask)
    {
        var properties = new Sni.MenuItemProperty[0];
        var index = 0U;

        while (properties_mask != 0U)
        {
            if ((properties_mask & 1U) != 0U) {
                properties += (Sni.MenuItemProperty) index;
            }

            properties_mask = properties_mask >> 1;
            index++;
        }

        return properties;
    }


    /**
     * A D-Bus service for exporting an tray icon.
     *
     * We try to keep things modern by not using pixmaps. Not all features are handled the same
     * way by various desktops.
     *
     * Note that unlike standard D-Bus services, the authors of the spec instead of using
     * `PropertiesChanged` signal invented custom signals (`New*`) for notifying about changes.
     * So, we don't emit `PropertiesChanged` as it's redundant in this case.
     *
     * https://www.freedesktop.org/wiki/Specifications/StatusNotifierItem/StatusNotifierItem/
     * https://api.kde.org/kstatusnotifieritem.html
     */
    [DBus (name = "org.kde.StatusNotifierItem")]
    private class StatusNotifierItemDBusService : GLib.Object
    {
        public string id {
            owned get {
                return Config.APPLICATION_ID;
            }
        }

        public string category {
            owned get {
                return "ApplicationStatus";
            }
        }

        public bool item_is_menu {
            get {
                return this._item_is_menu;
            }
        }

        public GLib.ObjectPath menu {
            owned get {
                return this._menu;
            }
        }

        public string title {
            owned get {
                return this._title;
            }
        }

        public string status {
            owned get {
                return this._status.to_string ();
            }
        }

        public string icon_theme_path {  // not in spec
            owned get {
                return this._icon_theme_path;
            }
        }

        public string icon_name {
            owned get {
                return this._icon_name;
            }
        }

        [DBus (signature = "a(iiay)")]
        public GLib.Variant icon_pixmap {
            owned get {
                return serialize_pixmaps ({});
            }
        }

        public string overlay_icon_name {
            owned get {
                return this._overlay_icon_name;
            }
        }

        [DBus (signature = "a(iiay)")]
        public GLib.Variant overlay_icon_pixmap {
            owned get {
                return serialize_pixmaps ({});
            }
        }

        public string attention_icon_name {
            owned get {
                return this.icon_name;
            }
        }

        [DBus (signature = "a(iiay)")]
        public GLib.Variant attention_icon_pixmap {
            owned get {
                return this.icon_pixmap;
            }
        }

        public string attention_movie_name {
            owned get {
                return "";
            }
        }

        [DBus (name = "ToolTip", signature = "(sa(iiay)ss)")]
        public GLib.Variant tooltip {
            owned get {
                return this._tooltip.to_variant ();
            }
        }

        public int32 window_id {
            get {
                return 0;
            }
        }

        private Sni.IndicatorStatus _status = Sni.IndicatorStatus.ACTIVE;
        private Sni.Tooltip         _tooltip;
        private GLib.ObjectPath     _menu;
        private bool                _item_is_menu;
        private string              _title;
        private string              _icon_theme_path;
        private string              _icon_name;
        private string              _overlay_icon_name;

        internal string activation_token;

        construct
        {
            this._item_is_menu = !Sni.Capabilities.have_activation ();
            this._title = GLib.Environment.get_application_name ();
            this._icon_name = @"$(Config.APPLICATION_ID)-symbolic";
            this._overlay_icon_name = "";
            this._tooltip = Sni.Tooltip ();
            this.activation_token = "";
        }

        public StatusNotifierItemDBusService (string menu_object_path,
                                              string icon_theme_path = "")
        {
            this._menu = new GLib.ObjectPath (menu_object_path);
            this._icon_theme_path = icon_theme_path;
        }

        public void context_menu (int32 x,
                                  int32 y) throws GLib.DBusError, GLib.IOError
        {
        }

        public void provide_xdg_activation_token (string token) throws GLib.DBusError, GLib.IOError
        {
            this.activation_token = token ?? "";
            this.received_activation_token (this.activation_token);
        }

        public void activate (int32 x,
                              int32 y) throws GLib.DBusError, GLib.IOError
        {
            this.activated (this.activation_token);
        }

        public void secondary_activate (int32 x,
                                        int32 y) throws GLib.DBusError, GLib.IOError
        {
            this.secondary_activated ();
        }

        public void scroll (int32  delta,
                            string orientation) throws GLib.DBusError, GLib.IOError
        {
            if (delta != 0 &&
                orientation != null && orientation.ascii_down () == "vertical")
            {
                this.scrolled (delta);
            }
        }

        public signal void new_title ();
        public signal void new_icon ();
        public signal void new_attention_icon ();
        public signal void new_status ();
        public signal void new_menu ();

        [DBus (name = "NewToolTip")]
        public signal void new_tooltip ();

        /*
         * Internal API
         */

        internal void set_title_internal (string value,
                                          bool   emit_signal = true)
        {
            if (this._title == value) {
                return;
            }

            this._title = value;

            if (emit_signal) {
                this.new_title ();
            }
        }

        internal void set_icon_name_internal (string value,
                                              bool   emit_signal = true)
        {
            if (this._icon_name == value) {
                return;
            }

            this._icon_name = value;

            if (emit_signal)
            {
                this.new_icon ();

                if (this._status == Sni.IndicatorStatus.NEEDS_ATTENTION) {
                    this.new_attention_icon ();
                }
            }
        }

        internal Sni.IndicatorStatus get_status_internal ()
        {
            return this._status;
        }

        internal void set_status_internal (Sni.IndicatorStatus value,
                                           bool                emit_signal = true)
        {
            if (this._status == value) {
                return;
            }

            this._status = value;

            if (emit_signal)
            {
                if (value == Sni.IndicatorStatus.NEEDS_ATTENTION) {
                    this.new_attention_icon ();
                }

                this.new_status ();
            }
        }

        internal Sni.Tooltip get_tooltip_internal ()
        {
            return this._tooltip;
        }

        internal void set_tooltip_internal (Sni.Tooltip value,
                                            bool        emit_signal = true)
        {
            if (this._tooltip.equals (value)) {
                return;
            }

            this._tooltip = value;

            if (emit_signal) {
                this.new_tooltip ();
            }
        }

        internal void emit_new_menu ()
        {
            this.new_menu ();
        }

        [DBus (visible = false)]
        public signal void received_activation_token (string token);

        [DBus (visible = false)]
        public signal void activated (string token);

        [DBus (visible = false)]
        public signal void secondary_activated ();

        [DBus (visible = false)]
        public signal void scrolled (int delta);
    }


    /**
     * A D-Bus service for exporting an indicator menu.
     *
     * Menu structure should be static.
     *
     * https://github.com/gnustep/libs-dbuskit/blob/master/Bundles/DBusMenu/com.canonical.dbusmenu.xml
     */
    [DBus (name = "com.canonical.dbusmenu")]
    private class DBusMenuService : GLib.Object
    {
        private const int32 ROOT_ID = 0;

        public uint32 version {
            get {
                return 4U;
            }
        }

        public string status {
            owned get {
                return "normal";
            }
        }

        public string[] icon_theme_path {
            owned get {
                return {this._icon_theme_path};
            }
        }

        public string text_direction {
            owned get {
                return Gtk.Widget.get_default_direction () == Gtk.TextDirection.RTL
                        ? "rtl"
                        : "ltr";
            }
        }

        private string                                    _icon_theme_path = null;
        private Sni.IndicatorActionGroup?                 action_group = null;
        private Sni.MenuItem?                             root = null;
        private uint32                                    revision = 1U;
        private GLib.HashTable<uint, weak Sni.MenuItem>   menu_items_by_id;
        private GLib.HashTable<string, weak Sni.MenuItem> menu_items_by_name;
        private uint                                      layout_updated_idle_id = 0;
        private uint                                      items_properties_updated_idle_id = 0;

        internal string activation_token = "";

        public DBusMenuService (Sni.MenuItem             root,
                                Sni.IndicatorActionGroup action_group,
                                string                   icon_theme_path)
        {
            this.root = root;
            this.action_group = action_group;
            this._icon_theme_path = icon_theme_path;

            this.menu_items_by_id = new GLib.HashTable<uint, weak Sni.MenuItem> (GLib.direct_hash, GLib.direct_equal);
            this.menu_items_by_name = new GLib.HashTable<string, weak Sni.MenuItem> (GLib.str_hash, GLib.str_equal);

            this.root.traverse (
                (menu_item) => {
                    this.menu_items_by_id.insert (menu_item.id, menu_item);

                    if (menu_item.name != "" && menu_item.name != null) {
                        this.menu_items_by_name.insert (menu_item.name, menu_item);
                    }

                    menu_item.child_added.connect (this.on_child_added);
                    menu_item.child_added.connect (this.on_child_removed);
                    menu_item.changed.connect (this.on_changed);
                });
        }

        private inline unowned Sni.MenuItem? lookup_by_id (int32 id)
        {
            return id >= 0
                    ? this.menu_items_by_id.lookup ((uint) id)
                    : null;
        }

        private inline unowned Sni.MenuItem? lookup_by_name (string name)
        {
            return this.menu_items_by_name.lookup (name);
        }

        internal unowned Sni.MenuItem? lookup_menu_item (string name)
        {
            return this.lookup_by_name (name);
        }

        internal void emit_layout_updated ()
        {
            if (this.root == null) {
                return;
            }

            if (this.layout_updated_idle_id != 0) {
                GLib.Source.remove (this.layout_updated_idle_id);
                this.layout_updated_idle_id = 0;
            }

            uint[] changed_ids = {};

            this.root.traverse (
                (menu_item) => {
                    if (menu_item.dirty_layout) {
                        changed_ids += menu_item.id;
                        menu_item.dirty_layout = false;
                    }
                });

            if (changed_ids.length > 0) {
                this.revision++;
                this.layout_updated (this.revision, (int32) this.root.id);  // TODO: find common ancestor
            }
        }

        private void queue_layout_updated ()
        {
            if (this.layout_updated_idle_id != 0) {
                return;
            }

            this.layout_updated_idle_id = GLib.Idle.add (
                () => {
                    this.layout_updated_idle_id = 0;

                    if (this.root != null) {
                        this.layout_updated (this.revision, (int32) this.root.id);  // TODO: try to pass parent_id of the changed submenu - not the rooot
                    }

                    return GLib.Source.REMOVE;
                });
        }

        private void queue_items_properties_updated ()
        {
            if (this.layout_updated_idle_id != 0) {
                return;
            }
        }

        private void emit_items_properties_updated ()
        {
            if (this.root == null) {
                return;
            }

            if (this.items_properties_updated_idle_id != 0) {
                GLib.Source.remove (this.items_properties_updated_idle_id);
                this.items_properties_updated_idle_id = 0;
            }

            var builder = new GLib.VariantBuilder (new GLib.VariantType ("a(ia{sv})"));
            var changed = false;

            this.root.traverse (
                (menu_item) => {
                    if (menu_item.dirty_properties != 0U) {
                        builder.add_value (
                            new GLib.Variant.tuple ({
                                new GLib.Variant.int32 ((int32) menu_item.id),
                                menu_item.serialize_properties (
                                    unpack_properties (menu_item.dirty_properties))
                            })
                        );
                        menu_item.dirty_properties = 0U;
                        changed = true;
                    }
                });

            if (changed) {
                this.items_properties_updated (
                        builder.end (),
                        new GLib.Variant.array (new GLib.VariantType ("(ias)"), {}));
            }
        }

        internal void emit_updates ()
        {
            this.emit_layout_updated ();
            this.emit_items_properties_updated ();
        }

        private void on_child_added (Sni.MenuItem menu_item,
                                     Sni.MenuItem child)
        {
            menu_item.mark_dirty_layout ();
            menu_item.mark_dirty_property (Sni.MenuItemProperty.CHILDREN_DISPLAY);

            this.queue_layout_updated ();

            child.child_added.connect (this.on_child_added);
            child.child_added.connect (this.on_child_removed);
        }

        private void on_child_removed (Sni.MenuItem menu_item,
                                       Sni.MenuItem child)
        {
            menu_item.mark_dirty_layout ();
            menu_item.mark_dirty_property (Sni.MenuItemProperty.CHILDREN_DISPLAY);

            this.queue_layout_updated ();

            child.child_added.disconnect (this.on_child_added);
            child.child_removed.disconnect (this.on_child_removed);
        }

        private void on_changed (Sni.MenuItem         menu_item,
                                 Sni.MenuItemProperty property)
        {
            menu_item.mark_dirty_property (property);

            this.queue_items_properties_updated ();
        }

        private void handle_event (int32        id,
                                   string       event_name,
                                   GLib.Variant data,
                                   uint32       timestamp)
                                   throws GLib.DBusError
        {
            if (event_name != "clicked") {
                return;
            }

            unowned var menu_item = this.lookup_by_id (id);
            if (menu_item == null) {
                throw new GLib.DBusError.INVALID_ARGS ("Unknown id");
            }

            this.action_group.activate_action_full (menu_item.action_name,
                                                    menu_item.action_target,
                                                    build_platform_data (this.activation_token));
        }

        /*
         * Public D-Bus API
         */

        public void get_layout (int32               parent_id,
                                int32               recursion_depth,
                                string[]            property_names,
                                out uint32          revision,
                                [DBus (signature = "(ia{sv}av)")]
                                out GLib.Variant    layout) throws GLib.DBusError, GLib.IOError
        {
            unowned var parent = this.lookup_by_id (parent_id);

            if (parent == null) {
                throw new GLib.DBusError.INVALID_ARGS ("Unknown parent id");
            }

            revision = this.revision;
            layout = serialize_layout (parent,
                                       Sni.MenuItemProperty.from_strv (property_names),
                                       recursion_depth);
        }

        [DBus (name = "GetProperty", signature = "v")]
        public GLib.Variant get_property_ (int32  id,
                                           string name)
                                           throws GLib.DBusError, GLib.IOError
        {
            unowned var menu_item = this.lookup_by_id (id);
            if (menu_item == null) {
                throw new GLib.DBusError.INVALID_ARGS ("Unknown menu item id");
            }

            var property = Sni.MenuItemProperty.from_string (name);
            var value = menu_item.serialize_property (property);

            if (value == null) {
                throw new GLib.DBusError.INVALID_ARGS ("Unknown property");
            }

            return new GLib.Variant.variant (value);
        }

        [DBus (signature = "a(ia{sv})")]
        public GLib.Variant get_group_properties (int32[]  ids,
                                                  string[] property_names)
                                                  throws GLib.DBusError, GLib.IOError
        {
            var properties = Sni.MenuItemProperty.from_strv (property_names);
            var builder = new GLib.VariantBuilder (new GLib.VariantType ("a(ia{sv})"));

            foreach (var id in ids)
            {
                var menu_item = this.lookup_by_id (id);
                if (menu_item == null) {
                    continue;
                }

                var data = menu_item.serialize_properties (
                        filter_properties (menu_item, properties));
                if (data == null) {
                    continue;
                }

                builder.add_value (
                    new GLib.Variant.tuple ({
                        new GLib.Variant.int32 ((int32) menu_item.id),
                        data
                    }));
            }

            return builder.end ();
        }

        public void event (int32        id,
                           string       event_id,
                           GLib.Variant data,
                           uint32       timestamp) throws GLib.DBusError, GLib.IOError
        {
            this.handle_event (id, event_id, data, timestamp);
        }

        public int32[] event_group ([DBus (signature = "a(isvu)")] GLib.Variant events)
                                    throws GLib.DBusError, GLib.IOError
        {
            int32        id;
            string       event_id;
            GLib.Variant data;
            uint32       timestamp;

            var n = events.n_children ();

            for (var index = 0; index < n; index++)
            {
                var event = events.get_child_value (index);
                event.get ("(isvu)", out id, out event_id, out data, out timestamp);

                this.handle_event (id, event_id, data, timestamp);
            }

            return {};
        }

        public bool about_to_show (int32 id) throws GLib.DBusError, GLib.IOError
        {
            unowned var menu_item = this.lookup_by_id (id);

            return menu_item != null
                    ? menu_item.needs_update ()
                    : false;
        }

        public void about_to_show_group (int32[]     ids,
                                         out int32[] updates_needed,
                                         out int32[] id_errors) throws GLib.DBusError, GLib.IOError
        {
            updates_needed = new int32[ids.length];
            id_errors      = new int32[ids.length];

            for (var index = 0; index < ids.length; index < index++)
            {
                unowned var menu_item = this.lookup_by_id (ids[index]);

                updates_needed[index] = (int32)(menu_item != null && menu_item.needs_update ());
                id_errors[index]      = (int32)(menu_item == null);
            }
        }

        /**
         * Triggered when there are property updates across many items.
         */
        public signal void items_properties_updated (
                [DBus (signature = "a(ia{sv})")] GLib.Variant updated_props,
                [DBus (signature = "a(ias)")] GLib.Variant    removed_props);

        /**
         * Triggered by app, notify client to update the menu.
         *
         * Passing current `revision` as the client may already have the latest update.
         */
        public signal void layout_updated (uint32 revision,
                                           int32  parent_id);

        /**
         * Triggered by app, requesting to open the menu.
         */
        public signal void item_activation_requested (int32  id,
                                                      uint32 timestamp);

        public override void dispose ()
        {
            if (this.layout_updated_idle_id != 0) {
                GLib.Source.remove (this.layout_updated_idle_id);
                this.layout_updated_idle_id = 0;
            }

            if (this.items_properties_updated_idle_id != 0) {
                GLib.Source.remove (this.items_properties_updated_idle_id);
                this.items_properties_updated_idle_id = 0;
            }

            this.menu_items_by_id = null;
            this.menu_items_by_name = null;

            base.dispose ();
        }
    }
}
