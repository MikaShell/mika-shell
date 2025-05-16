package main

import (
	"context"
	"fmt"
	"io"
	"io/fs"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"sync"
	"syscall"

	"github.com/HumXC/mikami/bundle"
	"github.com/HumXC/mikami/services"
	"github.com/adrg/xdg"
	"github.com/dustin/go-humanize"
	"github.com/urfave/cli/v2"
	"github.com/wailsapp/wails/v3/pkg/application"
)

func SockPath(instance string) string {
	return filepath.Join(xdg.RuntimeDir, fmt.Sprintf("%s.sock", instance))
}
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
		fmt.Printf("failed to get config dir: %v", err)
		return nil
	}
	hasBudle := bundle.HasBundle()
	instanceName := "mikami"
	if hasBudle {
		b, err := bundle.UnBundle()
		if err != nil {
			fmt.Printf("failed to unbundle: %v", err)
			return nil
		}
		instanceName = b.Name
	}
	app := &cli.App{
		Name:   "mikami",
		Action: CmdMain,
		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:    "config",
				Aliases: []string{"c"},
				Value:   configDir,
				Usage:   "Set config directory path",
			},
			&cli.StringFlag{
				Name:    "instance",
				Aliases: []string{"i"},
				Value:   instanceName,
				Usage:   "Instance name, used in socket file name",
			},
		},
		Commands: []*cli.Command{
			{
				Name:   "event",
				Usage:  "Send an event to mikami. e.g. mikami event <EventName> <EventData>",
				Action: CmdEvent,
			},
		},
	}
	if !hasBudle {
		app.Flags = append(app.Flags,
			&cli.StringFlag{
				Name:  "dev",
				Usage: "Need a http server to serve frontend assets.",
			},
		)
		app.Commands = append(app.Commands, &cli.Command{
			Name:   "bundle",
			Usage:  "Bundle frontend assets into executable file. e.g. mikami bundle <AssetsDir> <OutputFile> <Description>",
			Action: CmdBundle,
		})
	} else {
		app.Commands = append(app.Commands, &cli.Command{
			Name:   "unbundle",
			Usage:  "Extract bundled assets from executable file. e.g. mikami unbundle <OutputDir>",
			Action: CmdUnBundle,
		})
	}
	return app

}

func CmdMain(ctx *cli.Context) error {
	var err error
	assetsPath := ctx.String("dev")
	isDevMode := true
	if assetsPath == "" {
		assetsPath = filepath.Join(ctx.String("config"), "assets")
		os.Mkdir(assetsPath, 0755)
		isDevMode = false
	}
	var assetsServer http.Handler
	hasBundle := bundle.HasBundle()
	if hasBundle {
		assets, err := bundle.UnBundle()
		if err != nil {
			return err
		}
		fmt.Println("Use bundled assets from executable file")
		fmt.Println("Assets name:", assets.Name)
		fmt.Println("Assets description:", assets.Description)
		fmt.Println("Assets create time:", assets.CreateTime)
		fmt.Println("Assets size:", humanize.Bytes(uint64(assets.Size)))
		assetsServer = NewBundledAssetServer(assets)
	} else {
		assetsServer = NewAssetServer(assetsPath, isDevMode)
	}

	mikami := services.NewMikami()

	app := application.New(application.Options{
		Assets: application.AssetOptions{
			Handler: assetsServer,
		},
		Services: []application.Service{
			mikami,
			services.NewHyprland(),
			services.NewLayer(),
			services.NewWindow(),
			services.NewTray(),
			services.NewNotifd(),
			services.NewOS(),
			services.NewApp(),
			services.NewTheme(),
			services.NewConfig(filepath.Join(ctx.String("config"), "config.json")),
			application.NewService(application.DefaultLogger(slog.LevelInfo)),
		},
	})
	services.SetupMikami(mikami, app)
	wg := sync.WaitGroup{}

	if eventServer, err := NewEventServer(SockPath(ctx.String("instance"))); err != nil {
		return err
	} else {
		go func() {
			err = eventServer.Listen(context.Background(), func(err error, name string, data any) {
				if err != nil {
					fmt.Println(err)
					return
				}
				fmt.Println("Received event:", name, data)
				app.EmitEvent(name, data)
			})
			if err != nil {
				wg.Add(1)
				app.Quit()
				wg.Done()
			}
		}()
	}

	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-sigs
		wg.Add(1)
		app.Quit()
		wg.Done()
	}()

	if err_ := app.Run(); err_ != nil {
		return err_
	}
	wg.Wait()
	return err
}

func CmdBundle(ctx *cli.Context) error {
	assetsDir := ctx.Args().Get(0)
	outputFile := ctx.Args().Get(1)
	description := ctx.Args().Get(2)
	if assetsDir == "" || outputFile == "" || description == "" {
		return fmt.Errorf("invalid arguments. Usage: mikami bundle <AssetsDir> <OutputFile> <Description>")
	}
	if stat, err := os.Stat(assetsDir); os.IsNotExist(err) {
		return fmt.Errorf("sssets directory not found: %s", assetsDir)
	} else if !stat.IsDir() {
		return fmt.Errorf("sssets path is not a directory: %s", assetsDir)
	}
	return bundle.Bundle(os.DirFS(assetsDir), outputFile, description)
}

func CmdUnBundle(ctx *cli.Context) error {
	if !bundle.HasBundle() {
		return fmt.Errorf("no bundle found")
	}
	dist := ctx.Args().Get(0)
	if dist == "" {
		exe, _ := os.Executable()
		dist = exe + "-assets"
	}
	assets, err := bundle.UnBundle()
	if err != nil {
		return err
	}
	fmt.Println("Use bundled assets from executable file")
	fmt.Println("Assets name:", assets.Name)
	fmt.Println("Assets description:", assets.Description)
	fmt.Println("Assets create time:", assets.CreateTime)
	fmt.Println("Assets size:", humanize.Bytes(uint64(assets.Size)))
	fmt.Println("Extracting assets to:", dist)
	os.MkdirAll(dist, 0755)
	err = fs.WalkDir(assets, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			os.Mkdir(filepath.Join(dist, path), 0755)
			return nil
		}
		src, err := assets.Open(path)
		if err != nil {
			return err
		}
		defer src.Close()
		dst, err := os.Create(filepath.Join(dist, path))
		if err != nil {
			return err
		}
		defer dst.Close()
		if _, err := io.Copy(dst, src); err != nil {
			return err
		}
		return nil
	})
	return err
}

func CmdEvent(ctx *cli.Context) error {
	if ctx.Args().Len() < 1 {
		return fmt.Errorf("invalid arguments. Usage: mikami event <EventName> <EventData|null>")
	}
	eventName := ctx.Args().Get(0)
	eventData := ctx.Args().Get(1)
	return SendEvent(SockPath(ctx.String("instance")), eventName, eventData)
}
