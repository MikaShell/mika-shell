package services

import (
	"bytes"
	"encoding/base64"
	"image"
	"image/color"
	"sort"
	"sync"

	"github.com/HumXC/mikami/lib/tray"
	"github.com/wailsapp/wails/v3/pkg/application"

	"slices"

	"github.com/kolesa-team/go-webp/webp"
)

type Icon struct {
	Height int32
	Width  int32
	Base64 string
}

// TODO: 优化视觉中心的算法
func (i *Icon) fromPixmap(p tray.Pixmap) {
	i.Width = p.Width
	i.Height = p.Height
	img := image.NewNRGBA(image.Rect(0, 0, int(p.Width), int(p.Height)))
	var sumX, sumY, sumAlpha float64
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
			alpha := float64(a) / 65535.0

			sumX += float64(x) * alpha
			sumY += float64(y) * alpha
			sumAlpha += alpha
		}
	}
	buf := new(bytes.Buffer)

	webp.Encode(buf, img, nil)
	i.Base64 = base64.StdEncoding.EncodeToString(buf.Bytes())
}

type Category tray.Category
type Status tray.Status

// TODO: 优化这一坨结构
type TrayItem struct {
	Service   string
	Id        string
	Category  Category
	IsMenu    bool
	Status    Status
	Title     string
	WindowId  int32
	Attention struct {
		IconName  string
		MovieName string
		Icon      *Icon
	}
	Icon struct {
		Width  int32
		Height int32
		Base64 string
	}
	OverlayIcon struct {
		Name string
		Icon *Icon
	}
	ToolTip struct {
		IconName    string
		Icon        *Icon
		Title       string
		Description string
	}
}

func (t *TrayItem) fromDBus(service string, item *tray.StatusNotifierItem) {
	parseIcon := func(p []tray.Pixmap) *Icon {
		slices.SortFunc(p, func(a, b tray.Pixmap) int {
			return int(b.Height - a.Height)
		})
		for _, pix := range p {
			i := Icon{}
			i.fromPixmap(pix)
			return &i
		}
		return nil
	}
	t.Service = service
	t.Id = item.Id
	t.Category = Category(item.Category)
	t.IsMenu = item.ItemIsMenu
	t.Status = Status(item.Status)
	t.Title = item.Title
	t.WindowId = item.WindowId
	t.Attention.IconName = item.AttentionIconName
	t.Attention.MovieName = item.AttentionMovieName
	t.Attention.Icon = parseIcon(item.AttentionIconPixmap)

	if icon := parseIcon(item.IconPixmap); icon != nil {
		t.Icon.Width = icon.Width
		t.Icon.Height = icon.Height
		t.Icon.Base64 = icon.Base64
	}
	t.OverlayIcon.Name = item.OverlayIconName
	t.OverlayIcon.Icon = parseIcon(item.OverlayIconPixmap)
	t.ToolTip.IconName = item.ToolTip.IconName
	t.ToolTip.Icon = parseIcon(item.ToolTip.IconPixmap)
	t.ToolTip.Title = item.ToolTip.Title
	t.ToolTip.Description = item.ToolTip.Description
}
func NewTray() application.Service {
	return application.NewService(&Tray{})
}

type Tray struct {
	watcher   *tray.StatusNotifierWatcher
	listeners []*application.WebviewWindow
	cache     []TrayItem
	mutex     sync.Mutex
}

func (t *Tray) Init() error {
	if t.watcher == nil {
		watcher, err := tray.New()
		if err != nil {
			return err
		}
		t.watcher = watcher
		watcher.AddListener(func() {
			t.cache = nil
			for _, listener := range t.listeners {
				listener.EmitEvent("Tray.Update")
			}
		})
	}
	return nil
}

func (t *Tray) Stop() {
	t.watcher.Close()
	t.watcher = nil
}

func (t *Tray) Items() []TrayItem {
	t.mutex.Lock()
	defer t.mutex.Unlock()
	if t.watcher == nil {
		return nil
	}
	if t.cache != nil {
		return t.cache
	}
	result := make([]TrayItem, 0, len(t.watcher.Items))
	for s, it := range t.watcher.Items {
		item := TrayItem{}
		item.fromDBus(s, it)
		result = append(result, item)
	}
	sort.Slice(result, func(i, j int) bool {
		return result[i].Id < result[j].Id
	})
	t.cache = result
	return result
}
func (t *Tray) Subscribe(id uint) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	if slices.Contains(t.listeners, window.WebviewWindow) {
		return nil
	}
	t.listeners = append(t.listeners, window.WebviewWindow)
	return nil
}

func (t *Tray) Unsubscribe(id uint) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	for i, w := range t.listeners {
		if w == window.WebviewWindow {
			t.listeners = slices.Delete(t.listeners, i, i+1)
		}
	}
	return nil
}

func (t *Tray) Activate(service string, x, y int32) {
	if t.watcher == nil {
		return
	}
	if it, ok := t.watcher.Items[service]; ok {
		it.Activate(x, y)
	}
}

func (t *Tray) ContextMenu(service string, x, y int32) {
	if t.watcher == nil {
		return
	}
	if it, ok := t.watcher.Items[service]; ok {
		it.ContextMenu(x, y)
	}
}

func (t *Tray) ProvideXdgActivationToken(service string, token string) {
	if t.watcher == nil {
		return
	}
	if it, ok := t.watcher.Items[service]; ok {
		it.ProvideXdgActivationToken(token)
	}
}

func (t *Tray) Scroll(service string, delta int32, orientation string) {
	if t.watcher == nil {
		return
	}
	if it, ok := t.watcher.Items[service]; ok {
		it.Scroll(delta, orientation)
	}
}

func (t *Tray) SecondaryActivate(service string, x, y int32) {
	if t.watcher == nil {
		return
	}
	if it, ok := t.watcher.Items[service]; ok {
		it.SecondaryActivate(x, y)
	}
}
