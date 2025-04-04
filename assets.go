package main

import (
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"

	"github.com/wailsapp/wails/v3/pkg/application"
)

func NewAssetServer(assets string) http.Handler {
	if target, err := url.Parse(assets); err == nil && target.Scheme != "" {
		proxy := httputil.NewSingleHostReverseProxy(target)
		base := proxy.Director
		proxy.Director = func(req *http.Request) {
			req.URL.Path = strings.TrimPrefix(req.URL.Path, target.Path)
			base(req)
			req.Host = target.Host
			req.Header.Set("X-Forwarded-Host", req.Header.Get("Host"))
		}
		return proxy
	}
	return application.BundledAssetFileServer(os.DirFS(assets))
}
