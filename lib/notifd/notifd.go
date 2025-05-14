package notifd

import (
	"fmt"

	"slices"

	"github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5/introspect"
)

type ImageData struct {
	Width         int32
	Height        int32
	Rowstride     int32
	HasAlpha      bool
	BitsPerSample int32
	Channels      int32
	ImageData     []byte
}
type Urgency byte

const (
	UrgencyLow Urgency = iota
	UrgencyNormal
	UrgencyCritical
)

type Hint string

const (
	HintActionIcons   Hint = "action-icons"   // bool
	HintCategory      Hint = "category"       // string
	HintDesktopEntry  Hint = "desktop-entry"  // string
	HintImageData     Hint = "image-data"     // ImageData
	HintImagePath     Hint = "image-path"     // string
	HintResident      Hint = "resident"       // bool
	HintSoundFile     Hint = "sound-file"     // string
	HintSoundName     Hint = "sound-name"     // string
	HintSuppressSound Hint = "suppress-sound" // bool
	HintTransient     Hint = "transient"      // bool
	HintX             Hint = "x"              // int32
	HintY             Hint = "y"              // int32
	HintUrgency       Hint = "urgency"        // Urgency
	HintSenderPID     Hint = "sender-pid"     // int64 并不在标准中
)

type Notification struct {
	Id            uint32
	AppName       string
	ReplacesId    uint32
	AppIcon       string
	Summary       string
	Body          string
	Actions       []string
	Hints         map[Hint]any
	ExpireTimeout uint32
}
type Notifyd struct {
	conn                *dbus.Conn
	Ns                  []Notification
	onNotify            func(Notification)
	onCloseNotification func(uint32)
	startId             uint32
}

func (n *Notifyd) CloseNotification(id uint32) *dbus.Error {
	for i, v := range n.Ns {
		if v.Id == id {
			n.Ns = slices.Delete(n.Ns, i, i+1)
			if n.onCloseNotification != nil {
				n.onCloseNotification(id)
			}
			n.NotificationClosed(id, 0)
			return nil
		}
	}
	return nil
}

func (n *Notifyd) GetCapabilities() ([]string, *dbus.Error) {
	return []string{
		"action-icons",
		"actions",
		"body",
		"body-hyperlinks",
		"body-images",
		"body-markup",
		"icon-multi",
		"icon-static",
		"persistence",
		"sound",
	}, nil
}

func (n *Notifyd) GetServerInformation() (name, vendor, version, spec_version string, err *dbus.Error) {
	return "notifd", "mikami", "0.1", "1.2", nil
}

func (n *Notifyd) Notify(
	app_name string,
	replaces_id uint32,
	app_icon string,
	summary string,
	body string,
	actions []string,
	hints map[string]dbus.Variant,
	expire_timeout uint32,
) (id uint32, err *dbus.Error) {
	n.startId++
	id = n.startId
	notification := Notification{
		Id:            id,
		AppName:       app_name,
		ReplacesId:    replaces_id,
		AppIcon:       app_icon,
		Summary:       summary,
		Body:          body,
		Actions:       actions,
		ExpireTimeout: expire_timeout,
		Hints:         make(map[Hint]any),
	}
	for k, v := range hints {
		if k == "image-data" {
			var imageData ImageData
			value := v.Value().([]any)
			imageData.Width = value[0].(int32)
			imageData.Height = value[1].(int32)
			imageData.Rowstride = value[2].(int32)
			imageData.HasAlpha = value[3].(bool)
			imageData.BitsPerSample = value[4].(int32)
			imageData.Channels = value[5].(int32)
			imageData.ImageData = value[6].([]byte)
			notification.Hints[HintImageData] = imageData
		} else {
			notification.Hints[Hint(k)] = v.Value()
		}
	}
	if notification.ReplacesId > 0 {
		for i, v := range n.Ns {
			if v.Id != notification.ReplacesId {
				continue
			}
			n.Ns[i] = notification
			return notification.ReplacesId, nil
		}
	}
	n.Ns = append(n.Ns, notification)
	if n.onNotify != nil {
		n.onNotify(notification)
	}
	return id, nil
}

