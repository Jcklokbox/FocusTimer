/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

[CCode (cheader_filename = "ft-wayland.h")]
namespace FtWayland
{
    [CCode (has_target = false)]
    public delegate void IdleMonitorCallback (uint32 id, void* user_data);

    public class IdleMonitor
    {
        public IdleMonitor (Wl.Display display,
                            Wl.Seat    seat);

        public bool is_ready ();
        public bool supports_input_idle ();

        public uint32 add_notification (uint32               timeout_ms,
                                        IdleMonitorCallback? on_idled,
                                        IdleMonitorCallback? on_resumed,
                                        void*                user_data);

        public uint32 add_input_notification (uint32               timeout_ms,
                                              IdleMonitorCallback? on_idled,
                                              IdleMonitorCallback? on_resumed,
                                              void*                user_data);

        public void remove_notification (uint32 id);
    }
}
