package services

/*
#cgo pkg-config: gtk+-3.0
#include <gtk/gtk.h>
*/
import "C"
import (
	"encoding/base64"
	"net/url"
	"os"
	"strings"
	"unsafe"

	"github.com/wailsapp/wails/v3/pkg/application"
)

func NewTheme() application.Service {
	return application.NewService(&Theme{})
}

type Theme struct{}

func (t *Theme) LookupIcon(name string, size int) (string, error) {
	var filename string
	application.InvokeSync(func() {
		icon_theme := C.gtk_icon_theme_get_default()
		icon_name := C.CString(name)
		defer C.free(unsafe.Pointer(icon_name))
		icon_info := C.gtk_icon_theme_lookup_icon(icon_theme, icon_name, C.gint(size), C.GTK_ICON_LOOKUP_USE_BUILTIN)
		if icon_info == nil {
			return
		}
		defer C.g_object_unref(C.gpointer(icon_info))
		icon_filename := C.gtk_icon_info_get_filename(icon_info)
		filename = C.GoString(icon_filename)
	})
	if filename == "" {
		if _, err := os.Stat(name); err != nil {
			return "", nil
		}
		filename = name
	}
	b, err := os.ReadFile(filename)
	if err != nil {
		return "", err
	}
	if strings.HasSuffix(filename, ".svg") {
		return "data:image/svg+xml," + url.PathEscape(string(b)), nil
	}
	return "data:image/png;base64," + base64.StdEncoding.EncodeToString(b), nil
}
