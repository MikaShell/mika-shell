package services

import (
	"encoding/base64"
	"fmt"
	"os"
	"os/exec"

	"github.com/google/shlex"
	"github.com/wailsapp/wails/v3/pkg/application"
)

func NewOS() application.Service {
	return application.NewService(&OS{})
}

type OS struct{}

func (o *OS) Exec(command string) error {
	cmd_, err := shlex.Split(command)
	if err != nil {
		return err
	}

	cmd := exec.Command(cmd_[0], cmd_[1:]...)
	err = cmd.Run()
	if err != nil {
		output, _ := cmd.CombinedOutput()
		return fmt.Errorf("error executing command: %s, output: %s", err, output)
	}
	return nil
}

func (o *OS) Read(filename string) (string, error) {
	b, err := os.ReadFile(filename)
	if err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(b), nil
}

func (o *OS) Write(filename string, content string) error {
	b, err := base64.StdEncoding.DecodeString(content)
	if err != nil {
		return err
	}
	return os.WriteFile(filename, b, 0644)
}
