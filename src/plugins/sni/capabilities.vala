/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace Sni.Capabilities
{
    private int get_env (string name)
    {
        switch (GLib.Environment.get_variable (name)?.ascii_down ())
        {
            case "1":
            case "true":
                return 1;

            case "0":
            case "false":
                return 0;

            default:
                return -1;
        }
    }


    /**
     * Whether the host supports icon themes. Without it, we only can display app icon.
     */
    internal bool have_icon_theme ()
    {
        var env_value = get_env ("SNI_HAVE_ICON_THEME");
        if (env_value >= 0) {
            return (bool) env_value;
        }

        switch (Ft.get_desktop_name ())
        {
            case "gnome":
                return true;

            case "kde":
                return true;

            case "cinnamon":
                return false;

            case "xfce":
                return true;

            case "lxqt":
                return true;  // doesn't re-color symbolic icons though

            case "cosmic":
                return false;

            default:
                return false;
        }
    }


    /**
     * Whether the host supports PASSIVE status (when the timer stopped),
     * and the tray icon remain visible - just with lower priority.
     */
    internal bool have_passive_status ()
    {
        var env_value = get_env ("SNI_HAVE_PASSIVE_STATUS");
        if (env_value >= 0) {
            return (bool) env_value;
        }

        switch (Ft.get_desktop_name ())
        {
            case "gnome":
                return false;

            case "kde":
                return true;

            case "cinnamon":
                return false;

            case "xfce":
                return false;

            case "lxqt":
                return false;

            case "cosmic":
                return false;

            default:
                return false;
        }
    }


    /**
     * Whether the host makes the icon blinking in NEEDS_ATTENTION status (when the timer is
     * paused or finished).
     */
    internal bool have_attention_status ()
    {
        var env_value = get_env ("SNI_HAVE_ATTENTION_STATUS");
        if (env_value >= 0) {
            return (bool) env_value;
        }

        switch (Ft.get_desktop_name ())
        {
            case "gnome":
                return false;

            case "kde":
                return true;

            case "cinnamon":
                return false;

            case "xfce":
                return false;

            case "lxqt":
                return false;

            case "cosmic":
                return false;

            default:
                return false;
        }
    }


    /**
     * Whether the host prefers activation (clicking the icon brings the app to focus)
     * over displaying the context menu.
     */
    internal bool have_activation ()
    {
        var env_value = get_env ("SNI_HAVE_ACTIVATION");
        if (env_value >= 0) {
            return (bool) env_value;
        }

        switch (Ft.get_desktop_name ())
        {
            case "gnome":
                return false;  // via double-click

            case "kde":
                return true;

            case "cinnamon":
                return true;

            case "xfce":
                return true;

            case "lxqt":
                return true;  // no activation token

            case "cosmic":
                return false;

            default:
                return true;
        }
    }


    /**
     * Whether the host displays tooltips.
     *
     * It's required for scroll-wheel gesture. Otherwise user would change countdown duration
     * without much of a visual cue.
     */
    internal bool have_tooltips ()
    {
        var env_value = get_env ("SNI_HAVE_TOOLTIPS");
        if (env_value >= 0) {
            return (bool) env_value;
        }

        switch (Ft.get_desktop_name ())
        {
            case "gnome":
                return false;

            case "kde":
                return true;

            case "cinnamon":
                return false;  // shows app title

            case "xfce":
                return false;  // shows app title

            case "lxqt":
                return false;  // no description

            case "cosmic":
                return false;

            default:
                return false;
        }
    }


    /**
     * Whether the desktop prefers having icons in their menus,
     * and the host can handle custom icon themes in the menu.
     */
    internal bool have_menu_icons ()
    {
        var env_value = get_env ("SNI_HAVE_MENU_ICONS");
        if (env_value >= 0) {
            return (bool) env_value;
        }

        switch (Ft.get_desktop_name ())
        {
            case "gnome":
                return false;  // broken icons

            case "kde":
                return true;

            case "cinnamon":
                return false;  // broken layout

            case "xfce":
                return false;  // broken layout

            case "lxqt":
                return false;

            case "cosmic":
                return false;

            default:
                return false;
        }
    }


    /**
     * Whether the host displays radios right next to the label
     * or does it *break* the menu layout.
     *
     * When `false`, we use custom icons to display radio / checkmark.
     */
    internal bool have_toggles ()
    {
        if (!have_menu_icons ()) {
            return true;
        }

        var env_value = get_env ("SNI_HAVE_TOGGLES");
        if (env_value >= 0) {
            return (bool) env_value;
        }

        switch (Ft.get_desktop_name ())
        {
            case "gnome":
                return true;

            case "kde":
                return false;  // broken layout

            case "cinnamon":
                return true;

            case "xfce":
                return true;

            case "lxqt":
                return true;

            case "cosmic":
                return true;

            default:
                return true;
        }
    }
}
