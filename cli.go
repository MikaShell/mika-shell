package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/HumXC/mikami/services"
	"github.com/urfave/cli/v2"
	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/events"
)

const DEFAULT_ASSETS_DIR = "/usr/share/aikadm"

func ConfigDir() (string, error) {
	userConfigDir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(userConfigDir, "mikami"), nil
}
func NewCli() *cli.App {
	configDir, err := ConfigDir()
	if err != nil {
		fmt.Println(err)
		return nil
	}
	return &cli.App{
		Name:   "mikami",
		Action: CmdMain,
		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:    "assets",
				Aliases: []string{"a"},
				Value:   filepath.Join(configDir, "assets"),
				Usage:   "Set of assets to serve",
			},
		},
		Commands: []*cli.Command{
			{
				Name:   "install",
				Usage:  "Install frontend assets to the specified directory, which can be a compressed file, directory or a link to a compressed file. If directory is not exists, it will be created.",
				Action: CmdInstall,
			},
		},
	}

}

func CmdMain(ctx *cli.Context) error {
	configDir, err := ConfigDir()
	if err != nil {
		fmt.Println(err)
		return nil
	}
	os.MkdirAll(configDir, 0755)
	// TODO: 设置webview的storage
	assetsPath := ctx.String("assets")
	mikami := &services.Mikami{}
	window := &services.Window{}
	layer := &services.Layer{}
	app := application.New(application.Options{
		Assets: application.AssetOptions{
			Handler: NewAssetServer(assetsPath),
		},
		Services: []application.Service{
			application.NewService(mikami),
			application.NewService(window),
			application.NewService(layer),
		},
	})
	services.SetupApp(mikami, app)

	app.OnApplicationEvent(events.Common.ApplicationStarted, func(event *application.ApplicationEvent) {
		mikami.NewWindow("/")
	})
	return app.Run()
}

func CmdInstall(ctx *cli.Context) error {

	return nil
}
