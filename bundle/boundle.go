package bundle

import (
	"encoding/binary"
	"errors"
	"github.com/spf13/afero"
	"io"
	"io/fs"
	"os"
	"strings"
	"time"
)

type prop struct {
	name   string
	offset int64
	size   int64
}
type file struct {
	prop
	f    *os.File
	read int64
}

var (
	_ io.Seeker   = (*file)(nil)
	_ io.ReaderAt = (*file)(nil)
	_ fs.File     = (*file)(nil)
	_ fs.FileInfo = (*file)(nil)
)

func (f *file) IsDir() bool        { return false }
func (f *file) ModTime() time.Time { return time.Time{} }
func (f *file) Mode() fs.FileMode  { return 0444 }
func (f *file) Name() string       { return f.name }
func (f *file) Size() int64        { return f.size }
func (f *file) Sys() any           { return nil }

func (f *file) ReadAt(p []byte, off int64) (n int, err error) {
	if off < 0 || off >= f.size {
		return 0, errors.New("invalid offset")
	}
	if len(p) == 0 {
		return 0, nil
	}
	if off+int64(len(p)) > f.size {
		p = p[:int(f.size-off)]
	}
	n, err = f.f.ReadAt(p, f.offset+off)
	f.read += int64(n)
	return
}

func (f *file) Seek(offset int64, whence int) (int64, error) {
	var trueOffset int64
	switch whence {
	case io.SeekStart:
		trueOffset = f.offset + offset
	case io.SeekCurrent:
		trueOffset = f.offset + f.read + offset
	case io.SeekEnd:
		trueOffset = f.offset + f.size + offset
	}
	n, err := f.f.Seek(trueOffset, io.SeekStart)
	if err != nil {
		return 0, err
	}
	f.read = n - f.offset
	return n, nil
}

func (f *file) Stat() (fs.FileInfo, error) {

	return f, nil
}

func (f *file) Close() error {
	return f.f.Close()
}

func (f *file) Read(p []byte) (n int, err error) {
	if f.read >= f.size {
		err = io.EOF
		return
	}
	if seekCurrent, _ := f.f.Seek(0, io.SeekCurrent); f.offset+f.size-seekCurrent < int64(len(p)) {
		p = p[:int(f.offset+f.size-seekCurrent)]
	}
	n, err = f.f.Read(p)
	f.read += int64(n)
	return
}

type bundle struct {
	files *[]prop
	fs    afero.Fs
	src   string
}

func (b *bundle) Open(name string) (fs.File, error) {
	fname := strings.TrimLeft(name, "/")
	if !fs.ValidPath(fname) {
		return nil, &fs.PathError{
			Op:   "open",
			Path: name,
			Err:  fs.ErrInvalid,
		}
	}
	for _, f := range *b.files {
		if f.name == fname {
			realFile, err := os.Open(b.src)
			if err != nil {
				return nil, err
			}
			realFile.Seek(f.offset, io.SeekStart)
			return &file{
				f:    realFile,
				prop: f,
			}, nil
		}
	}
	return b.fs.Open(name)
}

func writeBundle(w io.WriteSeeker, filename string, file fs.File) (int64, error) {
	var size int64
	filenameData := []byte(filename)
	length := uint32(len(filenameData))
	size += 4 + int64(length)
	if err := binary.Write(w, binary.LittleEndian, length); err != nil {
		return 0, err
	}
	if err := binary.Write(w, binary.LittleEndian, filenameData); err != nil {
		return 0, err
	}
	stat, err := file.Stat()
	if err != nil {
		return 0, err
	}
	length = uint32(stat.Size())
	size += 4 + int64(length)
	if err := binary.Write(w, binary.LittleEndian, length); err != nil {
		return 0, err
	}

	if _, err := io.Copy(w, file); err != nil {
		return 0, err
	}
	return size, nil
}

