#include <dbus/dbus.h>
#include <stdlib.h>
DBusError *dbus_error_new(void)
{
    DBusError *err = malloc(sizeof(DBusError));
    dbus_error_init(err);
    return err;
}

void dbus_error_destroy(DBusError *err)
{
    dbus_error_free(err);
    free(err);
}

const char *dbus_error_get_name(DBusError *err)
{
    return err->name;
}

const char *dbus_error_get_message(DBusError *err)
{
    return err->message;
}
