package services

/*
#cgo linux pkg-config: gtk+-3.0
#include <gtk/gtk.h>
*/
import "C"
import (
	"fmt"
	"reflect"
	"unsafe"

	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/events"
)

type Mikami struct {
	app *application.App
}

func SetupApp(mikami *Mikami, app *application.App) {
	mikami.app = app
}

type MikamiWindow struct {
	ID            uint
	WebviewWindow *application.WebviewWindow
	GtkWindow     *C.GtkWindow
	GtkWidget     *C.GtkWidget
	IsInit        bool
}

var windows = []*MikamiWindow{}

func GetWindow(id uint) (*MikamiWindow, error) {
	for _, w := range windows {
		if w.ID == id {
			return w, nil
		}
	}
	// 0 是由npm包配置的默认值，如果为0，则表示还没有初始化完成
	if id == 0 {
		return nil, fmt.Errorf("mikami is not ready yet. Please wait for the 'Init' function.")
	}
	return nil, fmt.Errorf("window with id %d not found", id)
}

func (w *Mikami) registerWindow(window *application.WebviewWindow) uint {
	id := uint(reflect.ValueOf(window).Elem().FieldByName("id").Uint())
	window.OnWindowEvent(events.Common.WindowRuntimeReady, func(event *application.WindowEvent) {
		window.ExecJS(fmt.Sprintf("sessionStorage.setItem(\"mikami_id\", \"%d\");", id))
		window.EmitEvent("MikamiReady", nil)
	})
	impl := reflect.ValueOf(window).Elem().FieldByName("impl").Elem().Elem()
	windowPtr := unsafe.Pointer(impl.FieldByName("window").Pointer())
	windows = append(windows, &MikamiWindow{
		ID:            id,
		WebviewWindow: window,
		IsInit:        false,
		GtkWindow:     (*C.GtkWindow)(windowPtr),
		GtkWidget:     (*C.GtkWidget)(windowPtr),
	})
	return id
}

func (w *Mikami) NewWindow(path string) uint {
	window := w.app.NewWebviewWindowWithOptions(application.WebviewWindowOptions{
		Hidden: true,
		URL:    path,
	})
	return w.registerWindow(window)
}