func readBundle(r io.ReadSeeker, src string) fs.FS {
	files := make([]prop, 0)
	var err error
	for {
		var filenameLength uint32
		if err = binary.Read(r, binary.LittleEndian, &filenameLength); err != nil {
			break
		}
		name := make([]byte, filenameLength)
		if err = binary.Read(r, binary.LittleEndian, &name); err != nil {
			break
		}
		dataLength := uint32(0)
		if err = binary.Read(r, binary.LittleEndian, &dataLength); err != nil {
			break
		}
		var offset int64
		if offset, err = r.Seek(0, io.SeekCurrent); err != nil {
			break
		}
		r.Seek(int64(dataLength), io.SeekCurrent)
		files = append(files, prop{
			name:   string(name),
			offset: offset,
			size:   int64(dataLength),
		})
	}
	virtualFS := afero.NewMemMapFs()
	for _, f := range files {
		_, _ = virtualFS.Create(f.name)
	}
	return &bundle{
		files: &files,
		fs:    virtualFS,
		src:   src,
	}
}

type BundleHeader struct {
	CreateTime  time.Time
	Size        int64
	Description string
}
type BundleData struct {
	BundleHeader
	fs.FS
}

const magic = "MIKAMI"

func Bundle(assets fs.FS, dist, description string) error {
	var err error
	var exe string
	var exeFile *os.File
	var distFile *os.File
	var offset int64

	if exe, err = os.Executable(); err != nil {
		return err
	}

	if exeFile, err = os.Open(exe); err != nil {
		return err
	}
	defer exeFile.Close()

	if distFile, err = os.OpenFile(dist, os.O_RDWR|os.O_CREATE, 0666); err != nil {
		return err
	}
	defer distFile.Close()
	if offset, err = io.Copy(distFile, exeFile); err != nil {
		return err
	}
	binary.Write(distFile, binary.LittleEndian, []byte(magic))
	binary.Write(distFile, binary.LittleEndian, time.Now().Unix())
	binary.Write(distFile, binary.LittleEndian, int64(0))
	binary.Write(distFile, binary.LittleEndian, uint32(len(description)))
	binary.Write(distFile, binary.LittleEndian, []byte(description))
	distFile.Sync()
	var size int64
	fs.WalkDir(assets, ".", func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		file, err := assets.Open(path)
		if err != nil {
			return err
		}
		defer file.Close()
		n, err := writeBundle(distFile, path, file)
		size += n
		if err != nil {
			return err
		}
		return nil
	})

	binary.Write(distFile, binary.LittleEndian, uint32(offset))
	distFile.Seek(offset+8+int64(len(magic)), io.SeekStart)
	binary.Write(distFile, binary.LittleEndian, size)
	distFile.Sync()
	return nil
}

func SUnBundle(filename string) (*BundleData, error) {
	var err error
	var exeFile *os.File

	if exeFile, err = os.Open(filename); err != nil {
		return nil, err
	}
	defer exeFile.Close()
	var offset uint32
	exeFile.Seek(-4, io.SeekEnd)
	binary.Read(exeFile, binary.LittleEndian, &offset)
	exeFile.Seek(int64(offset), io.SeekStart)
	if !hasBundle(exeFile) {
		return nil, errors.New("invalid bundle file")
	}
	var header BundleHeader
	var createTime int64
	var size int64
	var descriptionLength uint32
	binary.Read(exeFile, binary.LittleEndian, &createTime)
	binary.Read(exeFile, binary.LittleEndian, &size)
	binary.Read(exeFile, binary.LittleEndian, &descriptionLength)
	description := make([]byte, descriptionLength)
	binary.Read(exeFile, binary.LittleEndian, &description)
	header.CreateTime = time.Unix(createTime, 0)
	header.Size = size
	header.Description = string(description)
	return &BundleData{
		BundleHeader: header,
		FS:           readBundle(exeFile, filename),
	}, nil
}

func UnBundle() (*BundleData, error) {
	exe, _ := os.Executable()
	return SUnBundle(exe)
}

func hasBundle(r io.Reader) bool {
	var magic_ [len(magic)]byte
	binary.Read(r, binary.LittleEndian, &magic_)
	return string(magic_[:]) == magic
}
func HasBundle() bool {
	exe, _ := os.Executable()
	exeFile, _ := os.Open(exe)
	defer exeFile.Close()
	var offset uint32
	exeFile.Seek(-4, io.SeekEnd)
	binary.Read(exeFile, binary.LittleEndian, &offset)
	exeFile.Seek(int64(offset), io.SeekStart)
	return hasBundle(exeFile)
}