func (n *Notifyd) ActionInvoked(id uint32, action_key string) *dbus.Error {
	n.conn.Emit("/org/freedesktop/Notifications", "org.freedesktop.Notifications.ActionInvoked", id, action_key)
	return nil
}

func (n *Notifyd) ActivationToken(id uint32, activation_token string) *dbus.Error {
	n.conn.Emit("/org/freedesktop/Notifications", "org.freedesktop.Notifications.ActivationToken", id, activation_token)
	return nil
}

func (n *Notifyd) NotificationClosed(id uint32, reason uint32) *dbus.Error {
	n.conn.Emit("/org/freedesktop/Notifications", "org.freedesktop.Notifications.NotificationClosed", id, reason)
	return nil
}

func (n *Notifyd) Close() {
	n.conn.Close()
}
func New(onNotify func(Notification), onCloseNotification func(uint32)) (*Notifyd, error) {
	conn, err := dbus.SessionBus()
	if err != nil {
		return nil, err
	}

	reply, err := conn.RequestName("org.freedesktop.Notifications", dbus.NameFlagDoNotQueue)
	if err != nil || reply != dbus.RequestNameReplyPrimaryOwner {
		return nil, fmt.Errorf("failed to request name, is there another process registered notifications? err:: %v", err)
	}
	notifyd := &Notifyd{conn: conn, onNotify: onNotify, onCloseNotification: onCloseNotification}
	conn.Export(notifyd, "/org/freedesktop/Notifications", "org.freedesktop.Notifications")
	node := &introspect.Node{
		Name: "/Notifications",
		Interfaces: []introspect.Interface{
			introspect.IntrospectData,
			{
				Name: "org.freedesktop.Notifications",
				Methods: []introspect.Method{
					{Name: "CloseNotification", Args: []introspect.Arg{
						{Name: "id", Type: "u", Direction: "in"},
					}},
					{Name: "GetCapabilities", Args: []introspect.Arg{
						{Name: "resulr", Type: "as", Direction: "out"},
					}},
					{Name: "GetServerInformation", Args: []introspect.Arg{
						{Name: "name", Type: "s", Direction: "out"},
						{Name: "vendor", Type: "s", Direction: "out"},
						{Name: "spec_version", Type: "s", Direction: "out"}, //1.2
					}},
					{Name: "Notify", Args: []introspect.Arg{
						{Name: "app_name", Type: "s", Direction: "in"},
						{Name: "replaces_id", Type: "u", Direction: "in"},
						{Name: "app_icon", Type: "s", Direction: "in"},
						{Name: "summary", Type: "s", Direction: "in"},
						{Name: "body", Type: "s", Direction: "in"},
						{Name: "actions", Type: "as", Direction: "in"},
						{Name: "hints", Type: "a{sv}", Direction: "in"}, // Vardict
						{Name: "expire_timeout", Type: "i", Direction: "in"},
						{Name: "result", Type: "u", Direction: "out"},
					}},
				},
				Signals: []introspect.Signal{
					{Name: "ActionInvoked", Args: []introspect.Arg{
						{Name: "id", Type: "u"},
						{Name: "action_key", Type: "s"},
					}},
					{Name: "ActivationToken", Args: []introspect.Arg{
						{Name: "id", Type: "u"},
						{Name: "activation_token", Type: "s"},
					}},
					{Name: "NotificationClosed", Args: []introspect.Arg{
						{Name: "id", Type: "u"},
						{Name: "reason", Type: "u"},
					}},
				},
			},
		},
	}

	conn.Export(introspect.NewIntrospectable(node), "/Notifications",
		"org.freedesktop.DBus.Introspectable")

	return notifyd, nil
}
