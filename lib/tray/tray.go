package tray

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5/introspect"
)

type ToolTip struct {
	IconName    string
	IconPixmap  []Pixmap
	Title       string
	Description string
}

func (t *ToolTip) FromDBus(v any) {
	if v == nil {
		return
	}
	v_ := v.([]any)
	t.IconName = v_[0].(string)
	t.IconPixmap = StorePixmap(v_[1])
	t.Title = v_[2].(string)
	t.Description = v_[3].(string)
}

type Category string

const (
	ApplicationStatus Category = "ApplicationStatus"
	Communications    Category = "Communications"
	SystemServices    Category = "SystemServices"
	Hardware          Category = "Hardware"
)

type Status string

const (
	Passive        Status = "Passive"
	Active         Status = "Active"
	NeedsAttention Status = "NeedsAttention"
)

type Pixmap struct {
	Width  int32
	Height int32
	Bytes  []byte
}

func StorePixmap(data any) []Pixmap {
	if data == nil {
		return nil
	}
	data_ := data.([][]any)
	pixmaps := make([]Pixmap, 0, len(data_))
	for _, p := range data_ {
		pixmap := Pixmap{
			Width:  p[0].(int32),
			Height: p[1].(int32),
			Bytes:  p[2].([]byte),
		}
		pixmaps = append(pixmaps, pixmap)
	}
	return pixmaps
}

func Store(v dbus.Variant, ptr any) {
	data := v.Value()
	if data == nil {
		return
	}
	v.Store(ptr)
}

type StatusNotifierItem struct {
	bus                 dbus.BusObject
	AttentionIconName   string
	AttentionIconPixmap []Pixmap
	AttentionMovieName  string
	Category            Category
	IconName            string
	IconPixmap          []Pixmap
	IconThemePath       string
	Id                  string
	ItemIsMenu          bool
	Menu                dbus.ObjectPath
	OverlayIconName     string
	OverlayIconPixmap   []Pixmap
	Status              Status
	Title               string
	ToolTip             ToolTip
	WindowId            int32
}

func (i *StatusNotifierItem) getAllProperty() (map[string]dbus.Variant, error) {
	var props map[string]dbus.Variant
	err := i.bus.Call("org.freedesktop.DBus.Properties.GetAll", 0, "org.kde.StatusNotifierItem").Store(&props)
	if err != nil {
		return nil, err
	}
	return props, nil
}

func (i *StatusNotifierItem) update() {
	props, err := i.getAllProperty()
	if err != nil {
		return
	}
	for k, v := range props {
		switch k {
		case "AttentionIconName":
			Store(v, &i.AttentionIconName)
		case "AttentionIconPixmap":
			i.AttentionIconPixmap = StorePixmap(v.Value())
		case "AttentionMovieName":
			Store(v, &i.AttentionMovieName)
		case "Category":
			Store(v, &i.Category)
		case "IconName":
			Store(v, &i.IconName)
		case "IconPixmap":
			i.IconPixmap = StorePixmap(v.Value())
		case "IconThemePath":
			Store(v, &i.IconThemePath)
		case "Id":
			Store(v, &i.Id)
		case "ItemIsMenu":
			Store(v, &i.ItemIsMenu)
		case "Menu":
			Store(v, &i.Menu)
		case "OverlayIconName":
			Store(v, &i.OverlayIconName)
		case "OverlayIconPixmap":
			i.OverlayIconPixmap = StorePixmap(v.Value())
		case "Status":
			Store(v, &i.Status)
		case "Title":
			Store(v, &i.Title)
		case "ToolTip":
			i.ToolTip.FromDBus(v.Value())
		case "WindowId":
			Store(v, &i.WindowId)
		}
	}
}

func (i *StatusNotifierItem) Activate(x, y int32) {
	i.bus.Call("org.kde.StatusNotifierItem.Activate", dbus.FlagNoReplyExpected, x, y)
}

