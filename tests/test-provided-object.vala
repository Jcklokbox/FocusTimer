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
        public abstract string name { get; construct set; }
        public abstract Scenario scenario { get; construct set; }
    }


    public class SimpleAntiGravityProvider : Ft.Provider, AntiGravityProvider
    {
        public string name { get; construct set; default = ""; }
        public Scenario scenario { get; construct set; default = Scenario.AVAILABLE; }

        public uint initialize_count = 0;
        public uint uninitialize_count = 0;
        public uint enable_count = 0;
        public uint disable_count = 0;

        public SimpleAntiGravityProvider (string   name,
                                          Scenario scenario = Scenario.AVAILABLE)
        {
            GLib.Object (
                name: name,
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


    public class AntiGravity : Ft.ProvidedObject<AntiGravityProvider>
    {
        public uint enabled_count = 0;
        public uint disabled_count = 0;

        public AntiGravity ()
        {
        }

        public void add_provider (string      name,
                                  Scenario    scenario,
                                  Ft.Priority priority = Ft.Priority.DEFAULT)
        {
            this.providers.add (new SimpleAntiGravityProvider (name, scenario), priority);
        }

        protected override void initialize ()
        {
        }

        protected override void setup_providers ()
        {
        }

        protected override void provider_enabled (AntiGravityProvider provider)
        {
            this.enabled_count++;
        }

        protected override void provider_disabled (AntiGravityProvider provider)
        {
            this.disabled_count++;
        }
    }


    public class ProvidedObjectTest : Tests.TestSuite
    {
        private GLib.MainLoop? main_loop = null;
        private uint           timeout_id = 0;

        public ProvidedObjectTest ()
        {
            this.add_test ("available", this.test_available);
            this.add_test ("unavailable_1", this.test_unavailable_1);
            this.add_test ("unavailable_2", this.test_unavailable_2);
            this.add_test ("delayed_unavailable_1", this.test_delayed_unavailable_1);
            this.add_test ("delayed_unavailable_2", this.test_delayed_unavailable_2);
            this.add_test ("no_availability_reported", this.test_no_availability_reported);
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

        public void test_available ()
        {
            var anti_gravity = new AntiGravity ();
            anti_gravity.notify["enabled"].connect (() => { this.quit_main_loop (); });
            anti_gravity.add_provider ("", Scenario.AVAILABLE);

            assert_true (this.run_main_loop ());

            assert_true (anti_gravity.available);
            assert_true (anti_gravity.enabled);
            assert_nonnull (anti_gravity.provider);
            assert_true (anti_gravity.provider.available);
            assert_true (anti_gravity.provider.enabled);

            assert_cmpuint (anti_gravity.enabled_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (anti_gravity.disabled_count, GLib.CompareOperator.EQ, 0);
        }

        public void test_unavailable_1 ()
        {
            var anti_gravity = new AntiGravity ();
            anti_gravity.add_provider ("", Scenario.UNAVAILABLE);
            assert_null (anti_gravity.provider);
            assert_false (anti_gravity.available);

            assert_cmpuint (anti_gravity.enabled_count, GLib.CompareOperator.EQ, 0);
            assert_cmpuint (anti_gravity.disabled_count, GLib.CompareOperator.EQ, 0);
        }

        public void test_unavailable_2 ()
        {
            var anti_gravity = new AntiGravity ();
            anti_gravity.add_provider ("high", Scenario.UNAVAILABLE, Ft.Priority.HIGH);
            anti_gravity.add_provider ("low", Scenario.AVAILABLE, Ft.Priority.LOW);
            anti_gravity.notify["enabled"].connect (() => { this.quit_main_loop (); });

            assert_true (this.run_main_loop ());

            assert_true (anti_gravity.available);
            assert_true (anti_gravity.enabled);

            assert_nonnull (anti_gravity.provider);
            assert_cmpstr (anti_gravity.provider.name, GLib.CompareOperator.EQ, "low");
            assert_true (anti_gravity.provider.available);
            assert_true (anti_gravity.provider.enabled);

            assert_cmpuint (anti_gravity.enabled_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (anti_gravity.disabled_count, GLib.CompareOperator.EQ, 0);
        }

        public void test_delayed_unavailable_1 ()
        {
            var anti_gravity = new AntiGravity ();
            anti_gravity.add_provider ("high", Scenario.DELAYED_UNAVAILABLE, Ft.Priority.HIGH);
            anti_gravity.add_provider ("low", Scenario.AVAILABLE, Ft.Priority.LOW);
            anti_gravity.notify["enabled"].connect (() => { this.quit_main_loop (); });

            assert_true (this.run_main_loop ());

            assert_true (anti_gravity.available);
            assert_true (anti_gravity.enabled);

            assert_nonnull (anti_gravity.provider);
            assert_cmpstr (anti_gravity.provider.name, GLib.CompareOperator.EQ, "low");
            assert_true (anti_gravity.provider.available);
            assert_true (anti_gravity.provider.enabled);

            assert_cmpuint (anti_gravity.enabled_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (anti_gravity.disabled_count, GLib.CompareOperator.EQ, 0);
        }

        public void test_delayed_unavailable_2 ()
        {
            var anti_gravity = new AntiGravity ();
            anti_gravity.add_provider ("low", Scenario.AVAILABLE, Ft.Priority.LOW);
            anti_gravity.add_provider ("default", Scenario.DELAYED_AVAILABLE, Ft.Priority.DEFAULT);
            anti_gravity.add_provider ("high", Scenario.UNAVAILABLE, Ft.Priority.HIGH);
            anti_gravity.notify["enabled"].connect (() => { this.quit_main_loop (); });

            assert_true (this.run_main_loop ());

            assert_true (anti_gravity.available);
            assert_true (anti_gravity.enabled);

            assert_nonnull (anti_gravity.provider);
            assert_cmpstr (anti_gravity.provider.name, GLib.CompareOperator.EQ, "default");
            assert_true (anti_gravity.provider.available);
            assert_true (anti_gravity.provider.enabled);

            assert_cmpuint (anti_gravity.enabled_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (anti_gravity.disabled_count, GLib.CompareOperator.EQ, 0);
        }

        public void test_no_availability_reported ()
        {
            var anti_gravity = new AntiGravity ();
            anti_gravity.add_provider ("high", Scenario.NO_AVAILABILITY_REPORTED, Ft.Priority.HIGH);
            anti_gravity.add_provider ("low", Scenario.AVAILABLE, Ft.Priority.LOW);

            anti_gravity.notify["enabled"].connect (() => { this.quit_main_loop (); });

            assert_true (this.run_main_loop ());

            assert_true (anti_gravity.available);
            assert_true (anti_gravity.enabled);

            assert_nonnull (anti_gravity.provider);
            assert_cmpstr (anti_gravity.provider.name, GLib.CompareOperator.EQ, "low");
            assert_true (anti_gravity.provider.available);
            assert_true (anti_gravity.provider.enabled);

            assert_cmpuint (anti_gravity.enabled_count, GLib.CompareOperator.EQ, 1);
            assert_cmpuint (anti_gravity.disabled_count, GLib.CompareOperator.EQ, 0);
        }
    }
}


public static int main (string[] args)
{
    Tests.init (args);

    return Tests.run (
        new Tests.ProvidedObjectTest ()
    );
}
