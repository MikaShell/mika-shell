package services

import (
	"context"
	"slices"
	"sort"
	"time"

	"github.com/thiagokokada/hyprland-go"
	hyprEvent "github.com/thiagokokada/hyprland-go/event"
	"github.com/thiagokokada/hyprland-go/helpers"
	"github.com/wailsapp/wails/v3/pkg/application"
)

func NewHyprland() application.Service {
	return application.NewService(&Hyprland{})
}

type HyprlandEventHandler struct {
	c           *hyprEvent.EventClient
	closeClient context.CancelFunc
	listenerMap map[*application.WebviewWindow][]hyprEvent.EventType
	allEvents   []hyprEvent.EventType
	ch          chan HyprlandEventHandlerPayload
}
type HyprlandEventHandlerPayload struct {
	EventType hyprEvent.EventType
	Data      any
}

func (h *HyprlandEventHandler) Add(window *application.WebviewWindow, event hyprEvent.EventType) error {
	if window == nil {
		return nil
	}
	if h.c == nil {
		sock, err := helpers.GetSocket(helpers.EventSocket)
		if err != nil {
			return err
		}
		c, err := hyprEvent.NewClient(sock)
		if err != nil {
			return err
		}
		h.c = c
		h.ch = make(chan HyprlandEventHandlerPayload, 10)
		go func() {
			duration := 20 * time.Millisecond
			timer := time.NewTimer(duration)
			timer.Stop()
			defer timer.Stop()
			tasks := make(map[hyprEvent.EventType]any, 0)
			for {
				select {
				case event, ok := <-h.ch:
					if !ok {
						return
					}
					tasks[event.EventType] = event.Data
					timer.Reset(duration)
				case <-timer.C:
					for typ, data := range tasks {
						h.EmitEventToWindow(typ, data)
					}
					tasks = make(map[hyprEvent.EventType]any, 0)
				}
			}
		}()
	}
	if h.listenerMap == nil {
		h.listenerMap = make(map[*application.WebviewWindow][]hyprEvent.EventType)
	}
	if h.allEvents == nil {
		h.allEvents = make([]hyprEvent.EventType, 0)
	}
	if h.listenerMap[window] == nil {
		h.listenerMap[window] = make([]hyprEvent.EventType, 0)
	}
	listeners := h.listenerMap[window]
	if slices.Contains(listeners, event) {
		return nil
	}
	h.listenerMap[window] = append(listeners, event)

	if !slices.Contains(h.allEvents, event) {
		h.allEvents = append(h.allEvents, event)
		if h.closeClient != nil {
			h.closeClient()
		}
		ctx, cancel := context.WithCancel(context.Background())
		h.closeClient = cancel
		h.c.Subscribe(ctx, h, h.allEvents...)
	}
	return nil
}

func (h *HyprlandEventHandler) Remove(window *application.WebviewWindow, event hyprEvent.EventType) error {
	listeners := h.listenerMap[window]
	if listeners == nil {
		return nil
	}
	index := slices.Index(listeners, event)
	if index == -1 {
		return nil
	}
	listeners = slices.Delete(listeners, index, index+1)
	h.listenerMap[window] = listeners
	if len(listeners) == 0 {
		delete(h.listenerMap, window)
	}
	if len(h.listenerMap) == 0 {
		h.closeClient()
		h.closeClient = nil
		h.c = nil
		close(h.ch)
		h.ch = nil
	}
	return nil
}

func (h *HyprlandEventHandler) EmitEventToWindow(e hyprEvent.EventType, data any) {
	for window, events := range h.listenerMap {
		if slices.Contains(events, e) {
			window.EmitEvent("Hyprland."+string(e), data)
		}
	}
}

func (h *HyprlandEventHandler) ActiveLayout(l hyprEvent.ActiveLayout) {
	h.ch <- HyprlandEventHandlerPayload{hyprEvent.EventActiveLayout, l}
}

func (h *HyprlandEventHandler) ActiveWindow(w hyprEvent.ActiveWindow) {
	h.ch <- HyprlandEventHandlerPayload{hyprEvent.EventActiveWindow, w}
}

func (h *HyprlandEventHandler) CloseLayer(c hyprEvent.CloseLayer) {
	h.ch <- HyprlandEventHandlerPayload{hyprEvent.EventCloseLayer, c}
}

