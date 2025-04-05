package services

/*
#cgo linux pkg-config: gtk+-3.0
#include <gtk/gtk.h>
*/
import "C"
import (
	"unsafe"

	"github.com/HumXC/mikami/layershell"
	"github.com/wailsapp/wails/v3/pkg/application"
)

type Layer struct {
}

type LayerOptions struct {
	Title                   string
	Namespace               string
	AutoExclusiveZoneEnable bool
	ExclusiveZone           int
	Anchor                  []layershell.EdgeFlags
	Layer                   layershell.LayerFlags
	Margin                  []int
	Width                   int
	Height                  int
}

func (l *Layer) Init(id uint, options LayerOptions) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}

	gtkWindow := window.GtkWindow
	gtkWidget := window.GtkWidget
	application.InvokeSync(func() {
		layer := layershell.NewWindow(unsafe.Pointer(gtkWindow))
		if !window.IsInit {
			layer.Init()
		}
		layer.SetLayer(options.Layer)
		if options.Title != "" {
			window.WebviewWindow.SetTitle(options.Title)
		}
		if options.Namespace == "" {
			options.Namespace = "mikami-layer"
		}
		layer.SetNamespace(options.Namespace)
		layer.SetExclusiveZone(options.ExclusiveZone)
		if options.AutoExclusiveZoneEnable {
			layer.AutoExclusiveZoneEnable()
		}
		for _, edge := range options.Anchor {
			layer.SetAnchor(edge, true)
		}
		for i, margin := range options.Margin {
			switch i {
			case 0:
				layer.SetMargin(layershell.EDGE_TOP, margin)
			case 1:
				layer.SetMargin(layershell.EDGE_RIGHT, margin)
			case 2:
				layer.SetMargin(layershell.EDGE_BOTTOM, margin)
			case 3:
				layer.SetMargin(layershell.EDGE_LEFT, margin)
			}
		}
		C.gtk_window_set_default_size(gtkWindow, -1, -1)
		if options.Width <= 0 && options.Height <= 0 {
			C.gtk_window_set_resizable(gtkWindow, C.gboolean(0))
		}
		C.gtk_widget_set_size_request(gtkWidget, C.gint(options.Width), C.gint(options.Height))
	})
	window.IsInit = true
	return nil
}

func (l *Layer) SetSize(id uint, width int, height int) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	application.InvokeSync(func() {
		if width == 0 || height == 0 {
			C.gtk_window_set_resizable(window.GtkWindow, C.gboolean(0))
		} else {
			C.gtk_window_set_resizable(window.GtkWindow, C.gboolean(1))
		}
		C.gtk_widget_set_size_request(window.GtkWidget, C.gint(width), C.gint(height))
	})
	return nil
}

func (l *Layer) SetLayer(id uint, layer layershell.LayerFlags) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	la := layershell.NewWindow(unsafe.Pointer(window.GtkWindow))
	application.InvokeSync(func() {
		la.SetLayer(layer)
	})
	return nil
}

func (l *Layer) SetTitle(id uint, title string) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	window.WebviewWindow.SetTitle(title)
	return nil
}

func (l *Layer) SetAnchor(id uint, edge layershell.EdgeFlags, anchor bool) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	application.InvokeSync(func() {
		layer := layershell.NewWindow(unsafe.Pointer(window.GtkWindow))
		layer.SetAnchor(edge, anchor)
	})
	return nil
}

func (l *Layer) ResetAnchor(id uint) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	layer := layershell.NewWindow(unsafe.Pointer(window.GtkWindow))
	application.InvokeSync(func() {
		layer.SetAnchor(layershell.EDGE_BOTTOM, false)
		layer.SetAnchor(layershell.EDGE_LEFT, false)
		layer.SetAnchor(layershell.EDGE_RIGHT, false)
		layer.SetAnchor(layershell.EDGE_TOP, false)
	})
	return nil
}

func (l *Layer) SetMargin(id uint, edge layershell.EdgeFlags, margin int) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	layer := layershell.NewWindow(unsafe.Pointer(window.GtkWindow))
	application.InvokeSync(func() {
		layer.SetMargin(edge, margin)
	})
	return nil
}

func (l *Layer) SetNamespace(id uint, namespace string) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	layer := layershell.NewWindow(unsafe.Pointer(window.GtkWindow))
	application.InvokeSync(func() {
		layer.SetNamespace(namespace)
	})
	return nil
}

func (l *Layer) Size(id uint) (int, int, error) {
	window, err := GetWindow(id)
	if err != nil {
		return 0, 0, err
	}
	size := application.InvokeSyncWithResult(func() [2]int {
		width := C.gtk_widget_get_allocated_width(window.GtkWidget)
		height := C.gtk_widget_get_allocated_height(window.GtkWidget)
		return [2]int{int(width), int(height)}
	})

	return int(size[0]), int(size[1]), nil
}

func (l *Layer) SetExclusiveZone(id uint, zone int) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	layer := layershell.NewWindow(unsafe.Pointer(window.GtkWindow))
	application.InvokeSync(func() {
		layer.SetExclusiveZone(zone)
	})
	return nil
}

func (l *Layer) AutoExclusiveZoneEnable(id uint) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	layer := layershell.NewWindow(unsafe.Pointer(window.GtkWindow))
	application.InvokeSync(func() {
		layer.AutoExclusiveZoneEnable()
	})
	return nil
}

func (l *Layer) Close(id uint) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	window.WebviewWindow.Close()
	return nil
}

func (l *Layer) Hide(id uint) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	window.WebviewWindow.Hide()
	return nil
}

func (l *Layer) Show(id uint) error {
	window, err := GetWindow(id)
	if err != nil {
		return err
	}
	window.WebviewWindow.Show()
	return nil
}
