#include <dbus/dbus.h>
DBusError *dbus_error_new(void);
void dbus_error_destroy(DBusError *err);
void dbus_error_reset(DBusError *err);
const char *dbus_error_get_name(DBusError *err);
const char *dbus_error_get_message(DBusError *err);
