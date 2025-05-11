package services

import (
	"slices"
	"testing"

	"github.com/google/shlex"
)

func TestNormalizeCommand(t *testing.T) {
	cases := []struct {
		command                      string
		argf, argu, argi, argc, argk string
		argF, argU                   []string
		cmd                          []string
		env                          []string
	}{
		{
			"",
			"", "", "", "", "",
			nil, nil,
			nil,
			nil,
		}, {
			"A=c B=d C= go run /app.go",
			"", "", "", "", "",
			nil, nil,
			[]string{"go", "run", "/app.go"},
			[]string{"A=c", "B=d", "C="},
		}, {
			"go",
			"", "", "", "", "",
			nil, nil,
			[]string{"go"},
			nil,
		}, {
			"exe %f",
			"/path/to/file", "somethiong", "icon", "name", "path",
			[]string{"file1", "file2"}, []string{"http://example.com/file3"},
			[]string{"exe", "/path/to/file"},
			nil,
		}, {
			// A command line may contain at most one %f, %u, %F or %U field code.
			"exe %f %u %i %c %k %F %U",
			"/path/to/file", "somethiong", "icon", "name", "path",
			[]string{"file1", "file2"}, []string{"http://example.com/file3"},
			[]string{"exe", "/path/to/file", "icon", "name", "path"},
			nil,
		},
	}
	for _, c := range cases {
		command, _ := shlex.Split(c.command)
		cmd, env := NormalizeCommand(command, c.argf, c.argF, c.argu, c.argU, c.argi, c.argc, c.argk)
		if !slices.Equal(cmd, c.cmd) {
			t.Errorf("cmd: expected %v, got %v", c.cmd, cmd)
		}
		if !slices.Equal(env, c.env) {
			t.Errorf("env: expected %v, got %v", c.env, env)
		}
	}
}
