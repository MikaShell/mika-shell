package services

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"image"
	"image/color"
	"slices"

	"github.com/HumXC/mikami/lib/notifd"
	"github.com/kolesa-team/go-webp/webp"
	"github.com/wailsapp/wails/v3/pkg/application"
)

type Urgency notifd.Urgency

const (
	UrgencyLow Urgency = iota
	UrgencyNormal
	UrgencyCritical
)

type Notification struct {
	Id            uint32
	AppName       string
	Replacesed    bool
	AppIcon       *string
	Summary       string
	Body          string
	Actions       []string
	ExpireTimeout uint32
	ActionIcons   bool
	Category      string
	DesktopEntry  string
	Image         *string // Base64 encoded image data
	Resident      bool
	SoundFile     *string
	SoundName     *string
	SuppressSound bool
	Transient     bool
	Urgency       Urgency
	SenderPID     int64
}

func (n *Notification) FromDBus(src notifd.Notification) {
	n.Id = src.Id
	n.AppName = src.AppName
	n.Replacesed = src.ReplacesId > 0
	n.AppIcon = &src.AppIcon
	n.Summary = src.Summary
	n.Body = src.Body
	n.Actions = src.Actions
	n.ExpireTimeout = src.ExpireTimeout

	if actionIcons, ok := src.Hints[notifd.HintActionIcons]; ok {
		n.ActionIcons = actionIcons.(bool)
	}
	if category, ok := src.Hints[notifd.HintCategory]; ok {
		n.Category = category.(string)
	}
	if desktopEntry, ok := src.Hints[notifd.HintDesktopEntry]; ok {
		n.DesktopEntry = desktopEntry.(string)
	}
	if resident, ok := src.Hints[notifd.HintResident]; ok {
		n.Resident = resident.(bool)
	}
	if soundFile, ok := src.Hints[notifd.HintSoundFile]; ok {
		str, _ := soundFile.(string)
		n.SoundFile = &str
	}
	if soundName, ok := src.Hints[notifd.HintSoundName]; ok {
		str, _ := soundName.(string)
		n.SoundName = &str
	}
	if suppressSound, ok := src.Hints[notifd.HintSuppressSound]; ok {
		n.SuppressSound = suppressSound.(bool)
	}
	if transient, ok := src.Hints[notifd.HintTransient]; ok {
		n.Transient = transient.(bool)
	}
	if urgency, ok := src.Hints[notifd.HintUrgency]; ok {
		n.Urgency = Urgency(urgency.(byte))
	}
	if senderPID, ok := src.Hints[notifd.HintSenderPID]; ok {
		n.SenderPID = senderPID.(int64)
	}
	p := src.Hints[notifd.HintImageData].(notifd.ImageData)

	img := image.NewNRGBA(image.Rect(0, 0, int(p.Width), int(p.Height)))
	for y := range int(p.Height) {
		for x := range int(p.Width) {
			i := y*int(p.Rowstride) + x*int(p.Channels)
			r := p.ImageData[i]
			g := p.ImageData[i+1]
			b := p.ImageData[i+2]
			a := uint8(255)
			if p.Channels == 4 {
				a = p.ImageData[i+3]
			}
			img.Set(x, y, color.NRGBA{R: r, G: g, B: b, A: a})
		}
	}
	buf := new(bytes.Buffer)

	webp.Encode(buf, img, nil)
	base64Str := base64.StdEncoding.EncodeToString(buf.Bytes())
	n.Image = &base64Str
}

func NewNotifd() application.Service {
	return application.NewService(&Notifd{})
}

type Notifd struct {
	daemon    *notifd.Notifyd
	listeners []uint
}

func (n *Notifd) onNotify(notification notifd.Notification) {
	nn := Notification{}
	nn.FromDBus(notification)
	for _, listener := range n.listeners {
		w, _ := GetWindow(listener)
		w.WebviewWindow.EmitEvent("Notifd.Notification", nn)
	}
}
func (n *Notifd) onCloseNotification(id uint32) {
	for _, listener := range n.listeners {
		w, _ := GetWindow(listener)
		w.WebviewWindow.EmitEvent("Notifd.CloseNotification", id)
	}
}

func (n *Notifd) Subscribe(id uint) error {
	if n.daemon == nil {
		daemonl, err := notifd.New(n.onNotify, n.onCloseNotification)
		if err != nil {
			return err
		}
		n.daemon = daemonl
	}
	if slices.Index(n.listeners, id) >= 0 {
		return nil
	}
	n.listeners = append(n.listeners, id)
	return nil
}

func (n *Notifd) Unsubscribe(id uint) error {
	for i, listener := range n.listeners {
		if listener == id {
			n.listeners = slices.Delete(n.listeners, i, i+1)
			break
		}
	}
	if len(n.listeners) == 0 {
		n.daemon.Close()
		n.daemon = nil
	}
	return nil
}

func (n *Notifd) GetNotifications() []Notification {
	result := []Notification{}
	for _, notification := range n.daemon.Ns {
		n := Notification{}
		n.FromDBus(notification)
		result = append(result, n)
	}
	return result
}
func (n *Notifd) GetNotification(id uint32) (*Notification, error) {
	for _, notification := range n.daemon.Ns {
		if notification.Id == id {
			n := Notification{}
			n.FromDBus(notification)
			return &n, nil
		}
	}
	return nil, fmt.Errorf("notification with id %d not found", id)
}

func (n *Notifd) CloseNotification(id uint32) error {
	if n.daemon == nil {
		return fmt.Errorf("notification daemon not running")
	}
	n.daemon.CloseNotification(id)
	return nil
}

func (n *Notifd) InvokeAction(id uint32, action string) error {
	if n.daemon == nil {
		return fmt.Errorf("notification daemon not running")
	}
	n.daemon.ActionInvoked(id, action)
	return nil
}

func (n *Notifd) ActivationToken(id uint32, token string) error {
	if n.daemon == nil {
		return fmt.Errorf("notification daemon not running")
	}
	n.daemon.ActivationToken(id, token)
	return nil
}
