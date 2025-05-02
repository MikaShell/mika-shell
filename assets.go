package main

import (
	"io/fs"
	"net/http"
	"os"

	"github.com/wailsapp/wails/v3/pkg/application"
)

func NewAssetServer(assets string, dev bool) http.Handler {
	if dev {
		// BundledAssetFileServer 内部需要这个环境变量
		os.Setenv("FRONTEND_DEVSERVER_URL", assets)
	}
	return application.BundledAssetFileServer(os.DirFS(assets))
}

func NewBundledAssetServer(assets fs.FS) http.Handler {
	return application.BundledAssetFileServer(assets)
}
