/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Sni
{
    public sealed class MenuItem : GLib.Object
    {
        public uint             id { get; construct; }
        public string           name { get; construct; }
        public string           action_name { get; set; default = ""; }
        public GLib.Variant?    action_target { get; set; }

        [CCode (notify = false)]
        public Sni.MenuItemType item_type {
            get {
                return this._item_type;
            }
            construct {
                this._item_type = value;
            }
        }

        [CCode (notify = false)]
        public string icon_name {
            get {
                return this._icon_name;
            }
            set {
                if (this._icon_name != value) {
                    this._icon_name = value;
                    this.changed (Sni.MenuItemProperty.ICON_NAME);
                }
            }
        }

        [CCode (notify = false)]
        public string label {
            get {
                return this._label;
            }
            set {
                if (this._label != value) {
                    this._label = value;
                    this.changed (Sni.MenuItemProperty.LABEL);
                }
            }
        }

        [CCode (notify = false)]
        public Sni.MenuToggleType toggle_type {
            get {
                return this._toggle_type;
            }
            set {
                if (this._toggle_type != value) {
                    this._toggle_type = value;
                    this.changed (Sni.MenuItemProperty.TOGGLE_TYPE);
                    this.changed (Sni.MenuItemProperty.TOGGLE_STATE);
                }
            }
        }

        [CCode (notify = false)]
        public bool toggle_state {
            get {
                return this._toggle_state;
            }
            set {
                if (this._toggle_state != value) {
                    this._toggle_state = value;
                    this.changed (Sni.MenuItemProperty.TOGGLE_STATE);
                }
            }
        }

        [CCode (notify = false)]
        public bool enabled {
            get {
                return this._enabled;
            }
            set {
                if (this._enabled != value) {
                    this._enabled = value;
                    this.changed (Sni.MenuItemProperty.ENABLED);
                }
            }
        }

        [CCode (notify = false)]
        public bool visible {
            get {
                return this._visible;
            }
            set {
                if (this._visible != value) {
                    this._visible = value;
                    this.changed (Sni.MenuItemProperty.VISIBLE);
                }
            }
        }

        private static uint next_id = 1U;

        private Sni.MenuItemType        _item_type = Sni.MenuItemType.STANDARD;
        private string                  _icon_name = "";
        private string                  _label = "";
        private Sni.MenuToggleType      _toggle_type = Sni.MenuToggleType.NONE;
        private bool                    _toggle_state = false;
        private bool                    _enabled = true;
        private bool                    _visible = true;
        private weak Sni.MenuItem?      parent = null;
        private GLib.List<Sni.MenuItem> children;

        internal bool dirty_layout = false;
        internal uint dirty_properties = 0U;
        internal uint modified_properties = 0U;

        public MenuItem (string        name,
                         string        label,
                         string        icon_name,
                         string        action_name,
                         GLib.Variant? action_target = null)
        {
            var id = next_id;
            next_id++;

            GLib.Object (
                id: id,
                name: name,
                item_type: Sni.MenuItemType.STANDARD,
                label: label,
                icon_name: icon_name,
                action_name: action_name,
                action_target: action_target
            );
        }

        public MenuItem.root ()
        {
            GLib.Object (
                id: 0U,
                name: "",
                item_type: Sni.MenuItemType.STANDARD
            );
        }

        public MenuItem.separator (string name = "")
        {
            var id = next_id;
            next_id++;

            GLib.Object (
                id: id,
                name: name,
                item_type: Sni.MenuItemType.SEPARATOR
            );
        }

        public void append (Sni.MenuItem child)
                            requires (child.parent == null)
        {
            child.parent = this;

            this.children.append (child);
            this.child_added (child);
        }

        public void @foreach (GLib.Func<MenuItem> func)
        {
            this.children.@foreach (func);
        }

        public void traverse (GLib.Func<Sni.MenuItem> func)
        {
            func (this);

            this.children.@foreach (
                (child) => {
                    child.traverse (func);
                });
        }

        public bool has_children ()
        {
            return this.children != null;
        }

        public bool needs_update ()
        {
            // XXX: check children if they need update?

            return this.dirty_layout || this.dirty_properties != 0U;
        }

        internal bool has_default_property (Sni.MenuItemProperty property)
        {
            switch (property)
            {
                case Sni.MenuItemProperty.TYPE:
                    return this._item_type == Sni.MenuItemType.STANDARD;

                case Sni.MenuItemProperty.LABEL:
                    return this._label == "";

                case Sni.MenuItemProperty.ENABLED:
                    return this._enabled;

                case Sni.MenuItemProperty.VISIBLE:
                    return this._visible;

                case Sni.MenuItemProperty.ICON_NAME:
                    return this._icon_name == "";

                case Sni.MenuItemProperty.TOGGLE_TYPE:
                case Sni.MenuItemProperty.TOGGLE_STATE:
                    return this._toggle_type == Sni.MenuToggleType.NONE;

                case Sni.MenuItemProperty.CHILDREN_DISPLAY:
                    return !this.has_children ();

                case Sni.MenuItemProperty.ICON_DATA:
                    return true;

                case Sni.MenuItemProperty.SHORTCUT:
                    return true;

                case Sni.MenuItemProperty.INVALID:
                    return true;

                default:
                    assert_not_reached ();
            }
        }

        internal bool has_modified_property (Sni.MenuItemProperty property)
        {
            return (this.modified_properties & (1 << (uint) property)) != 0;
        }

        public GLib.Variant? serialize_property (Sni.MenuItemProperty property)
        {
            switch (property)
            {
                case Sni.MenuItemProperty.TYPE:
                    return new GLib.Variant.string (this._item_type.to_string ());

                case Sni.MenuItemProperty.LABEL:
                    return new GLib.Variant.string (this._label);

                case Sni.MenuItemProperty.ENABLED:
                    return new GLib.Variant.boolean (this._enabled);

                case Sni.MenuItemProperty.VISIBLE:
                    return new GLib.Variant.boolean (this._visible);

                case Sni.MenuItemProperty.ICON_NAME:
                    return new GLib.Variant.string (this._icon_name);

                case Sni.MenuItemProperty.TOGGLE_TYPE:
                    return new GLib.Variant.string (this._toggle_type.to_string ());

                case Sni.MenuItemProperty.TOGGLE_STATE:
                    return new GLib.Variant.int32 (this._toggle_type != Sni.MenuToggleType.NONE
                            ? (int32) this._toggle_state
                            : -1);

                case Sni.MenuItemProperty.CHILDREN_DISPLAY:
                    return new GLib.Variant.string (this.has_children () ? "submenu" : "");

                case Sni.MenuItemProperty.ICON_DATA:  // unused
                    return null;

                case Sni.MenuItemProperty.SHORTCUT:  // unused
                    return null;

                case Sni.MenuItemProperty.INVALID:
                    return null;

                default:
                    assert_not_reached ();
            }
        }

        public GLib.Variant? serialize_properties (Sni.MenuItemProperty[] properties)
        {
            var builder = new GLib.VariantBuilder (GLib.VariantType.VARDICT);

            foreach (var property in properties)
            {
                var value = this.serialize_property (property);
                if (value != null) {
                    builder.add ("{sv}", property.to_string (), value);
                }
            }

            return builder.end ();
        }

        internal void mark_dirty_layout ()
        {
            this.dirty_layout = true;
        }

        internal void mark_dirty_property (Sni.MenuItemProperty property)
        {
            uint property_mask = 1 << (uint) property;

            this.dirty_properties |= property_mask;
            this.modified_properties |= property_mask;
        }

        public signal void child_added (Sni.MenuItem child);

        public signal void child_removed (Sni.MenuItem child);

        public signal void changed (Sni.MenuItemProperty property);

        public override void dispose ()
        {
            this.parent = null;
            this.children = null;

            base.dispose ();
        }
    }
}