func (i *StatusNotifierItem) ContextMenu(x, y int32) {
	i.bus.Call("org.kde.StatusNotifierItem.ContextMenu", dbus.FlagNoReplyExpected, x, y)
}

func (i *StatusNotifierItem) ProvideXdgActivationToken(token string) {
	i.bus.Call("org.kde.StatusNotifierItem.ProvideXdgActivationToken", dbus.FlagNoReplyExpected, token)
}

func (i *StatusNotifierItem) Scroll(delta int32, orientation string) {
	i.bus.Call("org.kde.StatusNotifierItem.Scroll", dbus.FlagNoReplyExpected, delta, orientation)
}

func (i *StatusNotifierItem) SecondaryActivate(x, y int32) {
	i.bus.Call("org.kde.StatusNotifierItem.SecondaryActivate", dbus.FlagNoReplyExpected, x, y)
}

func NewItem(conn *dbus.Conn, service, path string) *StatusNotifierItem {
	path_ := filepath.Join(path, "StatusNotifierItem")
	bus := conn.Object(service, dbus.ObjectPath(path_))
	item := &StatusNotifierItem{bus: bus}
	item.update()
	return item
}

type StatusNotifierWatcher struct {
	conn     *dbus.Conn
	Items    map[string]*StatusNotifierItem
	mutex    sync.Mutex
	ctx      context.Context
	cancel   context.CancelFunc
	listener []func()
}

func (w *StatusNotifierWatcher) Close() {
	w.conn.Close()
	w.cancel()
}

func (w *StatusNotifierWatcher) AddListener(handler func()) {
	w.listener = append(w.listener, handler)
}

func (w *StatusNotifierWatcher) RegisterStatusNotifierItem(service string, sender dbus.Sender) *dbus.Error {
	w.mutex.Lock()
	defer w.mutex.Unlock()
	serviceSpl := strings.Split(service, "/")
	service_ := serviceSpl[0]
	path := "/"
	if len(serviceSpl) > 1 {
		path += path + strings.Join(serviceSpl[1:], "/")
	}
	w.Items[service] = NewItem(w.conn, service_, path)
	return nil
}

func (w *StatusNotifierWatcher) Get(iface, property string) (dbus.Variant, *dbus.Error) {
	switch property {
	case "ProtocolVersion":
		return dbus.MakeVariant(0), nil
	case "RegisteredStatusNotifierItems":
		w.mutex.Lock()
		defer w.mutex.Unlock()
		keys := make([]string, 0, len(w.Items))
		for k := range w.Items {
			keys = append(keys, k+"/StatusNotifierItem")
		}
		return dbus.MakeVariant(keys), nil
	case "IsStatusNotifierHostRegistered":
		return dbus.MakeVariant(true), nil
	default:
		return dbus.MakeVariant(nil), nil
	}
}
func (w *StatusNotifierWatcher) GetAll(iface string) (map[string]dbus.Variant, *dbus.Error) {
	props := make(map[string]dbus.Variant)
	registeredStatusNotifierItems, err := w.Get(iface, "RegisteredStatusNotifierItems")
	if err != nil {
		return nil, err
	}
	props["RegisteredStatusNotifierItems"] = registeredStatusNotifierItems
	props["ProtocolVersion"] = dbus.MakeVariant(0)
	props["IsStatusNotifierHostRegistered"] = dbus.MakeVariant(true)
	return props, nil
}

func (w *StatusNotifierWatcher) Set(iface, property string, value dbus.Variant) *dbus.Error {
	return nil
}

