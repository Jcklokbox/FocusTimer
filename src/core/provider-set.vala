/*
 * Copyright (c) 2024-2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

namespace Ft
{
    /**
     * Time between the start of provider initialization to resolution of availability.
     */
    private const int64 AVAILABILITY_TIMEOUT = Ft.Interval.MILLISECOND * 100;
    private const int64 AVAILABILITY_TIMEOUT_TOLERANCE = Ft.Interval.MILLISECOND * 20;


    // XXX: remove - only SINGLE is used
    public enum SelectionMode
    {
        NONE,
        SINGLE,
        ALL
    }


    private enum ProviderStatus
    {
        NOT_INITIALIZED,
        INITIALIZING,
        UNINITIALIZING,
        DISABLING,
        DISABLED,
        ENABLING,
        ENABLED;

        public bool is_transient ()
        {
            switch (this)
            {
                case INITIALIZING:
                case UNINITIALIZING:
                case DISABLING:
                case ENABLING:
                    return true;

                default:
                    return false;
            }
        }
    }


    private enum ProviderAvailability
    {
        UNKNOWN,
        AVAILABLE,
        UNAVAILABLE;

        public static int compare (ProviderAvailability value,
                                   ProviderAvailability other)
        {
            if (value == other) {
                return 0;
            }

            if (value == ProviderAvailability.AVAILABLE) {
                return -1;
            }

            if (other == ProviderAvailability.AVAILABLE) {
                return 1;
            }

            return value == ProviderAvailability.UNKNOWN ? -1 : 1;
        }
    }


    private class ProviderInfo
    {
        public Ft.Provider       instance;
        public Ft.Priority       priority;
        public Ft.ProviderStatus status = Ft.ProviderStatus.NOT_INITIALIZED;
        public bool              selected = false;
        public GLib.Cancellable? cancellable = null;
        public int64             initialization_time = Ft.Timestamp.UNDEFINED;
        public bool              destroying = false;

        public ProviderInfo (Ft.Provider instance,
                             Ft.Priority priority)
        {
            this.instance = instance;
            this.priority = priority;
        }

        ~ProviderInfo ()
        {
            // Expect to use .destroy() until provider gets unintialized
            assert (this.instance == null);
        }

        public int64 get_availability_timeout (ref int64 monotonic_time)
        {
            if (this.instance.available_set) {
                return 0;
            }

            if (Ft.Timestamp.is_undefined (this.initialization_time)) {
                return 0;
            }

            if (Ft.Timestamp.is_undefined (monotonic_time)) {
                monotonic_time = GLib.get_monotonic_time ();
            }

            return monotonic_time - this.initialization_time;
        }

        private void destroy_internal ()
        {
            var provider = this.instance;

            if (provider == null || this.status.is_transient ()) {
                return;
            }

            if (this.status == Ft.ProviderStatus.ENABLED)
            {
                this.status = Ft.ProviderStatus.DISABLING;
                provider.enabled = false;
                provider.disable.begin (
                    (obj, res) => {
                        try {
                            provider.disable.end (res);
                        }
                        catch (GLib.Error error) {
                            GLib.warning ("Error while disabling %s: %s",
                                          provider.get_type ().name (),
                                          error.message);
                        }

                        this.status = Ft.ProviderStatus.DISABLED;
                        this.destroy_internal ();
                    });
            }
            else if (this.status == Ft.ProviderStatus.DISABLED)
            {
                this.status = Ft.ProviderStatus.UNINITIALIZING;
                provider.uninitialize.begin (
                    (obj, res) => {
                        try {
                            provider.uninitialize.end (res);
                        }
                        catch (GLib.Error error) {
                            GLib.warning ("Error while uninitializing %s: %s",
                                          provider.get_type ().name (),
                                          error.message);
                        }

                        this.status = Ft.ProviderStatus.NOT_INITIALIZED;
                        this.destroy_internal ();
                    });
            }
            else if (this.status == Ft.ProviderStatus.NOT_INITIALIZED)
            {
                this.instance = null;
            }
        }

        public void destroy ()
        {
            this.destroying = true;

            if (this.cancellable != null) {
                this.cancellable.cancel ();
                this.cancellable = null;
            }

            this.destroy_internal ();
        }
    }


    public class ProviderSet<T> : GLib.Object
    {
        public Ft.SelectionMode selection_mode
        {
            get {
                return this._selection_mode;
            }
            construct {
                this._selection_mode = value;
            }
        }

        private Ft.SelectionMode                 _selection_mode = Ft.SelectionMode.ALL;
        private GLib.GenericSet<Ft.ProviderInfo> providers = null;
        private Peas.ExtensionSet?               extension_set = null;
        private uint                             update_selection_timeout_id = 0;
        private uint                             update_selection_idle_id = 0;
        private bool                             selection_invalid = false;
        private bool                             updating_selection = false;
        private bool                             should_enable = false;

        construct
        {
            this.providers = new GLib.GenericSet<Ft.ProviderInfo> (GLib.direct_hash,
                                                                   GLib.direct_equal);
        }

        public ProviderSet (Ft.SelectionMode selection_mode = Ft.SelectionMode.ALL)
        {
            GLib.Object (
                selection_mode: selection_mode
            );
        }

        /**
         * Manage provider according to its status.
         *
         * It should be called after every async action or status changed.
         */
        private void check_provider_status (Ft.ProviderInfo provider_info)
        {
            var provider = provider_info.instance;

            if (provider == null || provider_info.destroying) {
                return;
            }

            // Each action should call check_provider_status() at the end, so if the status is transient
            // we can ignore it.
            if (provider_info.status.is_transient ()) {
                return;
            }

            if (provider_info.selected)
            {
                if (provider_info.status == Ft.ProviderStatus.NOT_INITIALIZED)
                {
                    provider_info.status = Ft.ProviderStatus.INITIALIZING;
                    provider_info.cancellable = new GLib.Cancellable ();
                    provider_info.initialization_time = GLib.get_monotonic_time ();
                    provider.initialize.begin (
                        provider_info.cancellable,
                        (obj, res) => {
                            try {
                                provider.initialize.end (res);
                                provider_info.status = Ft.ProviderStatus.DISABLED;

                                this.check_provider_status (provider_info);

                                if (provider_info.selected && !provider.available_set) {
                                    this.queue_update_selection ();
                                }
                            }
                            catch (GLib.Error error) {
                                GLib.warning ("Error while initializing %s: %s",
                                              provider.get_type ().name (),
                                              error.message);
                                provider_info.status = Ft.ProviderStatus.NOT_INITIALIZED;
                            }
                        });
                }
                else if (this.should_enable &&
                         provider_info.status == Ft.ProviderStatus.DISABLED &&
                         provider.available)
                {
                    provider_info.status = Ft.ProviderStatus.ENABLING;
                    provider_info.cancellable = new GLib.Cancellable ();
                    provider.enable.begin (
                        provider_info.cancellable,
                        (obj, res) => {
                            try {
                                provider.enable.end (res);
                                provider_info.status = Ft.ProviderStatus.ENABLED;
                                provider.enabled = true;
                                this.check_provider_status (provider_info);
                            }
                            catch (GLib.Error error) {
                                GLib.warning ("Error while enabling %s: %s",
                                              provider.get_type ().name (),
                                              error.message);
                                provider_info.status = Ft.ProviderStatus.DISABLED;

                                if (provider_info.destroying) {
                                    provider_info.destroy ();
                                }
                            }
                        });
                }
                else if (!this.should_enable &&
                         provider_info.status == Ft.ProviderStatus.ENABLED)
                {
                    provider_info.status = Ft.ProviderStatus.DISABLING;
                    provider.enabled = false;
                    provider.disable.begin (
                        (obj, res) => {
                            try {
                                provider.disable.end (res);
                                provider_info.status = Ft.ProviderStatus.DISABLED;

                                this.check_provider_status (provider_info);
                            }
                            catch (GLib.Error error) {
                                GLib.warning ("Error while disabling %s: %s",
                                              provider.get_type ().name (),
                                              error.message);
                                provider_info.status = Ft.ProviderStatus.DISABLED;

                                if (provider_info.destroying) {
                                    provider_info.destroy ();
                                }
                            }
                        });
                }
            }
            else if (provider_info.status == Ft.ProviderStatus.ENABLED)
            {
                // Disable unselected providers. We try to disable even if unavailable.
                provider_info.status = Ft.ProviderStatus.DISABLING;
                provider.enabled = false;
                provider.disable.begin (
                    (obj, res) => {
                        try {
                            provider.disable.end (res);
                        }
                        catch (GLib.Error error) {
                            GLib.warning ("Error while disabling %s: %s",
                                          provider.get_type ().name (),
                                          error.message);
                        }

                        provider_info.status = Ft.ProviderStatus.DISABLED;
                        this.check_provider_status (provider_info);
                    });
            }
        }

        private static ProviderAvailability get_availability (Ft.ProviderInfo provider_info,
                                                              int64           provider_timeout)
        {
            if (provider_info.instance.available_set) {
                return provider_info.instance.available
                        ? ProviderAvailability.AVAILABLE
                        : ProviderAvailability.UNAVAILABLE;
            }

            if (provider_info.status == Ft.ProviderStatus.NOT_INITIALIZED ||
                provider_info.status == Ft.ProviderStatus.INITIALIZING ||
                provider_timeout < AVAILABILITY_TIMEOUT)
            {
                return ProviderAvailability.UNKNOWN;
            }

            return ProviderAvailability.UNAVAILABLE;
        }

        private static int compare (Ft.ProviderInfo provider_info,
                                    int64           provider_timeout,
                                    Ft.ProviderInfo other_info,
                                    int64           other_timeout)
        {
            var provider_availability = get_availability (provider_info, provider_timeout);
            var other_availability = get_availability (other_info, other_timeout);

            if (provider_availability != other_availability)
            {
                if (provider_availability == ProviderAvailability.UNKNOWN &&
                    provider_info.priority > other_info.priority)
                {
                    return -1;
                }

                if (other_availability == ProviderAvailability.UNKNOWN &&
                    other_info.priority > provider_info.priority)
                {
                    return 1;
                }

                return ProviderAvailability.compare (provider_availability, other_availability);
            }

            if (provider_info.priority != other_info.priority) {
                return provider_info.priority > other_info.priority ? -1 : 1;
            }

            if (provider_info.selected != other_info.selected) {
                return provider_info.selected ? -1 : 1;
            }

            return 0;
        }

        private void get_preferred_provider_info (out unowned Ft.ProviderInfo? preferred_provider_info,
                                                  out int64                    preferred_provider_timeout)
        {
            unowned Ft.ProviderInfo? tmp_preferred_provider_info = null;
            int64                    tmp_preferred_provider_timeout = 0;
            int64                    monotonic_time = Ft.Timestamp.UNDEFINED;

            this.providers.@foreach (
                (provider_info) => {
                    var provider_timeout = provider_info.get_availability_timeout (ref monotonic_time);

                    if (tmp_preferred_provider_info == null)
                    {
                        tmp_preferred_provider_info = provider_info;
                        tmp_preferred_provider_timeout = provider_timeout;
                    }
                    else {
                        var comparison_result = compare (tmp_preferred_provider_info,
                                                         tmp_preferred_provider_timeout,
                                                         provider_info,
                                                         provider_timeout);
                        if (comparison_result > 0) {
                            tmp_preferred_provider_info = provider_info;
                            tmp_preferred_provider_timeout = provider_timeout;
                        }
                    }
                });

            preferred_provider_info = tmp_preferred_provider_info;
            preferred_provider_timeout = tmp_preferred_provider_timeout;
        }

        /**
         * Find best provider, preferably available with highest priority.
         */
        private void select_single ()
        {
            unowned Ft.ProviderInfo? preferred_provider_info = null;
            int64                    preferred_provider_timeout = 0;
            var                      selection_changed = false;

            this.get_preferred_provider_info (out preferred_provider_info,
                                              out preferred_provider_timeout);

            if (preferred_provider_info == null) {
                this.select_none ();
                return;
            }

            if (!preferred_provider_info.instance.available_set &&
                preferred_provider_timeout > 0 &&
                preferred_provider_timeout < AVAILABILITY_TIMEOUT)
            {
                this.schedule_update_selection (preferred_provider_timeout);
                return;
            }

            if (get_availability (preferred_provider_info, preferred_provider_timeout) ==
                ProviderAvailability.UNAVAILABLE)
            {
                this.select_none ();
                return;
            }

            this.providers.@foreach (
                (provider_info) => {
                    var selected = provider_info == preferred_provider_info;

                    if (provider_info.selected != selected)
                    {
                        provider_info.selected = selected;
                        selection_changed = true;

                        if (selected) {
                            this.provider_selected ((T) provider_info.instance);
                        }
                        else {
                            this.provider_unselected ((T) provider_info.instance);
                        }

                        this.check_provider_status (provider_info);
                    }
                });

            if (selection_changed) {
                this.selection_changed ();
            }
        }

        /**
         * Disable all providers.
         */
        private void select_none ()
        {
            var selection_changed = false;

            this.providers.@foreach (
                (provider_info) => {
                    if (provider_info.selected) {
                        provider_info.selected = false;
                        selection_changed = true;

                        this.provider_unselected ((T) provider_info.instance);
                        this.check_provider_status (provider_info);
                    }
                });

            if (selection_changed) {
                this.selection_changed ();
            }
        }

        /**
         * Try enabling all providers.
         */
        private void select_all ()
        {
            var selection_changed = false;

            this.providers.@foreach (
                (provider_info) => {
                    if (!provider_info.selected) {
                        provider_info.selected = true;
                        selection_changed = true;
                        this.provider_selected ((T) provider_info.instance);
                        this.check_provider_status (provider_info);
                    }
                });

            if (selection_changed) {
                this.selection_changed ();
            }
        }

        private void update_selection ()
        {
            if (this.providers == null) {
                return;
            }

            if (this.updating_selection) {
                this.selection_invalid = true;
                return;
            }

            if (this.update_selection_timeout_id != 0) {
                GLib.Source.remove (this.update_selection_timeout_id);
                this.update_selection_timeout_id = 0;
            }

            if (this.update_selection_idle_id != 0) {
                GLib.Source.remove (this.update_selection_idle_id);
                this.update_selection_idle_id = 0;
            }

            this.updating_selection = true;
            this.selection_invalid = false;

            switch (this._selection_mode)
            {
                case Ft.SelectionMode.NONE:
                    this.select_none ();
                    break;

                case Ft.SelectionMode.SINGLE:
                    this.select_single ();
                    break;

                case Ft.SelectionMode.ALL:
                    this.select_all ();
                    break;

                default:
                    assert_not_reached ();
            }

            this.updating_selection = false;

            if (this.selection_invalid) {
                this.update_selection ();
            }
        }

        private void schedule_update_selection (int64 timeout)
        {
            if (this.update_selection_timeout_id != 0) {
                return;
            }

            this.update_selection_timeout_id = GLib.Timeout.add (
                    Ft.Timestamp.to_milliseconds_uint (timeout + AVAILABILITY_TIMEOUT_TOLERANCE),
                    () => {
                        this.update_selection_timeout_id = 0;
                        this.update_selection ();

                        return GLib.Source.REMOVE;
                    });
            GLib.Source.set_name_by_id (this.update_selection_timeout_id,
                                        "Ft.ProviderSet.schedule_update_selection");
        }

        private void queue_update_selection ()
        {
            if (this.update_selection_idle_id != 0) {
                return;
            }

            this.update_selection_idle_id = GLib.Idle.add (
                () => {
                    this.update_selection_idle_id = 0;
                    this.update_selection ();

                    return GLib.Source.REMOVE;
                });
            GLib.Source.set_name_by_id (this.update_selection_idle_id,
                                        "Ft.ProviderSet.queue_update_selection");
        }

        private unowned Ft.ProviderInfo? lookup_info (Ft.Provider instance)
        {
            unowned Ft.ProviderInfo provider_info = null;

            if (this.providers == null) {
                return null;
            }

            this.providers.@foreach (
                (_provider_info) => {
                    if (_provider_info.instance == instance) {
                        provider_info = _provider_info;
                    }
                });

            return provider_info;
        }

        private void on_provider_notify_available (GLib.Object    object,
                                                   GLib.ParamSpec pspec)
        {
            var provider = (Ft.Provider) object;
            var provider_info = this.lookup_info (provider);

            if (provider_info == null) {
                return;
            }

            if (provider_info.selected && provider.available) {
                this.check_provider_status (provider_info);
            }
            else {
                this.update_selection ();
            }
        }

        private void on_provider_notify_enabled (GLib.Object    object,
                                                 GLib.ParamSpec pspec)
        {
            var provider = (Ft.Provider) object;

            if (provider.enabled) {
                this.provider_enabled ((T) provider);
            }
            else {
                this.provider_disabled ((T) provider);
            }
        }

        private void destroy_info (Ft.ProviderInfo provider_info)
        {
            provider_info.instance.notify["available"].disconnect (this.on_provider_notify_available);
            provider_info.instance.notify["enabled"].disconnect (this.on_provider_notify_enabled);

            provider_info.destroy ();
        }

        public void add (T           provider,
                         Ft.Priority priority = Ft.Priority.DEFAULT)
        {
            var instance = provider as Ft.Provider;

            assert (instance != null);

            if (this.providers == null) {
                return;
            }

            var existing_provider_info = this.lookup_info (instance);

            if (existing_provider_info != null) {
                existing_provider_info.priority = priority;
            }
            else {
                var provider_info = new Ft.ProviderInfo (instance, priority);

                if (this.providers.add (provider_info)) {
                    provider_info.instance.notify["available"].connect (this.on_provider_notify_available);
                    provider_info.instance.notify["enabled"].connect (this.on_provider_notify_enabled);
                }
            }

            if (this.should_enable) {
                this.update_selection ();
            }
            else {
                this.queue_update_selection ();
            }
        }

        public void remove (T provider)
        {
            var instance = provider as Ft.Provider;

            assert (instance != null);

            var provider_info = this.lookup_info (instance);

            if (provider_info == null || provider_info.destroying) {
                return;
            }

            var was_selected = provider_info.selected;

            if (!this.providers.remove (provider_info)) {
                return;
            }

            this.destroy_info (provider_info);

            if (was_selected) {
                this.update_selection ();
            }
        }

        public void remove_all ()
        {
            if (this.providers == null) {
                return;
            }

            if (this.update_selection_timeout_id != 0) {
                GLib.Source.remove (this.update_selection_timeout_id);
                this.update_selection_timeout_id = 0;
            }

            if (this.update_selection_idle_id != 0) {
                GLib.Source.remove (this.update_selection_idle_id);
                this.update_selection_idle_id = 0;
            }

            Ft.ProviderInfo[] providers = {};

            this.providers.@foreach (
                (provider_info) => {
                    providers += provider_info;
                });

            this.providers.remove_all ();

            foreach (var provider_info in providers) {
                this.destroy_info (provider_info);
            }
        }

        private void add_extension (Peas.PluginInfo info,
                                    GLib.Object     extension)
        {
            Ft.Priority priority = Ft.Priority.DEFAULT;

            unowned var priority_pspec = extension.get_class ().find_property ("priority");

            if (priority_pspec is GLib.ParamSpecEnum) {
                extension.@get ("priority", ref priority);
            }
            else {
                priority = Ft.Priority.from_string (info.get_external_data ("Priority"));
            }

            this.add ((T) extension, priority);
        }

        /**
         * Initialize Peas extensions discovery.
         */
        public void discover ()
        {
            if (this.extension_set != null) {
                return;
            }

            var engine = Peas.Engine.get_default ();
            var n = engine.get_n_items ();

            this.extension_set = new Peas.ExtensionSet.with_properties (
                    engine, typeof (T), {}, {});
            this.extension_set.extension_added.connect (this.on_extension_added);
            this.extension_set.extension_removed.connect (this.on_extension_removed);

            for (var i = 0U; i < n; i++)
            {
                var info = (Peas.PluginInfo) engine.get_item (i);
                var extension = this.extension_set.get_extension (info);

                if (extension != null && extension is Ft.Provider) {
                    this.add_extension (info, extension);
                }
            }
        }

        private void on_extension_added (Peas.PluginInfo info,
                                         GLib.Object     extension)
        {
            if (extension is Ft.Provider) {
                this.add_extension (info, extension);
            }
        }

        private void on_extension_removed (Peas.PluginInfo info,
                                           GLib.Object     extension)
        {
            if (extension is Ft.Provider) {
                this.remove ((T) extension);
            }
        }

        public void enable ()
        {
            this.should_enable = true;

            this.update_selection ();

            if (this.providers == null) {
                return;
            }

            this.providers.@foreach (
                (provider_info) => {
                    this.check_provider_status (provider_info);
                });
        }

        public void disable ()
        {
            this.should_enable = false;

            if (this.providers == null) {
                return;
            }

            this.providers.@foreach (
                (provider_info) => {
                    this.check_provider_status (provider_info);
                });
        }

        public void @foreach (GLib.Func<T> func)
        {
            if (this.providers == null) {
                return;
            }

            this.providers.@foreach (
                (provider_info) => {
                    func ((T) provider_info.instance);
                });
        }

        public void foreach_selected (GLib.Func<T> func)
        {
            if (this.providers == null) {
                return;
            }

            this.providers.@foreach (
                (provider_info) => {
                    if (provider_info.selected) {
                        func ((T) provider_info.instance);
                    }
                });
        }

        public void foreach_enabled (GLib.Func<T> func)
        {
            if (this.providers == null) {
                return;
            }

            this.providers.@foreach (
                (provider_info) => {
                    if (provider_info.instance.enabled) {
                        func ((T) provider_info.instance);
                    }
                });
        }

        internal signal void provider_selected (T provider);

        internal signal void provider_unselected (T provider);

        public signal void provider_enabled (T provider);

        public signal void provider_disabled (T provider);

        public signal void selection_changed ();

        public override void dispose ()
        {
            if (this.update_selection_timeout_id != 0) {
                GLib.Source.remove (this.update_selection_timeout_id);
                this.update_selection_timeout_id = 0;
            }

            if (this.update_selection_idle_id != 0) {
                GLib.Source.remove (this.update_selection_idle_id);
                this.update_selection_idle_id = 0;
            }

            if (this.extension_set != null) {
                this.extension_set.extension_added.disconnect (this.on_extension_added);
                this.extension_set.extension_removed.disconnect (this.on_extension_removed);
                this.extension_set = null;
            }

            this.remove_all ();

            base.dispose ();
        }
    }
}
