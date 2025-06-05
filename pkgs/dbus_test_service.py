#!/usr/bin/env python3

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib  # type: ignore
import uuid
import time


class ExampleDBusService(dbus.service.Object):
    """
    一个示例 DBus 服务，展示各种 DBus 功能
    """

    def __init__(self, bus_name):
        super().__init__(bus_name, "/com/example/DBusService")
        GLib.timeout_add_seconds(2, self._send_periodic_signal)

    @dbus.service.method("com.example.DBusService", in_signature="", out_signature="y")
    def GetByte(self):
        return dbus.Byte(123)

    @dbus.service.method("com.example.DBusService", in_signature="", out_signature="b")
    def GetBoolean(self):
        return dbus.Boolean(True)

    @dbus.service.method("com.example.DBusService", in_signature="", out_signature="n")
    def GetInt16(self):
        return dbus.Int16(-32768)

    @dbus.service.method("com.example.DBusService", in_signature="", out_signature="q")
    def GetUInt16(self):
        return dbus.UInt16(65535)

    @dbus.service.method("com.example.DBusService", in_signature="", out_signature="i")
    def GetInt32(self):
        return dbus.Int32(-2147483648)

    @dbus.service.method("com.example.DBusService", in_signature="", out_signature="u")
    def GetUInt32(self):
        return dbus.UInt32(4294967295)

    @dbus.service.method("com.example.DBusService", in_signature="", out_signature="x")
    def GetInt64(self):
        return dbus.Int64(-9223372036854775808)

    @dbus.service.method("com.example.DBusService", in_signature="", out_signature="t")
    def GetUInt64(self):
        return dbus.UInt64(18446744073709551615)

    @dbus.service.method("com.example.DBusService", in_signature="", out_signature="d")
    def GetDouble(self):
        return dbus.Double(3.141592653589793)

    @dbus.service.method("com.example.DBusService", in_signature="", out_signature="o")
    def GetObjectPath(self):
        return dbus.ObjectPath("/com/example/DBusObject")

    @dbus.service.method("com.example.DBusService", in_signature="", out_signature="s")
    def GetString(self):
        return "Hello from DBus Service!"

    @dbus.service.method("com.example.DBusService", in_signature="", out_signature="g")
    def GetSignature(self):
        return dbus.Signature("as")

    @dbus.service.method("com.example.DBusService", in_signature="", out_signature="as")
    def GetArrayString(self):
        return dbus.Array(["foo", "bar", "baz"], signature="s")

    @dbus.service.method(
        "com.example.DBusService", in_signature="", out_signature="(xb)"
    )
    def GetStruct(self):
        return dbus.Struct(
            (dbus.Int64(-1234567890), dbus.Boolean(True)), signature="(xb)"
        )

    @dbus.service.method("com.example.DBusService", in_signature="", out_signature="v")
    def GetVariant(self):
        return dbus.Int32(123)

    @dbus.service.method("com.example.DBusService", in_signature="", out_signature="")
    def GetNothing(self):
        return

    @dbus.service.method(
        "com.example.DBusService", in_signature="", out_signature="a{si}"
    )
    def GetDict1(self):
        return dbus.Dictionary(
            {
                "key1": dbus.Int32(1),
                "key2": dbus.Int32(2),
                "key3": dbus.Int32(3),
            }
        )

    @dbus.service.method(
        "com.example.DBusService", in_signature="", out_signature="a{ii}"
    )
    def GetDict2(self):
        return dbus.Dictionary(
            {
                1: dbus.Int32(1),
                2: dbus.Int32(2),
                3: dbus.Int32(3),
            }
        )

    @dbus.service.signal("com.example.DBusService", signature="a{sv}")
    def DataSignal(self, data):
        pass

    def _send_periodic_signal(self):
        self.DataSignal(
            {
                "timestamp": dbus.UInt64(int(time.time())),
                "message": dbus.String("Periodic update"),
            }
        )
        return True  # 保持定时器运行


if __name__ == "__main__":
    # 设置主循环
    DBusGMainLoop(set_as_default=True)

    # 获取系统总线
    bus = dbus.SessionBus()

    try:
        # 请求总线名称
        bus_name = dbus.service.BusName("com.example.DBusService", bus)

        # 创建服务对象
        service = ExampleDBusService(bus_name)

        print("DBus service is running...")

        # 运行主循环
        loop = GLib.MainLoop()
        loop.run()

    except dbus.exceptions.NameExistsException:
        print("Service is already running")
    except KeyboardInterrupt:
        print("Shutting down service")
    except Exception as e:
        print(f"Error: {e}")
