package main

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"net"
	"os"
)

type EventServer struct {
	listener net.Listener
}

func (s *EventServer) Listen(ctx context.Context, fn func(err error, name string, data any)) error {
	chConn := make(chan net.Conn)
	go func() {
		for {
			conn, err := s.listener.Accept()
			if ctx.Err() != nil {
				conn.Close()
				return
			}
			if err != nil {
				fn(err, "", nil)
				continue
			}
			if conn != nil {
				chConn <- conn
			}
		}
	}()
	for {
		select {
		case <-ctx.Done():
			s.listener.Close()
			return nil
		case conn := <-chConn:
			name, data, err := s.readEvent(conn)
			conn.Close()
			fn(err, name, data)
		}
	}
}

func (s *EventServer) readEvent(conn net.Conn) (string, any, error) {
	// read event name
	var nameLen int32
	if err := binary.Read(conn, binary.LittleEndian, &nameLen); err != nil {
		return "", nil, err
	}
	name := make([]byte, nameLen)
	if err := binary.Read(conn, binary.LittleEndian, &name); err != nil {
		return "", nil, err
	}
	// read event data
	var dataLen int32
	if err := binary.Read(conn, binary.LittleEndian, &dataLen); err != nil {
		return "", nil, err
	}
	dataStr := make([]byte, dataLen)
	if err := binary.Read(conn, binary.LittleEndian, &dataStr); err != nil {
		return "", nil, err
	}
	var data any
	if err := json.Unmarshal(dataStr, &data); err == nil {
		return string(name), data, nil
	}
	return string(name), string(dataStr), nil
}

func NewEventServer(path string) (*EventServer, error) {
	if conn, err := net.Dial("unix", path); err == nil {
		defer conn.Close()
		return nil, fmt.Errorf("event server already running on %s", path)
	} else {
		os.Remove(path)
	}
	listener, err := net.Listen("unix", path)
	if err != nil {
		return nil, err
	}
	return &EventServer{listener: listener}, nil
}

func SendEvent(path string, name, data string) error {
	conn, err := net.Dial("unix", path)
	if err != nil {
		return err
	}
	defer conn.Close()
	// write event name
	nameBytes := []byte(name)
	if err := binary.Write(conn, binary.LittleEndian, int32(len(nameBytes))); err != nil {
		return err
	}
	if err := binary.Write(conn, binary.LittleEndian, nameBytes); err != nil {
		return err
	}
	// write event data
	dataBytes := []byte(data)
	if err := binary.Write(conn, binary.LittleEndian, int32(len(dataBytes))); err != nil {
		return err
	}
	if err := binary.Write(conn, binary.LittleEndian, dataBytes); err != nil {
		return err
	}
	return nil
}