func (h *HyprlandEventHandler) CloseWindow(c hyprEvent.CloseWindow) {
	h.ch <- HyprlandEventHandlerPayload{hyprEvent.EventCloseWindow, c}
}

func (h *HyprlandEventHandler) CreateWorkspace(w hyprEvent.WorkspaceName) {
	h.ch <- HyprlandEventHandlerPayload{hyprEvent.EventCreateWorkspace, w}
}

func (h *HyprlandEventHandler) DestroyWorkspace(w hyprEvent.WorkspaceName) {
	h.ch <- HyprlandEventHandlerPayload{hyprEvent.EventDestroyWorkspace, w}
}

func (h *HyprlandEventHandler) FocusedMonitor(m hyprEvent.FocusedMonitor) {
	h.ch <- HyprlandEventHandlerPayload{hyprEvent.EventFocusedMonitor, m}
}

func (h *HyprlandEventHandler) Fullscreen(f hyprEvent.Fullscreen) {
	h.ch <- HyprlandEventHandlerPayload{hyprEvent.EventFullscreen, f}
}

func (h *HyprlandEventHandler) MonitorAdded(m hyprEvent.MonitorName) {
	h.ch <- HyprlandEventHandlerPayload{hyprEvent.EventMonitorAdded, m}
}

func (h *HyprlandEventHandler) MonitorRemoved(m hyprEvent.MonitorName) {
	h.ch <- HyprlandEventHandlerPayload{hyprEvent.EventMonitorRemoved, m}
}

func (h *HyprlandEventHandler) MoveWindow(m hyprEvent.MoveWindow) {
	h.ch <- HyprlandEventHandlerPayload{hyprEvent.EventMoveWindow, m}
}

func (h *HyprlandEventHandler) MoveWorkspace(w hyprEvent.MoveWorkspace) {
	h.ch <- HyprlandEventHandlerPayload{hyprEvent.EventMoveWorkspace, w}
}

func (h *HyprlandEventHandler) OpenLayer(l hyprEvent.OpenLayer) {
	h.ch <- HyprlandEventHandlerPayload{hyprEvent.EventOpenLayer, l}
}

func (h *HyprlandEventHandler) OpenWindow(o hyprEvent.OpenWindow) {
	h.ch <- HyprlandEventHandlerPayload{hyprEvent.EventOpenWindow, o}
}

func (h *HyprlandEventHandler) Screencast(s hyprEvent.Screencast) {
	h.ch <- HyprlandEventHandlerPayload{hyprEvent.EventScreencast, s}
}

func (h *HyprlandEventHandler) SubMap(s hyprEvent.SubMap) {
	h.ch <- HyprlandEventHandlerPayload{hyprEvent.EventSubMap, s}
}

func (h *HyprlandEventHandler) Workspace(w hyprEvent.WorkspaceName) {
	h.ch <- HyprlandEventHandlerPayload{hyprEvent.EventWorkspace, w}
}

var _ hyprEvent.EventHandler = (*HyprlandEventHandler)(nil)

type Hyprland struct {
	c *hyprland.RequestClient
	e *HyprlandEventHandler
}

// 该函数只用于 Wails 导出 JS 类型，实际上并没有实现任何功能
func (h *Hyprland) ExportModels(
	hyprEvent.ActiveLayout,
	hyprEvent.ActiveWindow,
	hyprEvent.CloseLayer,
	hyprEvent.CloseWindow,
	hyprEvent.FocusedMonitor,
	hyprEvent.Fullscreen,
	hyprEvent.MoveWindow,
	hyprEvent.MoveWorkspace,
	hyprEvent.OpenLayer,
	hyprEvent.OpenWindow,
	hyprEvent.Screencast,
	hyprEvent.SubMap,
	hyprEvent.WorkspaceName,
) {
}

func (h *Hyprland) init() error {
	if h.c != nil {
		return nil
	}
	sock, err := helpers.GetSocket(helpers.RequestSocket)
	if err != nil {
		return err
	}
	h.c = hyprland.NewClient(sock)
	return nil
}

func (h *Hyprland) Subscribe(id uint, event hyprEvent.EventType) error {
	if h.e == nil {
		h.e = &HyprlandEventHandler{}
	}
	window, err := GetWebview(id)
	if err != nil {
		return err
	}
	return h.e.Add(window.WebviewWindow, event)
}

