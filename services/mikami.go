package services

/*
#cgo pkg-config: gtk+-3.0 webkit2gtk-4.1

#include <gtk/gtk.h>
#include <webkit2/webkit2.h>
*/
import "C"
import (
	"fmt"
	"reflect"
	"unsafe"

	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/events"
)

func NewMikami() application.Service {
	return application.NewService(&Mikami{})
}

type Mikami struct {
	app *application.App
}

func SetupMikami(mikami application.Service, app *application.App) {
	instance := mikami.Instance().(*Mikami)
	instance.app = app
	app.OnApplicationEvent(events.Common.ApplicationStarted, func(event *application.ApplicationEvent) {
		// TODO: 设置webview的storage
		instance.NewWindow("/")
	})
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
		return nil, fmt.Errorf("mikami is not ready yet. Please wait for the 'Init' function")
	}
	return nil, fmt.Errorf("window with id %d not found", id)
}

func (m *Mikami) registerWindow(window *application.WebviewWindow) uint {
	id := window.ID()
	window.OnWindowEvent(events.Common.WindowRuntimeReady, func(event *application.WindowEvent) {
		window.ExecJS(fmt.Sprintf("sessionStorage.setItem(\"mikami_id\", \"%d\");", id))
		window.ExecJS(fmt.Sprintf("sessionStorage.setItem(\"mikami_name\", \"%s\");", window.Name()))
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

func (m *Mikami) NewWindow(path string) uint {
	window := m.app.NewWebviewWindowWithOptions(application.WebviewWindowOptions{
		Hidden: true,
		URL:    path,
	})
	impl := reflect.ValueOf(window).Elem().FieldByName("impl").Elem().Elem()
	windowPtr := (*C.GtkWindow)(unsafe.Pointer(impl.FieldByName("window").Pointer()))
	windowWidgetPtr := (*C.GtkWidget)(unsafe.Pointer(impl.FieldByName("window").Pointer()))
	webviewPtr := (*C.WebKitWebView)(unsafe.Pointer(impl.FieldByName("webview").Pointer()))
	application.InvokeSync(func() {
		// 解除 wails 默认的最大最小Size的设置
		C.gtk_window_set_geometry_hints(windowPtr, nil, nil, C.GDK_HINT_MAX_SIZE|C.GDK_HINT_MIN_SIZE)
		// 设置背景透明
		rgba := C.GdkRGBA{C.double(0), C.double(0), C.double(0), C.double(0)}
		C.webkit_web_view_set_background_color(webviewPtr, &rgba)
		cssStr := C.CString("window {background-color: transparent;}")
		provider := C.gtk_css_provider_new()
		context := C.gtk_widget_get_style_context(windowWidgetPtr)
		C.gtk_style_context_add_provider(
			context,
			(*C.GtkStyleProvider)(unsafe.Pointer(provider)),
			C.GTK_STYLE_PROVIDER_PRIORITY_USER)
		C.g_object_unref(C.gpointer(provider))
		C.gtk_css_provider_load_from_data(provider, cssStr, -1, nil)
		C.free(unsafe.Pointer(cssStr))
	})
	return m.registerWindow(window)
}

func (m *Mikami) CloseWindow(id uint) error {
	w, err := GetWindow(id)
	if err != nil {
		return err
	}
	w.WebviewWindow.Close()
	return nil
}

func (m *Mikami) Windows() []WindowInfo {
	result := make([]WindowInfo, len(windows))
	for i, w := range windows {
		field := reflect.ValueOf(w.WebviewWindow).Elem().FieldByName("options")
		options := reflect.NewAt(field.Type(), unsafe.Pointer(field.UnsafeAddr())).Interface().(*application.WebviewWindowOptions)

		result[i] = WindowInfo{
			Title: options.Title,
			URL:   options.URL,
			ID:    w.ID,
		}
	}
	return result
}

type WindowInfo struct {
	Name  string
	Title string
	URL   string
	ID    uint
}

func (m *Mikami) GetWindow(id uint) *WindowInfo {
	for _, w := range windows {
		if w.ID == id {
			options := reflect.ValueOf(w.WebviewWindow).Elem().FieldByName("options").Interface().(application.WebviewWindowOptions)
			return &WindowInfo{
				Name:  w.WebviewWindow.Name(),
				Title: options.Title,
				URL:   options.URL,
				ID:    w.ID,
			}
		}
	}
	return nil
}
