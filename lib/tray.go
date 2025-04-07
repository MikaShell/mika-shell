package lib

import (
	"bytes"
	"context"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"path/filepath"
	"strings"
	"sync"

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

func PixmapToPng(p Pixmap) []byte {
	img := image.NewNRGBA(image.Rect(0, 0, int(p.Width), int(p.Height)))

	for y := range int(p.Height) {
		for x := range int(p.Width) {
			i := (y*int(p.Width) + x) * 4
			if i+3 >= len(p.Bytes) {
				continue
			}
			a := p.Bytes[i]
			r := p.Bytes[i+1]
			g := p.Bytes[i+2]
			b := p.Bytes[i+3]
			img.Set(x, y, color.NRGBA{R: r, G: g, B: b, A: a})
		}
	}
	buf := new(bytes.Buffer)
	png.Encode(buf, img)
	return buf.Bytes()
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

func (i *StatusNotifierItem) getProperty(name string) (dbus.Variant, error) {
	return i.bus.GetProperty("org.kde.StatusNotifierItem." + name)
}
func (i *StatusNotifierItem) onNewAttentionIcon() {
	var v dbus.Variant
	v, _ = i.getProperty("AttentionIconName")
	Store(v, &i.AttentionIconName)
	v, _ = i.getProperty("AttentionPixmap")
	i.AttentionIconPixmap = StorePixmap(v.Value())
	v, _ = i.getProperty("AttentionMovieName")
	Store(v, &i.AttentionMovieName)
}

func (i *StatusNotifierItem) onNewIcon() {
	var v dbus.Variant
	v, _ = i.getProperty("IconName")
	Store(v, &i.IconName)
	v, _ = i.getProperty("IconPixmap")
	i.IconPixmap = StorePixmap(v.Value())
	v, _ = i.getProperty("IconThemePath")
	Store(v, &i.IconThemePath)
}

func (i *StatusNotifierItem) onNewMenu() {
	v, _ := i.getProperty("Menu")
	Store(v, &i.Menu)
}

func (i *StatusNotifierItem) onNewOverlayIcon() {
	var v dbus.Variant
	v, _ = i.getProperty("OverlayIconName")
	Store(v, &i.OverlayIconName)
	v, _ = i.getProperty("OverlayPixmap")
	i.OverlayIconPixmap = StorePixmap(v.Value())
}

func (i *StatusNotifierItem) onNewStatus() {
	v, _ := i.getProperty("Status")
	Store(v, &i.Status)
}

func (i *StatusNotifierItem) onNewTitle() {
	v, _ := i.getProperty("Title")
	Store(v, &i.Title)
}

func (i *StatusNotifierItem) onNewToolTip() {
	v, _ := i.getProperty("ToolTip")
	i.ToolTip.FromDBus(v.Value())
}

func (i *StatusNotifierItem) init() {
	var v dbus.Variant
	i.onNewAttentionIcon()
	i.onNewIcon()
	i.onNewMenu()
	i.onNewOverlayIcon()
	i.onNewStatus()
	i.onNewTitle()
	i.onNewToolTip()
	v, _ = i.getProperty("Category")
	Store(v, &i.Category)
	v, _ = i.getProperty("Id")
	Store(v, &i.Id)
	v, _ = i.getProperty("ItemIsMenu")
	Store(v, &i.ItemIsMenu)
	v, _ = i.getProperty("WindowId")
	Store(v, &i.WindowId)
}

func (i *StatusNotifierItem) handleSignal(signal *dbus.Signal) {
	switch strings.TrimPrefix(signal.Name, "org.kde.StatusNotifierItem.") {
	case "NewAttentionIcon":
		i.onNewAttentionIcon()
	case "NewIcon":
		i.onNewIcon()
	case "NewMenu":
		i.onNewMenu()
	case "NewOverlayIcon":
		i.onNewOverlayIcon()
	case "NewStatus":
		i.onNewStatus()
	case "NewTitle":
		i.onNewTitle()
	case "NewToolTip":
		i.onNewToolTip()
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
	go item.init()
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

func (w *StatusNotifierWatcher) RegisteredStatusNotifierItems() ([]string, *dbus.Error) {
	w.mutex.Lock()
	defer w.mutex.Unlock()
	keys := make([]string, 0, len(w.Items))
	for k := range w.Items {
		keys = append(keys, k+"/StatusNotifierItem")
	}
	return keys, nil
}

func (w *StatusNotifierWatcher) ProtocolVersion() (int32, *dbus.Error) {
	return 1, nil
}

func NewWatcher() (*StatusNotifierWatcher, error) {
	conn, err := dbus.SessionBus()
	if err != nil {
		return nil, err
	}

	reply, err := conn.RequestName("org.kde.StatusNotifierWatcher", dbus.NameFlagDoNotQueue)
	if err != nil || reply != dbus.RequestNameReplyPrimaryOwner {
		return nil, fmt.Errorf("failed to request name: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	watcher := &StatusNotifierWatcher{
		conn:   conn,
		Items:  make(map[string]*StatusNotifierItem),
		cancel: cancel,
		ctx:    ctx,
	}

	conn.Export(watcher, "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher")
	node := &introspect.Node{
		Name: "/StatusNotifierWatcher",
		Interfaces: []introspect.Interface{
			introspect.IntrospectData,
			{
				Name: "org.kde.StatusNotifierWatcher",
				Methods: []introspect.Method{
					{Name: "RegisterStatusNotifierItem", Args: []introspect.Arg{
						{Name: "service", Type: "s", Direction: "in"},
					}},
					{Name: "RegisterStatusNotifierHost", Args: []introspect.Arg{
						{Name: "service", Type: "s", Direction: "in"},
					}},
					{Name: "RegisteredStatusNotifierItems", Args: []introspect.Arg{
						{Name: "items", Type: "as", Direction: "out"},
					}},
					{Name: "ProtocolVersion", Args: []introspect.Arg{
						{Name: "version", Type: "i", Direction: "out"},
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
	go func(watcher *StatusNotifierWatcher) {
		ch := make(chan *dbus.Signal)
		conn.Signal(ch)
		for {
			select {
			case <-watcher.ctx.Done():
				conn.RemoveSignal(ch)
				return
			case signal := <-ch:
				if signal.Name == "org.freedesktop.DBus.NameOwnerChanged" {
					oldOwner := signal.Body[1].(string)
					if _, exists := watcher.Items[oldOwner]; exists {
						delete(watcher.Items, oldOwner)
						watcher.mutex.Lock()
						conn.Emit("/StatusNotifierWatcher",
							"org.kde.StatusNotifierWatcher.StatusNotifierItemUnregistered",
							oldOwner)
						conn.Emit("/StatusNotifierWatcher",
							"org.kde.StatusNotifierWatcher.StatusNotifierItemUnregistered",
							oldOwner)
						watcher.mutex.Unlock()
					}
				} else {
					item, ok := watcher.Items[signal.Sender]
					if ok {
						item.handleSignal(signal)
					}
				}
				for _, handler := range watcher.listener {
					if handler != nil {
						handler()
					}
				}
			}
		}
	}(watcher)
	return watcher, nil
}
