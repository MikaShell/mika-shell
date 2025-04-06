package services

import (
	"context"
	"fmt"
	"slices"

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
	ctx         context.Context
	listenerMap map[*application.WebviewWindow][]hyprEvent.EventType
	allEvents   []hyprEvent.EventType
}

func (h *HyprlandEventHandler) Add(window *application.WebviewWindow, event hyprEvent.EventType) error {
	sock, err := helpers.GetSocket(helpers.EventSocket)
	if err != nil {
		return err
	}
	if h.c == nil {
		c, err := hyprEvent.NewClient(sock)
		if err != nil {
			return err
		}
		h.c = c
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
		if h.ctx != nil {
			h.ctx.Done()
		}
		h.ctx = context.WithoutCancel(context.Background())

		h.c.Subscribe(h.ctx, h, h.allEvents...)
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
		h.ctx.Done()
		h.ctx = nil
	}
	return nil
}
func (h *HyprlandEventHandler) EmitEventToWindow(eventType hyprEvent.EventType, data any) {
	for window, events := range h.listenerMap {
		if slices.Contains(events, eventType) {
			window.EmitEvent("Hyprland."+string(eventType), data)
		}
	}
}

func (h *HyprlandEventHandler) ActiveLayout(l hyprEvent.ActiveLayout) {
	h.EmitEventToWindow(hyprEvent.EventActiveLayout, l)
}

func (h *HyprlandEventHandler) ActiveWindow(w hyprEvent.ActiveWindow) {
	h.EmitEventToWindow(hyprEvent.EventActiveWindow, w)
}

func (h *HyprlandEventHandler) CloseLayer(c hyprEvent.CloseLayer) {
	h.EmitEventToWindow(hyprEvent.EventCloseLayer, c)
}

func (h *HyprlandEventHandler) CloseWindow(c hyprEvent.CloseWindow) {
	h.EmitEventToWindow(hyprEvent.EventCloseWindow, c)
}

func (h *HyprlandEventHandler) CreateWorkspace(w hyprEvent.WorkspaceName) {
	h.EmitEventToWindow(hyprEvent.EventCreateWorkspace, w)
}

func (h *HyprlandEventHandler) DestroyWorkspace(w hyprEvent.WorkspaceName) {
	h.EmitEventToWindow(hyprEvent.EventDestroyWorkspace, w)
}

func (h *HyprlandEventHandler) FocusedMonitor(m hyprEvent.FocusedMonitor) {
	h.EmitEventToWindow(hyprEvent.EventFocusedMonitor, m)
}

func (h *HyprlandEventHandler) Fullscreen(f hyprEvent.Fullscreen) {
	h.EmitEventToWindow(hyprEvent.EventFullscreen, f)
}

func (h *HyprlandEventHandler) MonitorAdded(m hyprEvent.MonitorName) {
	h.EmitEventToWindow(hyprEvent.EventMonitorAdded, m)
}

func (h *HyprlandEventHandler) MonitorRemoved(m hyprEvent.MonitorName) {
	h.EmitEventToWindow(hyprEvent.EventMonitorRemoved, m)
}

func (h *HyprlandEventHandler) MoveWindow(m hyprEvent.MoveWindow) {
	h.EmitEventToWindow(hyprEvent.EventMoveWindow, m)
}

func (h *HyprlandEventHandler) MoveWorkspace(w hyprEvent.MoveWorkspace) {
	h.EmitEventToWindow(hyprEvent.EventMoveWorkspace, w)
}

func (h *HyprlandEventHandler) OpenLayer(l hyprEvent.OpenLayer) {
	h.EmitEventToWindow(hyprEvent.EventOpenLayer, l)
}

func (h *HyprlandEventHandler) OpenWindow(o hyprEvent.OpenWindow) {
	h.EmitEventToWindow(hyprEvent.EventOpenWindow, o)
}

func (h *HyprlandEventHandler) Screencast(s hyprEvent.Screencast) {
	h.EmitEventToWindow(hyprEvent.EventScreencast, s)
}

func (h *HyprlandEventHandler) SubMap(s hyprEvent.SubMap) {
	h.EmitEventToWindow(hyprEvent.EventSubMap, s)
}

func (h *HyprlandEventHandler) Workspace(w hyprEvent.WorkspaceName) {
	h.EmitEventToWindow(hyprEvent.EventWorkspace, w)
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
	window, err := GetWindow(id)
	if err != nil {
		return fmt.Errorf("failed to initialize hyprland client: %w", err)
	}
	return h.e.Add(window.WebviewWindow, event)
}

func (h *Hyprland) Unsubscribe(id uint, event hyprEvent.EventType) error {
	if h.e == nil {
		return nil
	}
	window, err := GetWindow(id)
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
	return h.c.Workspaces()
}
