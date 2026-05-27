/*
 * This file is part of focus-timer
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Authors: Kamil Prusko <kamilprusko@gmail.com>
 */

namespace Tests
{
    public enum Scenario
    {
        AVAILABLE,
        UNAVAILABLE,
        DELAYED_AVAILABLE,
        DELAYED_UNAVAILABLE,
        ASYNC_AVAILABLE,
        ASYNC_UNAVAILABLE,
        NO_AVAILABILITY_REPORTED,
    }


    public interface AntiGravityProvider : Ft.Provider
    {
        public abstract Scenario scenario { get; construct set; }
    }


    public class SimpleAntiGravityProvider : Ft.Provider, AntiGravityProvider
    {
        public Scenario scenario { get; construct set; }

        public uint initialize_count = 0;
        public uint uninitialize_count = 0;
        public uint enable_count = 0;
        public uint disable_count = 0;

        public SimpleAntiGravityProvider (Scenario scenario)
        {
            GLib.Object (
                scenario: scenario
            );
        }

        private void initialize__available ()
        {
            this.available = true;
        }

        private void initialize__unavailable ()
        {
            this.available = false;
        }

        private void initialize__delayed_available ()
        {
            GLib.Idle.add (() => {
                this.available = true;

                return GLib.Source.REMOVE;
            });
        }

        private void initialize__delayed_unavailable ()
        {
            GLib.Idle.add (() => {
                this.available = false;

                return GLib.Source.REMOVE;
            });
        }

        private async void initialize__async_available ()
        {
            GLib.Idle.add (() => {
                this.initialize__async_available.callback ();

                return GLib.Source.REMOVE;
            });

            yield;

            this.available = true;
        }

        private async void initialize__async_unavailable ()
        {
            GLib.Idle.add (() => {
                this.initialize__async_unavailable.callback ();

                return GLib.Source.REMOVE;
            });

            yield;

            this.available = false;
        }

        private void initialize__no_availability_reported ()
        {
        }

        public override async void initialize (GLib.Cancellable? cancellable) throws GLib.Error
        {
            this.initialize_count++;

            switch (this.scenario)
            {
                case Scenario.AVAILABLE:
                    this.initialize__available ();
                    break;

                case Scenario.UNAVAILABLE:
                    this.initialize__unavailable ();
                    break;

                case Scenario.DELAYED_AVAILABLE:
                    this.initialize__delayed_available ();
                    break;

                case Scenario.DELAYED_UNAVAILABLE:
                    this.initialize__delayed_unavailable ();
                    break;

                case Scenario.NO_AVAILABILITY_REPORTED:
                    this.initialize__no_availability_reported ();
                    break;

                case Scenario.ASYNC_AVAILABLE:
                    yield this.initialize__async_available ();
                    break;

                case Scenario.ASYNC_UNAVAILABLE:
                    yield this.initialize__async_unavailable ();
                    break;

                default:
                    assert_not_reached ();
            }
        }

        public override async void uninitialize () throws GLib.Error
        {
            this.uninitialize_count++;
        }

        public override async void enable (GLib.Cancellable? cancellable) throws GLib.Error
        {
            this.enable_count++;
        }

        public override async void disable () throws GLib.Error
        {
            this.disable_count++;
        }

        public override void dispose ()
        {
            base.dispose ();
        }
    }


    public class ProviderSetTest : Tests.TestSuite
    {
        private GLib.MainLoop? main_loop = null;
        private uint           timeout_id = 0;

        public ProviderSetTest ()
        {
            this.add_test ("enable_single__available", this.test_enable_single__available);
            this.add_test ("enable_single__unavailable", this.test_enable_single__unavailable);
            this.add_test ("enable_single__delayed_available_1", this.test_enable_single__delayed_available_1);
            this.add_test ("enable_single__delayed_available_2", this.test_enable_single__delayed_available_2);
            this.add_test ("enable_single__delayed_unavailable", this.test_enable_single__delayed_unavailable);
            this.add_test ("enable_single__async_available", this.test_enable_single__async_available);
            this.add_test ("enable_single__switch_to_higher_priority", this.test_enable_single__switch_to_higher_priority);
            this.add_test ("enable_single__no_availability_reported", this.test_enable_single__no_availability_reported);
            this.add_test ("enable_single__disable_when_all_unavailable", this.test_enable_single__disable_when_all_unavailable);
            this.add_test ("enable_single__priority_1", this.test_enable_single__priority_1);
            this.add_test ("enable_single__priority_2", this.test_enable_single__priority_2);
            this.add_test ("enable_single__priority_3", this.test_enable_single__priority_3);
            this.add_test ("destroy", this.test_destroy);

        }

