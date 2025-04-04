package layershell

/*
#cgo pkg-config: gtk+-3.0 gtk-layer-shell-0
#include <gtk/gtk.h>
#include <gtk-layer-shell.h>
*/
import "C"
import (
	"unsafe"
)

type EdgeFlags int

const (
	EDGE_LEFT EdgeFlags = iota
	EDGE_RIGHT
	EDGE_TOP
	EDGE_BOTTOM
)

type LayerFlags int

const (
	LAYER_BACKGROUND LayerFlags = iota
	LAYER_BOTTOM
	LAYER_TOP
	LAYER_OVERLAY
)

type Window struct {
	ptr *C.GtkWindow
}

func NewWindow(window unsafe.Pointer) *Window {
	return &Window{ptr: (*C.GtkWindow)(window)}
}
func (w *Window) Init() {
	C.gtk_layer_init_for_window(w.ptr)
}
func (w *Window) SetLayer(layer LayerFlags) {
	C.gtk_layer_set_layer(w.ptr, C.GtkLayerShellLayer(layer))
}
func (w *Window) SetAnchor(edge EdgeFlags, anchor bool) {
	_anchor := C.gboolean(0)
	if anchor {
		_anchor = C.gboolean(1)
	}
	C.gtk_layer_set_anchor(w.ptr, C.GtkLayerShellEdge(edge), _anchor)
}
func (w *Window) SetMargin(edge EdgeFlags, margin int) {
	C.gtk_layer_set_margin(w.ptr, C.GtkLayerShellEdge(edge), C.gint(margin))
}
func (w *Window) SetExclusiveZone(zone int) {
	C.gtk_layer_set_exclusive_zone(w.ptr, C.int(zone))
}
func (w *Window) SetNamespace(namespace string) {
	_namespace := C.CString(namespace)
	defer C.free(unsafe.Pointer(_namespace))
	C.gtk_layer_set_namespace(w.ptr, _namespace)
}
func (w *Window) AutoExclusiveZoneEnable() {
	C.gtk_layer_auto_exclusive_zone_enable(w.ptr)
}