func New() (*StatusNotifierWatcher, error) {
	conn, err := dbus.SessionBus()
	if err != nil {
		return nil, err
	}

	reply, err := conn.RequestName("org.kde.StatusNotifierWatcher", dbus.NameFlagDoNotQueue)
	if err != nil || reply != dbus.RequestNameReplyPrimaryOwner {
		return nil, fmt.Errorf("failed to request name, is there another process registered tray? err: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	watcher := &StatusNotifierWatcher{
		conn:   conn,
		Items:  make(map[string]*StatusNotifierItem),
		cancel: cancel,
		ctx:    ctx,
	}

	conn.Export(watcher, "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher")
	conn.Export(watcher, "/StatusNotifierWatcher", "org.freedesktop.DBus.Properties")
	node := &introspect.Node{
		Name: "/StatusNotifierWatcher",
		Interfaces: []introspect.Interface{
			introspect.IntrospectData,
			{
				Name: "org.kde.StatusNotifierWatcher",
				Properties: []introspect.Property{
					{Name: "ProtocolVersion", Type: "i", Access: "read"},
					{Name: "RegisteredStatusNotifierItems", Type: "as", Access: "read"},
					{Name: "IsStatusNotifierHostRegistered", Type: "b", Access: "read"},
				},
				Methods: []introspect.Method{
					{Name: "RegisterStatusNotifierItem", Args: []introspect.Arg{
						{Name: "service", Type: "s", Direction: "in"},
					}},
					{Name: "RegisterStatusNotifierHost", Args: []introspect.Arg{
						{Name: "service", Type: "s", Direction: "in"},
					}},
				},
				Signals: []introspect.Signal{
					{Name: "StatusNotifierItemRegistered", Args: []introspect.Arg{{Type: "s"}}},
					{Name: "StatusNotifierItemUnregistered", Args: []introspect.Arg{{Type: "s"}}},
					{Name: "StatusNotifierHostRegistered"},
					{Name: "StatusNotifierHostUnregistered"},
				},
			},
		},
	}

	conn.Export(introspect.NewIntrospectable(node), "/StatusNotifierWatcher",
		"org.freedesktop.DBus.Introspectable")
	// 监听StatusNotifierItem信号
	signals := []string{
		"NewAttentionIcon", "NewIcon", "NewMenu",
		"NewOverlayIcon", "NewStatus", "NewTitle", "NewToolTip",
	}
	for _, signal := range signals {
		conn.AddMatchSignal(dbus.WithMatchInterface("org.kde.StatusNotifierItem"), dbus.WithMatchMember(signal))
	}

	// 监听NameOwnerChanged信号以检测服务断开
	conn.AddMatchSignal(
		dbus.WithMatchInterface("org.freedesktop.DBus"),
		dbus.WithMatchMember("NameOwnerChanged"),
		dbus.WithMatchArg(2, ""),
	)
	// TODO: 优化性能
	go func(watcher *StatusNotifierWatcher) {
		ch := make(chan *dbus.Signal)
		conn.Signal(ch)
		defer conn.RemoveSignal(ch)
		needUpdate := make(map[string]struct{})
		const duration = 50 * time.Millisecond
		timer := time.NewTimer(duration)
		timer.Stop()
		defer timer.Stop()
		for {
			select {
			case <-watcher.ctx.Done():
				conn.RemoveSignal(ch)
				return
			case <-timer.C:
				for k := range needUpdate {
					if watcher.Items[k] != nil {
						watcher.Items[k].update()
					}
				}
				needUpdate = make(map[string]struct{})
				for _, handler := range watcher.listener {
					if handler != nil {
						handler()
					}
				}
			case signal := <-ch:
				if signal.Name == "org.freedesktop.DBus.NameOwnerChanged" {
					oldOwner := signal.Body[1].(string)
					if _, exists := watcher.Items[oldOwner]; exists {
						delete(watcher.Items, oldOwner)
						conn.Emit("/StatusNotifierWatcher",
							"org.kde.StatusNotifierWatcher.StatusNotifierItemUnregistered",
							oldOwner)
						conn.Emit("/StatusNotifierWatcher",
							"org.kde.StatusNotifierWatcher.StatusNotifierItemUnregistered",
							oldOwner)
					}
				} else {
					_, ok := watcher.Items[signal.Sender]
					if ok {
						needUpdate[signal.Sender] = struct{}{}
					}
				}
				timer.Reset(duration)
			}
		}
	}(watcher)
	return watcher, nil
}
