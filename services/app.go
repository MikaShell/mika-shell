package services

import (
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/adrg/xdg"
	"github.com/google/shlex"
	"github.com/rkoesters/xdg/desktop"
	"github.com/wailsapp/wails/v3/pkg/application"
)

func NewApp() application.Service {
	a := App{}
	a.List()
	return application.NewService(&App{})
}

type Entry struct {
	desktop.Entry
	EntryPath string
}
type App struct{}

func (a *App) List() ([]Entry, error) {
	var apps []Entry
	for _, dir := range xdg.ApplicationDirs {
		filepath.WalkDir(dir, func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				return nil
			}
			if d.IsDir() {
				return nil
			}
			if filepath.Ext(path) == ".desktop" {
				app, err := a.open(path)
				if err != nil {
					return err
				}
				apps = append(apps, *app)
			}
			return nil
		})
	}
	return apps, nil
}

func (a *App) open(filename string) (*Entry, error) {
	f, err := os.Open(filename)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	entry, err := desktop.New(f)
	if err != nil {
		return nil, err
	}
	return &Entry{
		Entry:     *entry,
		EntryPath: filename,
	}, nil
}

// urls is a list of urls to open
// if wanted to open a file, use file://<path> as the url
// FIXME: 在遇到终端程序时，需要正确使用 TERM 终端启动
func (a *App) Run(entry *Entry, action string, urls []string) error {
	var err error
	var command []string
	if action == "" {
		command, err = shlex.Split(entry.Exec)
	} else {
		for _, act := range entry.Actions {
			if act.Name == action {
				command, err = shlex.Split(act.Exec)

			}
		}
	}
	if err != nil {
		return fmt.Errorf("invalid exec command: %s. error: %s", entry.Exec, err)
	}
	var argf, argu, argi, argc, argk string
	var argF, argU []string
	argi = entry.Icon
	argc = entry.Name
	argk = entry.EntryPath

	files := []string{}
	for _, u := range urls {
		if strings.HasPrefix(u, "file://") {
			files = append(files, u[7:])
		}
	}
	argF = files
	argU = urls
	if slices.Contains(command, "%f") {
		if len(files) == 1 {
			argf = files[0]
		}
		if len(files) > 1 {
			for _, f := range files {
				err := a.Run(entry, action, []string{f})
				if err != nil {
					return err
				}
			}
			return nil
		}
		if len(urls) == 1 {
			var file string
			file, err = fetchFile(urls[0], entry.Name)
			argf = file
		}
		if len(urls) > 1 {
			for _, u := range urls {
				err := a.Run(entry, action, []string{u})
				if err != nil {
					return err
				}
			}
			return nil
		}
	}
	if slices.Contains(command, "%u") {
		if len(urls) == 1 {
			argu = urls[0]
		}
		if len(urls) > 1 {
			for _, u := range urls {
				err := a.Run(entry, action, []string{u})
				if err != nil {
					return err
				}
			}
		}
	}

	command, env := NormalizeCommand(command, argf, argF, argu, argU, argi, argc, argk)
	if len(command) == 0 {
		return fmt.Errorf("invalid exec command: %s. error: %s", entry.Exec, err)
	}
	var cmd *exec.Cmd
	if entry.Terminal {
		terminal := os.Getenv("TERM")
		err = fmt.Errorf("no terminal environment variable found, please set $TERM")
		if terminal == "" {
			return err
		}
		var term string
		if _, e := exec.LookPath(terminal); e == nil {
			term = terminal
			err = nil
		} else {
			termSplit := strings.Split(terminal, "-")
			if len(termSplit) == 2 {
				if _, e := exec.LookPath(termSplit[1]); e == nil {
					term = termSplit[1]
					err = nil
				}
			}
		}
		if err != nil {
			return err
		}
		cmd = exec.Command(term, "-e", strings.Join(command, " "))
	} else {
		cmd = exec.Command(command[0], command[1:]...)
	}
	cmd.Env = append(os.Environ(), env...)
	cmd.Start()
	return err
}

func NormalizeCommand(
	command []string,
	argf string, argF []string,
	argu string, argU []string,
	argi string, argc string, argk string) (cmd []string, env []string) {

	deprecatedKeys := []string{"%d", "%D", "%n", "%N", "%v", "%m"}
	parseEnv := true

	// A command line may contain at most one %f, %u, %F or %U field code
	alreadyHasfFuU := false
	for i := range command {
		if parseEnv && strings.Contains(command[i], "=") {
			env = append(env, command[i])
			continue
		}
		parseEnv = false
		if slices.Contains(deprecatedKeys, command[i]) {
			continue
		}
		switch command[i] {
		case "%f":
			if alreadyHasfFuU || argf == "" {
				break
			}
			cmd = append(cmd, argf)
			alreadyHasfFuU = true
		case "%F":
			if alreadyHasfFuU || len(argF) == 0 {
				break
			}
			cmd = append(cmd, argF...)
			alreadyHasfFuU = true
		case "%u":
			if alreadyHasfFuU || argu == "" {
				break
			}
			cmd = append(cmd, argu)
			alreadyHasfFuU = true
		case "%U":
			if alreadyHasfFuU || len(argU) == 0 {
				break
			}
			cmd = append(cmd, argU...)
			alreadyHasfFuU = true
		case "%i":
			if argi == "" {
				break
			}
			cmd = append(cmd, argi)
		case "%c":
			if argc == "" {
				break
			}
			cmd = append(cmd, argc)
		case "%k":
			if argk == "" {
				break
			}
			cmd = append(cmd, argk)
		default:
			// TODO: add preceding
			// https://specifications.freedesktop.org/desktop-entry-spec/latest/exec-variables.html
			cmd = append(cmd, command[i])
		}
	}
	return
}

func fetchFile(url_, name string) (string, error) {
	var err error
	_, err = url.Parse(url_)
	if err != nil {
		return "", err
	}
	client := http.Client{
		Timeout: 2 * time.Second,
	}
	resp, err := client.Get(url_)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	temp, err := os.CreateTemp(os.TempDir(), "mikami-app-temp-"+name+"-")
	if err != nil {
		return "", err
	}
	io.Copy(temp, resp.Body)
	temp.Close()
	return temp.Name(), nil
}
