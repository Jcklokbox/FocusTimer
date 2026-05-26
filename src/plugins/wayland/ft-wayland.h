/*
 * Copyright (c) 2026 focus-timer contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#pragma once

#include <glib.h>
#include <wayland-client.h>

G_BEGIN_DECLS

typedef struct _FtWaylandIdleMonitor FtWaylandIdleMonitor;

typedef void (*FtWaylandIdleMonitorCallback) (uint32_t id, gpointer user_data);

FtWaylandIdleMonitor *ft_wayland_idle_monitor_new (struct wl_display *display,
                                                   struct wl_seat    *seat);
FtWaylandIdleMonitor *ft_wayland_idle_monitor_ref (FtWaylandIdleMonitor *monitor);
void                  ft_wayland_idle_monitor_unref (FtWaylandIdleMonitor *monitor);
void                  ft_wayland_idle_monitor_free (FtWaylandIdleMonitor *monitor);

gboolean ft_wayland_idle_monitor_is_ready (FtWaylandIdleMonitor *monitor);
gboolean ft_wayland_idle_monitor_supports_input_idle (FtWaylandIdleMonitor *monitor);

uint32_t ft_wayland_idle_monitor_add_notification (FtWaylandIdleMonitor        *monitor,
                                                   uint32_t                     timeout_ms,
                                                   FtWaylandIdleMonitorCallback on_idled,
                                                   FtWaylandIdleMonitorCallback on_resumed,
                                                   gpointer                     user_data);
uint32_t ft_wayland_idle_monitor_add_input_notification (FtWaylandIdleMonitor        *monitor,
                                                         uint32_t                     timeout_ms,
                                                         FtWaylandIdleMonitorCallback on_idled,
                                                         FtWaylandIdleMonitorCallback on_resumed,
                                                         gpointer                     user_data);
void     ft_wayland_idle_monitor_remove_notification (FtWaylandIdleMonitor *monitor,
                                                      uint32_t               id);

G_END_DECLS