func (h *Hyprland) Unsubscribe(id uint, event hyprEvent.EventType) error {
	if h.e == nil {
		return nil
	}
	window, err := GetWebview(id)
	if err != nil {
		return err
	}
	return h.e.Remove(window.WebviewWindow, event)
}

func (h *Hyprland) ActiveWindow() (hyprland.Window, error) {
	if err := h.init(); err != nil {
		return hyprland.Window{}, err
	}
	return h.c.ActiveWindow()
}

func (h *Hyprland) ActiveWorkspace() (hyprland.Workspace, error) {
	if err := h.init(); err != nil {
		return hyprland.Workspace{}, err
	}
	return h.c.ActiveWorkspace()
}

func (h *Hyprland) Animations() ([][]hyprland.Animation, error) {
	if err := h.init(); err != nil {
		return nil, err
	}
	return h.c.Animations()
}

func (h *Hyprland) Binds() ([]hyprland.Bind, error) {
	if err := h.init(); err != nil {
		return nil, err
	}
	return h.c.Binds()
}

func (h *Hyprland) Clients() ([]hyprland.Client, error) {
	if err := h.init(); err != nil {
		return nil, err
	}
	return h.c.Clients()
}

func (h *Hyprland) ConfigErrors() ([]hyprland.ConfigError, error) {
	if err := h.init(); err != nil {
		return nil, err
	}
	return h.c.ConfigErrors()
}

func (h *Hyprland) CursorPos() (hyprland.CursorPos, error) {
	if err := h.init(); err != nil {
		return hyprland.CursorPos{}, err
	}
	return h.c.CursorPos()
}

func (h *Hyprland) Decorations(regex string) ([]hyprland.Decoration, error) {
	if err := h.init(); err != nil {
		return nil, err
	}
	return h.c.Decorations(regex)
}

func (h *Hyprland) Devices() (hyprland.Devices, error) {
	if err := h.init(); err != nil {
		return hyprland.Devices{}, err
	}
	return h.c.Devices()
}

func (h *Hyprland) Dispatch(params ...string) ([]hyprland.Response, error) {
	if err := h.init(); err != nil {
		return nil, err
	}
	return h.c.Dispatch(params...)
}

func (h *Hyprland) GetOption(name string) (hyprland.Option, error) {
	if err := h.init(); err != nil {
		return hyprland.Option{}, err
	}
	return h.c.GetOption(name)
}

func (h *Hyprland) Keyword(params ...string) ([]hyprland.Response, error) {
	if err := h.init(); err != nil {
		return nil, err
	}
	return h.c.Keyword(params...)
}

func (h *Hyprland) Kill() (hyprland.Response, error) {
	if err := h.init(); err != nil {
		return "", err
	}
	return h.c.Kill()
}

func (h *Hyprland) Layers() (hyprland.Layers, error) {
	if err := h.init(); err != nil {
		return hyprland.Layers{}, err
	}
	return h.c.Layers()
}

func (h *Hyprland) Monitors() ([]hyprland.Monitor, error) {
	if err := h.init(); err != nil {
		return nil, err
	}
	return h.c.Monitors()
}

func (h *Hyprland) Reload() (hyprland.Response, error) {
	if err := h.init(); err != nil {
		return "", err
	}
	return h.c.Reload()
}

func (h *Hyprland) SetCursor(theme string, size int) (hyprland.Response, error) {
	if err := h.init(); err != nil {
		return "", err
	}
	return h.c.SetCursor(theme, size)
}

func (h *Hyprland) Splash() (string, error) {
	if err := h.init(); err != nil {
		return "", err
	}
	return h.c.Splash()
}

func (h *Hyprland) SwitchXkbLayout(device string, cmd string) (hyprland.Response, error) {
	if err := h.init(); err != nil {
		return "", err
	}
	return h.c.SwitchXkbLayout(device, cmd)
}

func (h *Hyprland) Workspace() ([]hyprland.Workspace, error) {
	if err := h.init(); err != nil {
		return nil, err
	}
	ws, err := h.c.Workspaces()
	if err != nil {
		return nil, err
	}
	sort.Slice(ws, func(i, j int) bool {
		return ws[i].Id < ws[j].Id
	})
	return ws, nil
}
