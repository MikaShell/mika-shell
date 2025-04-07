package services

import (
	"bytes"
	"encoding/base64"
	"image"
	"image/color"
	"sort"

	"github.com/HumXC/mikami/lib"
	"github.com/wailsapp/wails/v3/pkg/application"

	"slices"

	"github.com/kolesa-team/go-webp/webp"
)

type Icon struct {
	Height  int32
	Width   int32
	CenterX int32
	CenterY int32
	Base64  string
}

func (i *Icon) fromPixmap(p lib.Pixmap) {
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
	i.CenterX = int32(sumX / sumAlpha)
	i.CenterY = int32(sumY / sumAlpha)
	buf := new(bytes.Buffer)

	webp.Encode(buf, img, nil)
	i.Base64 = base64.StdEncoding.EncodeToString(buf.Bytes())
}

type Category lib.Category
type Status lib.Status
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
		Icons     []Icon
	}
	Icon struct {
		Name      string
		ThemePath string
		Icons     []Icon
	}
	OverlayIcon struct {
		Name  string
		Icons []Icon
	}
	ToolTip struct {
		IconName    string
		Icons       []Icon
		Title       string
		Description string
	}
}

func (t *TrayItem) fromDBus(service string, item *lib.StatusNotifierItem) {
	parseIcon := func(p []lib.Pixmap) []Icon {
		result := make([]Icon, 0, len(p))
		for _, pix := range p {
			i := Icon{}
			i.fromPixmap(pix)
			result = append(result, i)
		}
		slices.SortFunc(result, func(a, b Icon) int {
			return int(b.Height - a.Height)
		})
		return result
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
	t.Attention.Icons = parseIcon(item.AttentionIconPixmap)
	t.Icon.Name = item.IconName
	t.Icon.ThemePath = item.IconThemePath
	t.Icon.Icons = parseIcon(item.IconPixmap)
	t.OverlayIcon.Name = item.OverlayIconName
	t.OverlayIcon.Icons = parseIcon(item.OverlayIconPixmap)
	t.ToolTip.IconName = item.ToolTip.IconName
	t.ToolTip.Icons = parseIcon(item.ToolTip.IconPixmap)
	t.ToolTip.Title = item.ToolTip.Title
	t.ToolTip.Description = item.ToolTip.Description
}
func NewTray() application.Service {
	return application.NewService(&Tray{})
}

type Tray struct {
	watcher   *lib.StatusNotifierWatcher
	listeners []*application.WebviewWindow
}

func (t *Tray) Init() error {
	if t.watcher == nil {
		watcher, err := lib.NewWatcher()
		if err != nil {
			return err
		}
		t.watcher = watcher
		watcher.AddListener(func() {
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
	if t.watcher == nil {
		return nil
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
