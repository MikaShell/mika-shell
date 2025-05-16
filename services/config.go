package services

import (
	"encoding/json"
	"github.com/wailsapp/wails/v3/pkg/application"
	"os"
)

func NewConfig(configFilePath string) application.Service {
	return application.NewService(&Config{configFilePath: configFilePath})
}

type Config struct {
	configFilePath string
}

func (c *Config) Read() (string, error) {
	if _, err := os.Stat(c.configFilePath); os.IsNotExist(err) {
		return "{}", nil
	}
	file, err := os.ReadFile(c.configFilePath)
	if err != nil {
		return "{}", err
	}
	return string(file), nil
}

func (c *Config) Write(config any) error {
	jsonConfig, err := json.Marshal(config)
	if err != nil {
		return err
	}
	f, err := os.Create(c.configFilePath)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = f.Write(jsonConfig)
	if err != nil {
		return err
	}
	return nil
}