        public override void setup ()
        {
            this.main_loop = new GLib.MainLoop ();
        }

        public override void teardown ()
        {
            this.main_loop = null;
        }

        private bool run_main_loop (uint timeout = 1000)
        {
            var success = true;

            if (this.timeout_id != 0) {
                GLib.Source.remove (this.timeout_id);
                this.timeout_id = 0;
            }

            this.timeout_id = GLib.Timeout.add (timeout, () => {
                this.timeout_id = 0;
                this.main_loop.quit ();

                success = false;

                return GLib.Source.REMOVE;
            });

            this.main_loop.run ();

            return success;
        }

        private void quit_main_loop ()
        {
            if (this.timeout_id != 0) {
                GLib.Source.remove (this.timeout_id);
                this.timeout_id = 0;
            }

            this.main_loop.quit ();
        }

        public void test_enable_single__available ()
        {
            var providers = new Ft.ProviderSet<AntiGravityProvider> (Ft.SelectionMode.SINGLE);
            providers.provider_enabled.connect (() => { this.quit_main_loop (); });

            var provider_low = new SimpleAntiGravityProvider (Scenario.AVAILABLE);
            providers.add (provider_low, Ft.Priority.LOW);

            var provider_high = new SimpleAntiGravityProvider (Scenario.AVAILABLE);
            providers.add (provider_high, Ft.Priority.HIGH);

            assert_cmpuint (provider_low.initialize_count, GLib.CompareOperator.EQ, 0);
            assert_cmpuint (provider_high.initialize_count, GLib.CompareOperator.EQ, 0);

            providers.enable ();

            assert_true (this.run_main_loop ());

            assert_true (provider_high.available_set);
            assert_true (provider_high.available);
            assert_true (provider_high.enabled);
            assert_cmpuint (provider_high.initialize_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_high.enable_count, GLib.CompareOperator.EQ, 1);

            assert_false (provider_low.available_set);
            assert_false (provider_low.available);
            assert_false (provider_low.enabled);
            assert_cmpuint (provider_low.initialize_count, GLib.CompareOperator.EQ, 0);
            assert_cmpuint (provider_low.enable_count, GLib.CompareOperator.EQ, 0);
        }

        public void test_enable_single__unavailable ()
        {
            var providers = new Ft.ProviderSet<AntiGravityProvider> (Ft.SelectionMode.SINGLE);
            providers.provider_enabled.connect (() => { this.quit_main_loop (); });

            var provider_low = new SimpleAntiGravityProvider (Scenario.AVAILABLE);
            providers.add (provider_low, Ft.Priority.LOW);
            assert_cmpuint (provider_low.initialize_count, GLib.CompareOperator.EQ, 0);

            var provider_high = new SimpleAntiGravityProvider (Scenario.UNAVAILABLE);
            providers.add (provider_high, Ft.Priority.HIGH);
            assert_cmpuint (provider_low.initialize_count, GLib.CompareOperator.EQ, 0);

            providers.enable ();
            assert_false (provider_low.enabled);
            assert_false (provider_high.enabled);

            assert_true (this.run_main_loop ());

            assert_true (provider_high.available_set);
            assert_false (provider_high.available);
            assert_false (provider_high.enabled);
            assert_cmpuint (provider_high.initialize_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_high.enable_count, GLib.CompareOperator.EQ, 0);

            assert_true (provider_low.available_set);
            assert_true (provider_low.available);
            assert_true (provider_low.enabled);
            assert_cmpuint (provider_low.initialize_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_low.enable_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_low.uninitialize_count, GLib.CompareOperator.EQ, 0);
        }

        public void test_enable_single__delayed_available_1 ()
        {
            var providers = new Ft.ProviderSet<AntiGravityProvider> (Ft.SelectionMode.SINGLE);
            providers.provider_enabled.connect (() => { this.quit_main_loop (); });

            var provider_low = new SimpleAntiGravityProvider (Scenario.AVAILABLE);
            providers.add (provider_low, Ft.Priority.LOW);
            assert_cmpuint (provider_low.initialize_count, GLib.CompareOperator.EQ, 0);

            var provider_high = new SimpleAntiGravityProvider (Scenario.DELAYED_AVAILABLE);
            providers.add (provider_high, Ft.Priority.HIGH);
            assert_cmpuint (provider_high.initialize_count, GLib.CompareOperator.EQ, 0);

            providers.enable ();
            assert_true (this.run_main_loop ());

            assert_true (provider_high.available_set);
            assert_true (provider_high.available);
            assert_true (provider_high.enabled);
            assert_cmpuint (provider_high.initialize_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_high.enable_count, GLib.CompareOperator.EQ, 1);

            assert_cmpuint (provider_low.initialize_count, GLib.CompareOperator.EQ, 0);
            assert_cmpuint (provider_low.enable_count, GLib.CompareOperator.EQ, 0);
        }

