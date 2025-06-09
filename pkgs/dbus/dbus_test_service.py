#!/usr/bin/env python3

from pydbus import SessionBus, Variant  # type: ignore
from gi.repository import GLib  # type: ignore
from dbus import DBusException
from pydbus.generic import signal
import logging

logging.disable()


class TestServices(object):
    """
    <node>
            <interface name="com.example.TestService">
                    <method name="GetByte">
                            <arg direction="out" type="y"/>
                    </method>
                    <method name="GetBoolean">
                            <arg direction="out" type="b"/>
                    </method>
                    <method name="GetInt16">
                            <arg direction="out" type="n"/>
                    </method>
                    <method name="GetUInt16">
                            <arg direction="out" type="q"/>
                    </method>
                    <method name="GetInt32">
                            <arg direction="out" type="i"/>
                    </method>
                    <method name="GetUInt32">
                            <arg direction="out" type="u"/>
                    </method>
                    <method name="GetInt64">
                            <arg direction="out" type="x"/>
                    </method>
                    <method name="GetUInt64">
                            <arg direction="out" type="t"/>
                    </method>
                    <method name="GetDouble">
                            <arg direction="out" type="d"/>
                    </method>
                    <method name="GetObjectPath">
                            <arg direction="out" type="o"/>
                    </method>
                    <method name="GetString">
                            <arg direction="out" type="s"/>
                    </method>
                    <method name="GetSignature">
                            <arg direction="out" type="g"/>
                    </method>
                    <method name="GetArrayString">
                            <arg direction="out" type="as"/>
                    </method>
                    <method name="GetArrayVariant">
                            <arg direction="out" type="av"/>
                    </method>
                    <method name="GetStruct">
                            <arg direction="out" type="(xb)"/>
                    </method>
                        <method name="GetVariant">
                            <arg direction="out" type="v"/>
                    </method>
                    <method name="GetNothing"></method>
                    <method name="GetError"></method>
                    <method name="GetDict1">
                            <arg direction="out" type="a{si}"/>
                    </method>
                    <method name="GetDict2">
                            <arg direction="out" type="a{ii}"/>
                    </method>
                    <method name="CallAdd">
                            <arg direction="in" type="i"/>
                            <arg direction="in" type="i"/>
                            <arg direction="out" type="i"/>
                    </method>
                    <method name="CallWithStringArray">
                            <arg direction="in" type="as"/>
                            <arg direction="out" type="s"/>
                    </method>
                    <method name="CallWithVariant">
                            <arg direction="in" type="v"/>
                            <arg direction="out" type="b"/>
                    </method>
                    <method name="CallWithDict">
                            <arg direction="in" type="a{ss}"/>
                            <arg direction="out" type="b"/>
                    </method>
                    <method name="CallWithStruct">
                            <arg direction="in" type="(sib)"/>
                            <arg direction="out" type="b"/>
                    </method>
                    <method name="GetDict3">
                            <arg direction="out" type="a{sv}"/>
                    </method>
                    <signal name="Signal1">
                            <arg type="s"/>
                            <arg type="i"/>
                    </signal>
                    <property name="Byte" type="y" access="read"/>
                    <property name="Boolean" type="b" access="write"/>
                    <property name="Int16" type="n" access="readwrite"/>
            </interface>
    </node>
    """

    def __init__(self) -> None:
        super().__init__()
        GLib.timeout_add(100, self._emit_signal1)

    def _emit_signal1(self):
        self.Signal1.emit("TestSignal", 78787)
        return True

    def GetByte(self):
        return 123

    def GetBoolean(self):
        return True

    def GetInt16(self):
        return -32768

    def GetUInt16(self):
        return 65535

    def GetInt32(self):
        return -2147483648

    def GetUInt32(self):
        return 4294967295

    def GetInt64(self):
        return -9223372036854775808

    def GetUInt64(self):
        return 18446744073709551615

    def GetDouble(self):
        return 3.141592653589793

    def GetObjectPath(self):
        return "/com/example/DBusObject"

    def GetString(self):
        return "Hello from DBus Service!"

    def GetSignature(self):
        return "as"

    def GetArrayString(self):
        return ["foo", "bar", "baz"]

    def GetArrayVariant(self):
        return [Variant("s", "foo"), Variant("i", 123), Variant("b", True)]

    def GetStruct(self):
        return (-1234567890, True)

    def GetVariant(self):
        return Variant("i", 123)

    def GetNothing(self):
        return

    def GetDict1(self):
        return {"key1": 1, "key2": 2, "key3": 3}

    def GetDict2(self):
        return {1: 1, 2: 2, 3: 3}

    def GetDict3(self):
        return {"name": Variant("s", "foo"), "home": Variant("i", 489)}

    def GetError(self):
        raise DBusException("ATestError")

    def CallAdd(self, a, b):
        return a + b

    def CallWithStringArray(self, strings):
        return " ".join(strings)

    def CallWithVariant(self, variant):
        return variant == 114514

    def CallWithDict(self, data):
        return data.get("name") == "foo" and data.get("home") == "bar"

    def CallWithStruct(self, data):
        return data[0] == "foo" and data[1] == 123 and data[2] == True

    @property
    def Byte(self):
        return 123

    @Byte.setter
    def Byte(self, value):
        print("Byte set to", value)

    @property
    def Boolean(self):
        return True

    @Boolean.setter
    def Boolean(self, value):
        pass

    property_int16 = -32768

    @property
    def Int16(self):
        return self.property_int16

    @Int16.setter
    def Int16(self, value):
        self.property_int16 = value

    PropertiesChanged = signal()
    Signal1 = signal()


if __name__ == "__main__":
    # 设置主循环
    bus = SessionBus()
    bus.publish("com.example.MikaShell", TestServices())

    loop = GLib.MainLoop()
    try:
        loop.run()
    except KeyboardInterrupt:
        pass
