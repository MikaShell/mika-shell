package main

import (
	"io/fs"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"

	"github.com/wailsapp/wails/v3/pkg/application"
)

func NewAssetServer(assets string, dev bool) http.Handler {
	if dev {
		parsedURL, err := url.Parse(assets)
		if err != nil {
			return http.HandlerFunc(
				func(rw http.ResponseWriter, req *http.Request) {
					log.Default().Print(req.Context(), "[ExternalAssetHandler] Invalid FRONTEND_DEVSERVER_URL. Should be valid URL", "error", err.Error())
					http.Error(rw, err.Error(), http.StatusInternalServerError)
				})

		}

		proxy := httputil.NewSingleHostReverseProxy(parsedURL)
		proxy.ErrorHandler = func(rw http.ResponseWriter, r *http.Request, err error) {
			log.Default().Print(r.Context(), "[ExternalAssetHandler] Proxy error", "error", err.Error())
			rw.WriteHeader(http.StatusBadGateway)
		}

		return proxy
	}

	return application.AssetFileServerFS(os.DirFS(assets))
}

func NewBundledAssetServer(assets fs.FS) http.Handler {
	return application.AssetFileServerFS(assets)
}
