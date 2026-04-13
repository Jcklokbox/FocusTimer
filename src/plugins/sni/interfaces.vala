/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Sni
{
    [DBus (name = "org.kde.StatusNotifierWatcher")]
    public interface StatusNotifierWatcher : GLib.Object
    {
        public abstract bool is_status_notifier_host_registered { get; }
        public abstract int32 protocol_version { get; }

        public abstract async void register_status_notifier_item (string service) throws GLib.DBusError, GLib.IOError;
    }


	public enum IndicatorStatus
	{
		PASSIVE,
		ACTIVE,
		NEEDS_ATTENTION;

        public string to_string ()
        {
            switch (this)
            {
                case PASSIVE:
                    return "Passive";

                case ACTIVE:
                    return "Active";

                case NEEDS_ATTENTION:
                    return "NeedsAttention";

                default:
                    assert_not_reached ();
            }
        }

        public static Sni.IndicatorStatus from_string (string? status)
        {
            switch (status)
            {
                case "Passive":
                    return PASSIVE;

                case "NeedsAttention":
                    return NEEDS_ATTENTION;

                default:
                    return ACTIVE;
            }
        }
	}


    public struct Pixmap
    {
        public int32   width;
        public int32   height;
        public uint8[] data;

        public GLib.Variant to_variant ()
        {
            return new GLib.Variant.tuple ({
                new GLib.Variant.int32 (this.width),
                new GLib.Variant.int32 (this.height),
                new GLib.Variant.from_bytes (GLib.VariantType.BYTE,
                                             new GLib.Bytes (this.data),
                                             true),
            });
        }
    }


    public struct Tooltip
    {
        public string   icon_name;
        public Pixmap[] icon_pixmaps;
        public string   title;
        public string   description;  // supports markup

        public Tooltip ()
        {
            this.icon_name = "";
            this.icon_pixmaps = {};
            this.title = "";
            this.description = "";
        }

        public GLib.Variant to_variant ()
        {
            return new GLib.Variant.tuple ({
                new GLib.Variant.string (this.icon_name),
                serialize_pixmaps (this.icon_pixmaps),
                new GLib.Variant.string (this.title),
                new GLib.Variant.string (this.description),
            });
        }

        public bool equals (Sni.Tooltip other)
        {
            return this.description == other.description &&
                   this.title == other.title &&
                   this.icon_name == other.icon_name;
        }
    }


    public enum MenuToggleType
    {
        NONE,
        CHECKMARK,
        RADIO;

        public string to_string ()
        {
            switch (this)
            {
                case NONE:
                    return "";

                case CHECKMARK:
                    return "checkmark";

                case RADIO:
                    return "radio";

                default:
                    assert_not_reached ();
            }
        }
    }


    public enum MenuItemType
    {
        STANDARD,
        SEPARATOR;

        public string to_string ()
        {
            switch (this)
            {
                case STANDARD:
                    return "standard";

                case SEPARATOR:
                    return "separator";

                default:
                    assert_not_reached ();
            }
        }
    }


    /**
     * Menu item properties exported in the D-Bus API
     */
    public enum MenuItemProperty
    {
        INVALID,
        TYPE,
        LABEL,
        ENABLED,
        VISIBLE,
        ICON_NAME,
        TOGGLE_TYPE,
        TOGGLE_STATE,
        CHILDREN_DISPLAY,
        ICON_DATA,
        SHORTCUT;

        public static MenuItemProperty from_string (string str)
        {
            switch (str)
            {
                case "type":
                    return TYPE;

                case "label":
                    return LABEL;

                case "enabled":
                    return ENABLED;

                case "visible":
                    return VISIBLE;

                case "icon-name":
                    return ICON_NAME;

                case "toggle-type":
                    return TOGGLE_TYPE;

                case "toggle-state":
                    return TOGGLE_STATE;

                case "children-display":
                    return CHILDREN_DISPLAY;

                case "icon-data":
                    return ICON_DATA;

                case "shortcut":
                    return SHORTCUT;

                default:
                    return INVALID;
            }
        }

        public static Sni.MenuItemProperty[] from_strv (string[] strv)
        {
            if (strv.length == 0) {
                return all ();
            }
            else {
                var properties = new Sni.MenuItemProperty[strv.length];

                for (var index = 0; index < strv.length; index++) {
                    properties[index] = Sni.MenuItemProperty.from_string (strv[index]);
                }

                return properties;
            }
        }

        public static Sni.MenuItemProperty[] all ()
        {
            return {
                Sni.MenuItemProperty.TYPE,
                Sni.MenuItemProperty.LABEL,
                Sni.MenuItemProperty.ENABLED,
                Sni.MenuItemProperty.VISIBLE,
                Sni.MenuItemProperty.ICON_NAME,
                Sni.MenuItemProperty.TOGGLE_TYPE,
                Sni.MenuItemProperty.TOGGLE_STATE,
                Sni.MenuItemProperty.CHILDREN_DISPLAY,
                // Sni.MenuItemProperty.ICON_DATA,
                // Sni.MenuItemProperty.SHORTCUT,
            };
        }

        public string to_string ()
        {
            switch (this)
            {
                case TYPE:
                    return "type";

                case LABEL:
                    return "label";

                case ENABLED:
                    return "enabled";

                case VISIBLE:
                    return "visible";

                case ICON_NAME:
                    return "icon-name";

                case TOGGLE_TYPE:
                    return "toggle-type";

                case TOGGLE_STATE:
                    return "toggle-state";

                case CHILDREN_DISPLAY:
                    return "children-display";

                case ICON_DATA:
                    return "icon-data";

                case SHORTCUT:
                    return "shortcut";

                case INVALID:
                    return "";

                default:
                    assert_not_reached ();
            }
        }
    }
}