        /**
         * Add a provider after the fallback got enabled.
         *
         * Expect to switch to the better provider.
         */
        public void test_enable_single__delayed_available_2 ()
        {
            var providers = new Ft.ProviderSet<AntiGravityProvider> (Ft.SelectionMode.SINGLE);
            var provider_low = new SimpleAntiGravityProvider (Scenario.AVAILABLE);
            SimpleAntiGravityProvider? added_provider = null;

            providers.provider_enabled.connect (
                () => {
                    if (added_provider == null) {
                        added_provider = new SimpleAntiGravityProvider (Scenario.DELAYED_AVAILABLE);
                        providers.add (added_provider, Ft.Priority.DEFAULT);
                    }
                    else {
                        this.quit_main_loop ();
                    }
                });

            providers.add (provider_low, Ft.Priority.LOW);
            providers.enable ();

            assert_true (this.run_main_loop ());

            assert_true (added_provider.available);
            assert_true (added_provider.enabled);
            assert_cmpuint (added_provider.initialize_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (added_provider.enable_count, GLib.CompareOperator.EQ, 1);

            assert_false (provider_low.enabled);
            assert_cmpuint (provider_low.enable_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_low.disable_count, GLib.CompareOperator.EQ, 1);
        }

        public void test_enable_single__delayed_unavailable ()
        {
            var providers = new Ft.ProviderSet<AntiGravityProvider> (Ft.SelectionMode.SINGLE);
            providers.provider_enabled.connect (() => { this.quit_main_loop (); });

            var provider_low = new SimpleAntiGravityProvider (Scenario.AVAILABLE);
            providers.add (provider_low, Ft.Priority.LOW);
            assert_cmpuint (provider_low.initialize_count, GLib.CompareOperator.EQ, 0);

            var provider_high = new SimpleAntiGravityProvider (Scenario.DELAYED_UNAVAILABLE);
            providers.add (provider_high, Ft.Priority.HIGH);
            assert_cmpuint (provider_high.initialize_count, GLib.CompareOperator.EQ, 0);

            providers.enable ();
            assert_true (this.run_main_loop ());

            assert_true (provider_high.available_set);
            assert_false (provider_high.available);
            assert_false (provider_high.enabled);
            assert_cmpuint (provider_high.initialize_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_high.enable_count, GLib.CompareOperator.EQ, 0);

            assert_true (provider_low.available_set);
            assert_true (provider_low.available);
            assert_true (provider_low.enabled);
            assert_cmpuint (provider_low.initialize_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_low.enable_count, GLib.CompareOperator.EQ, 1);
        }

        public void test_enable_single__switch_to_higher_priority ()
        {
            var providers = new Ft.ProviderSet<AntiGravityProvider> (Ft.SelectionMode.SINGLE);
            providers.provider_enabled.connect (() => { this.quit_main_loop (); });

            var provider_low = new SimpleAntiGravityProvider (Scenario.AVAILABLE);
            providers.add (provider_low, Ft.Priority.LOW);

            var provider_high = new SimpleAntiGravityProvider (Scenario.UNAVAILABLE);
            providers.add (provider_high, Ft.Priority.HIGH);

            providers.enable ();

            // Expect low priority provider to be enabled.
            assert_true (this.run_main_loop ());

            assert_true (provider_low.available);
            assert_true (provider_low.enabled);
            assert_cmpuint (provider_low.enable_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_low.disable_count, GLib.CompareOperator.EQ, 0);

            assert_true (provider_high.available_set);
            assert_false (provider_high.available);
            assert_false (provider_high.enabled);
            assert_cmpuint (provider_high.initialize_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_high.enable_count, GLib.CompareOperator.EQ, 0);

            // High priority provider becomes available. Expect to switch providers.
            provider_high.available = true;

            assert_true (this.run_main_loop ());

            assert_true (provider_high.available);
            assert_true (provider_high.enabled);
            assert_cmpuint (provider_high.initialize_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_high.enable_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_high.disable_count, GLib.CompareOperator.EQ, 0);

            assert_false (provider_low.enabled);
            assert_cmpuint (provider_low.disable_count, GLib.CompareOperator.EQ, 1);
        }

        public void test_enable_single__no_availability_reported ()
        {
            var providers = new Ft.ProviderSet<AntiGravityProvider> (Ft.SelectionMode.SINGLE);
            providers.provider_enabled.connect (() => { this.quit_main_loop (); });

            var provider_low = new SimpleAntiGravityProvider (Scenario.AVAILABLE);
            providers.add (provider_low, Ft.Priority.LOW);

            var provider_high = new SimpleAntiGravityProvider (Scenario.NO_AVAILABILITY_REPORTED);
            providers.add (provider_high, Ft.Priority.HIGH);

            providers.enable ();

            assert_true (this.run_main_loop ());

            assert_true (provider_low.available_set);
            assert_true (provider_low.available);
            assert_true (provider_low.enabled);
            assert_cmpuint (provider_low.initialize_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_low.enable_count, GLib.CompareOperator.EQ, 1);

            assert_false (provider_high.available_set);
            assert_false (provider_high.available);
            assert_false (provider_high.enabled);
            assert_cmpuint (provider_high.initialize_count, GLib.CompareOperator.EQ, 1);
        }

        public void test_enable_single__disable_when_all_unavailable ()
        {
            var providers = new Ft.ProviderSet<AntiGravityProvider> (Ft.SelectionMode.SINGLE);
            var wait_for_provider_disabled = false;

            var provider_high = new SimpleAntiGravityProvider (Scenario.UNAVAILABLE);
            providers.add (provider_high, Ft.Priority.HIGH);

            var provider_low = new SimpleAntiGravityProvider (Scenario.AVAILABLE);
            providers.add (provider_low, Ft.Priority.LOW);

            providers.provider_enabled.connect (() => {
                if (!wait_for_provider_disabled) {
                    this.quit_main_loop ();
                }
            });
            providers.provider_disabled.connect ((provider) => {
                if (wait_for_provider_disabled && provider == provider_low) {
                    this.quit_main_loop ();
                }
            });

            providers.enable ();

            assert_true (this.run_main_loop ());

            assert_true (provider_low.enabled);
            assert_cmpuint (provider_low.enable_count, GLib.CompareOperator.EQ, 1);

            wait_for_provider_disabled = true;
            GLib.Idle.add (
                () => {
                    provider_low.available = false;

                    return GLib.Source.REMOVE;
                });

            assert_true (this.run_main_loop ());

            assert_false (provider_high.enabled);
            assert_false (provider_low.enabled);
            assert_cmpuint (provider_high.enable_count, GLib.CompareOperator.EQ, 0);
            assert_cmpuint (provider_low.disable_count, GLib.CompareOperator.EQ, 1);
        }

        public void test_enable_single__priority_1 ()
        {
            var providers = new Ft.ProviderSet<AntiGravityProvider> (Ft.SelectionMode.SINGLE);
            providers.provider_enabled.connect (() => { this.quit_main_loop (); });

            var provider_high = new SimpleAntiGravityProvider (Scenario.UNAVAILABLE);
            providers.add (provider_high, Ft.Priority.HIGH);

            var provider_default = new SimpleAntiGravityProvider (Scenario.DELAYED_AVAILABLE);
            providers.add (provider_default, Ft.Priority.DEFAULT);

            var provider_low = new SimpleAntiGravityProvider (Scenario.AVAILABLE);
            providers.add (provider_low, Ft.Priority.LOW);

            providers.enable ();

            assert_true (this.run_main_loop ());

            assert_true (provider_default.available);
            assert_true (provider_default.enabled);
            assert_cmpuint (provider_default.initialize_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_default.enable_count, GLib.CompareOperator.EQ, 1);

            assert_false (provider_low.enabled);
            assert_cmpuint (provider_low.initialize_count, GLib.CompareOperator.EQ, 0);
        }

        public void test_enable_single__priority_2 ()
        {
            var providers = new Ft.ProviderSet<AntiGravityProvider> (Ft.SelectionMode.SINGLE);
            providers.provider_enabled.connect (() => { this.quit_main_loop (); });

            var provider_high = new SimpleAntiGravityProvider (Scenario.UNAVAILABLE);
            providers.add (provider_high, Ft.Priority.HIGH);

            var provider_low = new SimpleAntiGravityProvider (Scenario.AVAILABLE);
            providers.add (provider_low, Ft.Priority.LOW);

            providers.enable ();

            assert_true (this.run_main_loop ());

            assert_true (provider_low.available);
            assert_true (provider_low.enabled);
            assert_cmpuint (provider_low.initialize_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_low.enable_count, GLib.CompareOperator.EQ, 1);

            assert_true (provider_high.available_set);
            assert_false (provider_high.available);
            assert_false (provider_high.enabled);
            assert_cmpuint (provider_high.enable_count, GLib.CompareOperator.EQ, 0);
        }

        public void test_enable_single__priority_3 ()
        {
            var providers = new Ft.ProviderSet<AntiGravityProvider> (Ft.SelectionMode.SINGLE);
            providers.provider_enabled.connect (() => { this.quit_main_loop (); });

            var provider_high = new SimpleAntiGravityProvider (Scenario.UNAVAILABLE);
            providers.add (provider_high, Ft.Priority.HIGH);

            var provider_default = new SimpleAntiGravityProvider (Scenario.NO_AVAILABILITY_REPORTED);
            providers.add (provider_default, Ft.Priority.DEFAULT);

            var provider_low = new SimpleAntiGravityProvider (Scenario.AVAILABLE);
            providers.add (provider_low, Ft.Priority.LOW);

            providers.enable ();

            assert_true (this.run_main_loop ());

            assert_true (provider_low.available);
            assert_true (provider_low.enabled);
            assert_cmpuint (provider_low.initialize_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_low.enable_count, GLib.CompareOperator.EQ, 1);

            assert_false (provider_default.enabled);
            assert_cmpuint (provider_default.initialize_count, GLib.CompareOperator.EQ, 1);
        }

        public void test_enable_single__async_available ()
        {
            var providers = new Ft.ProviderSet<AntiGravityProvider> (Ft.SelectionMode.SINGLE);
            providers.provider_enabled.connect (() => { this.quit_main_loop (); });

            var provider_low = new SimpleAntiGravityProvider (Scenario.AVAILABLE);
            providers.add (provider_low, Ft.Priority.LOW);
            assert_cmpuint (provider_low.initialize_count, GLib.CompareOperator.EQ, 0);

            var provider_high = new SimpleAntiGravityProvider (Scenario.ASYNC_AVAILABLE);
            providers.add (provider_high, Ft.Priority.HIGH);
            assert_cmpuint (provider_high.initialize_count, GLib.CompareOperator.EQ, 0);

            providers.enable ();
            assert_true (this.run_main_loop ());

            assert_true (provider_high.available_set);
            assert_true (provider_high.available);
            assert_true (provider_high.enabled);
            assert_cmpuint (provider_high.initialize_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_high.enable_count, GLib.CompareOperator.EQ, 1);

            assert_false (provider_low.available_set);
            assert_false (provider_low.available);
            assert_false (provider_low.enabled);
            assert_cmpuint (provider_low.initialize_count, GLib.CompareOperator.EQ, 0);
            assert_cmpuint (provider_low.enable_count, GLib.CompareOperator.EQ, 0);
        }

        public void test_destroy ()
        {
            var providers = new Ft.ProviderSet<AntiGravityProvider> (Ft.SelectionMode.SINGLE);
            providers.provider_enabled.connect (() => { this.quit_main_loop (); });

            var provider_low = new SimpleAntiGravityProvider (Scenario.AVAILABLE);
            providers.add (provider_low, Ft.Priority.LOW);

            providers.enable ();
            assert_true (this.run_main_loop ());

            var provider_high = new SimpleAntiGravityProvider (Scenario.AVAILABLE);
            providers.add (provider_high, Ft.Priority.HIGH);
            assert_true (this.run_main_loop ());

            providers = null;

            var context = GLib.MainContext.default ();
            while (context.iteration (false)) {
            }

            assert_false (provider_low.enabled);
            assert_cmpuint (provider_low.disable_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_low.uninitialize_count, GLib.CompareOperator.EQ, 1);

            assert_false (provider_high.enabled);
            assert_cmpuint (provider_high.disable_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (provider_high.uninitialize_count, GLib.CompareOperator.EQ, 1);
        }
    }
}


public static int main (string[] args)
{
    Tests.init (args);

    return Tests.run (
        new Tests.ProviderSetTest ()
    );
}
