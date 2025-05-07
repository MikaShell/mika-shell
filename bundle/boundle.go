package bundle

import (
	"debug/elf"
	"encoding/binary"
	"errors"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/spf13/afero"
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

func readBundle(sectionOffset uint64, r io.ReadSeeker, src string) fs.FS {
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
		offset += int64(sectionOffset)
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

func Bundle(assets fs.FS, dist, description string) error {
	var err error
	var exe string
	assetsFile, err := os.CreateTemp(os.TempDir(), "mikami-assets")
	if err != nil {
		return err
	}
	defer os.Remove(assetsFile.Name())
	if exe, err = os.Executable(); err != nil {
		return err
	}

	binary.Write(assetsFile, binary.LittleEndian, time.Now().Unix())
	binary.Write(assetsFile, binary.LittleEndian, int64(0)) // assets size
	binary.Write(assetsFile, binary.LittleEndian, uint32(len(description)))
	binary.Write(assetsFile, binary.LittleEndian, []byte(description))
	assetsFile.Sync()
	var size int64
	err = fs.WalkDir(assets, ".", func(path string, d fs.DirEntry, err error) error {
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
		n, err := writeBundle(assetsFile, path, file)
		size += n
		if err != nil {
			return err
		}
		return nil
	})
	if err != nil {
		assetsFile.Close()
		return err
	}
	assetsFile.Seek(8, io.SeekStart)
	binary.Write(assetsFile, binary.LittleEndian, size)
	assetsFile.Sync()
	assetsFile.Close()

	cmd := exec.Command("objcopy", "--add-section", ".mikami-assets="+assetsFile.Name(), exe, dist, "--set-section-flags", "assets=readonly", "--strip-all")
	if err := cmd.Run(); err != nil {
		return err
	}
	return nil
}

func SUnBundle(filename string) (*BundleData, error) {
	var err error
	exeELF, err := elf.Open(filename)
	if err != nil {
		return nil, err
	}
	defer exeELF.Close()
	section := exeELF.Section(".mikami-assets")
	if section == nil {
		return nil, errors.New("invalid bundle file")
	}
	assetsReader := section.Open()

	var header BundleHeader
	var createTime int64
	var size int64
	var descriptionLength uint32
	binary.Read(assetsReader, binary.LittleEndian, &createTime)
	binary.Read(assetsReader, binary.LittleEndian, &size)
	binary.Read(assetsReader, binary.LittleEndian, &descriptionLength)
	description := make([]byte, descriptionLength)
	binary.Read(assetsReader, binary.LittleEndian, &description)
	header.CreateTime = time.Unix(createTime, 0)
	header.Size = size
	header.Description = string(description)
	return &BundleData{
		BundleHeader: header,
		FS:           readBundle(section.Offset, assetsReader, filename),
	}, nil
}

func UnBundle() (*BundleData, error) {
	exe, _ := os.Executable()
	return SUnBundle(exe)
}

func hasBundle(filename string) bool {
	exeELF, err := elf.Open(filename)
	if err != nil {
		return false
	}
	defer exeELF.Close()
	section := exeELF.Section(".mikami-assets")
	return section != nil
}
func HasBundle() bool {
	exe, _ := os.Executable()
	return hasBundle(exe)
}
