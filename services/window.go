package services

/*
#cgo pkg-config: gtk+-3.0
#include <gtk/gtk.h>
*/
import "C"
import "github.com/wailsapp/wails/v3/pkg/application"

func NewWindow() application.Service {
	return application.NewService(&Window{})
}

type Window struct{}
type WindowOption struct {
	Title     string
	Width     int
	Height    int
	MaxWidth  int
	MaxHeight int
	MinWidth  int
	MinHeight int
}

func (w *Window) Init(id uint, options WindowOption) error {
	win, err := GetWindow(id)
	if err != nil {
		return err
	}
	if win.IsInit {
		return nil
	}
	webviewWindow := win.WebviewWindow

	if options.Title != "" {
		webviewWindow.SetTitle(options.Title)
	}
	if options.MinWidth != 0 || options.MinHeight != 0 {
		webviewWindow.SetMinSize(options.MinWidth, options.MinHeight)
	}
	if options.MaxWidth != 0 || options.MaxHeight != 0 {
		webviewWindow.SetMaxSize(options.MaxWidth, options.MaxHeight)
	}
	if options.Width != 0 || options.Height != 0 {
		webviewWindow.SetSize(options.Width, options.Height)
	}
	win.IsInit = true
	return nil
}

func (w *Window) SetTitle(id uint, title string) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	window.WebviewWindow.SetTitle(title)
	return nil
}

func (w *Window) SetSize(id uint, width, height int) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	window.WebviewWindow.SetSize(width, height)
	return nil
}

func (w *Window) SetMinSize(id uint, width, height int) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	window.WebviewWindow.SetMinSize(width, height)
	return nil
}

func (w *Window) SetMaxSize(id uint, width, height int) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	window.WebviewWindow.SetMaxSize(width, height)
	return nil
}

func (w *Window) Close(id uint) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	window.WebviewWindow.Close()
	return nil
}

func (l *Window) Hide(id uint) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	window.WebviewWindow.Hide()
	return nil
}

func (w *Window) Show(id uint) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	window.WebviewWindow.Show()
	return nil
}
