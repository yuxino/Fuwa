//go:build fuwa_update_qa

// This executable is compiled only for updater acceptance. It calls the actual
// pinned MyGo updater from temporary fixture applications. The Ed25519 private
// key exists only in this controller's memory; nothing uses the owner's keys,
// installed applications, release feeds, login items, or system trust settings.
package main

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/egoist/mygo"
)

const fixtureName = "Fuwa Update QA.app"
const fixtureExecutable = "FuwaUpdateQA"
const markerName = "fuwa-update-qa-version.txt"

type qaResult struct {
	Name  string `json:"name"`
	OK    bool   `json:"ok"`
	Error string `json:"error,omitempty"`
}

type qaFeed struct {
	sync.Mutex
	mode      string
	archive   []byte
	signature string
	baseURL   string
	requests  map[string]int
}

func main() {
	var err error
	switch {
	case len(os.Args) == 2 && os.Args[1] == "--fuwa-update-smoke":
		err = controller()
	case len(os.Args) == 3 && os.Args[1] == "--fuwa-update-child":
		err = child(os.Args[2])
	case len(os.Args) == 2 && os.Args[1] == "--fuwa-update-installed":
		err = installed()
	default:
		err = errors.New("use --fuwa-update-smoke for the isolated updater acceptance")
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "FAIL updater:", err)
		os.Exit(1)
	}
}

func controller() error {
	output := os.Getenv("FUWA_SMOKE_OUTPUT")
	if output == "" {
		return errors.New("FUWA_SMOKE_OUTPUT is required")
	}
	root, err := os.MkdirTemp("", "fuwa-update-qa-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(root)
	// macOS commonly exposes /var through /private/var. Compare canonical
	// locations in the child, not their differently spelled aliases.
	root, err = filepath.EvalSymlinks(root)
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(root, ".fuwa-update-qa"), []byte("temporary fixture only\n"), 0o600); err != nil {
		return err
	}
	pub, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return err
	}
	feed := &qaFeed{requests: make(map[string]int)}
	server := httptest.NewServer(feed)
	defer server.Close()
	feed.Lock()
	feed.baseURL = server.URL
	feed.Unlock()
	flags := "-X github.com/egoist/mygo.production=1" +
		" -X github.com/egoist/mygo.packageUpdateKey=" + base64.StdEncoding.EncodeToString(pub) +
		" -X github.com/egoist/mygo.packageUpdateFeed=" + server.URL + "/manifest.json"
	binary := filepath.Join(root, "fixture-binary")
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	goTool := filepath.Join(runtime.GOROOT(), "bin", "go")
	build := exec.CommandContext(ctx, goTool, "build", "-mod=readonly", "-tags", "fuwa_update_qa,mygo_noinspector", "-trimpath", "-ldflags", flags, "-o", binary, "./scripts/qa/updater")
	build.Stdout, build.Stderr = os.Stdout, os.Stderr
	if err := build.Run(); err != nil {
		return fmt.Errorf("build isolated updater child: %w", err)
	}
	original := fixtureTarget(filepath.Join(root, "original"))
	replacement := fixtureTarget(filepath.Join(root, "replacement"))
	if err := makeFixture(original, binary, "1.0.0"); err != nil {
		return err
	}
	if err := makeFixture(replacement, binary, "2.0.0"); err != nil {
		return err
	}
	before, err := treeDigest(original)
	if err != nil {
		return err
	}
	after, err := treeDigest(replacement)
	if err != nil {
		return err
	}
	archive, err := fixtureArchive(replacement)
	if err != nil {
		return err
	}
	sum := sha256.Sum256(archive)
	feed.Lock()
	feed.archive = archive
	feed.signature = base64.StdEncoding.EncodeToString(ed25519.Sign(private, sum[:]))
	feed.Unlock()
	if info, ok := debug.ReadBuildInfo(); ok {
		for _, dependency := range info.Deps {
			if dependency.Path == "github.com/egoist/mygo" {
				fmt.Printf("Updater QA: %s/%s, MyGo %s\n", runtime.GOOS, runtime.GOARCH, dependency.Version)
			}
		}
	}
	var results []qaResult
	for _, mode := range []string{"valid", "tampered", "cancel-download", "cancel-final-byte", "offline"} {
		feed.Lock()
		feed.mode = mode
		feed.requests = make(map[string]int)
		feed.Unlock()
		if mode == "offline" {
			server.Close()
		}
		target := fixtureTarget(filepath.Join(root, "cases", mode))
		caseErr := copyTree(original, target)
		if caseErr == nil {
			caseErr = runChild(root, target, "--fuwa-update-child", mode)
		}
		want := before
		if mode == "valid" {
			want = after
		}
		if digest, err := treeDigest(target); err != nil {
			caseErr = errors.Join(caseErr, err)
		} else if digest != want {
			caseErr = errors.Join(caseErr, fmt.Errorf("%s left unexpected installed contents: %s (want %s)", mode, digest, want))
		}
		if entries, err := os.ReadDir(filepath.Dir(target)); err != nil {
			caseErr = errors.Join(caseErr, err)
		} else if len(entries) != 1 || entries[0].Name() != filepath.Base(target) {
			caseErr = errors.Join(caseErr, fmt.Errorf("%s left updater work or backup files next to the fixture", mode))
		}
		if mode != "offline" {
			feed.Lock()
			manifestRequests, archiveRequests := feed.requests["/manifest.json"], feed.requests["/archive.tar.gz"]
			feed.Unlock()
			if manifestRequests == 0 || archiveRequests == 0 {
				caseErr = errors.Join(caseErr, errors.New("fixture did not exercise both real updater HTTP requests"))
			}
		}
		if mode == "valid" && caseErr == nil {
			if runtime.GOOS == "darwin" {
				caseErr = verifySignature(target)
			}
			if caseErr == nil {
				caseErr = runChild(root, target, "--fuwa-update-installed")
			}
		}
		result := qaResult{Name: mode, OK: caseErr == nil}
		if caseErr != nil {
			result.Error = caseErr.Error()
			fmt.Println("FAIL updater:", mode, caseErr)
		} else {
			fmt.Println("PASS updater:", mode)
		}
		results = append(results, result)
	}
	if err := os.MkdirAll(output, 0o755); err != nil {
		return err
	}
	report, err := json.MarshalIndent(results, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(output, "updater-qa.json"), append(report, '\n'), 0o600); err != nil {
		return err
	}
	for _, result := range results {
		if !result.OK {
			return errors.New("real MyGo updater acceptance failed; see updater-qa.json")
		}
	}
	fmt.Println("PASS updater complete: real MyGo Check/Install with temporary fixtures and a generated test key")
	return nil
}

func (feed *qaFeed) ServeHTTP(w http.ResponseWriter, request *http.Request) {
	feed.Lock()
	feed.requests[request.URL.Path]++
	mode, archive, signature, baseURL := feed.mode, feed.archive, feed.signature, feed.baseURL
	feed.Unlock()
	switch request.URL.Path {
	case "/manifest.json":
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"version": "2.0.0", "notes": "Temporary updater acceptance fixture",
			"url": baseURL + "/archive.tar.gz", "size": len(archive), "signature": signature,
		})
	case "/archive.tar.gz":
		w.Header().Set("Content-Length", strconv.Itoa(len(archive)))
		if mode == "tampered" {
			archive = bytes.Clone(archive)
			archive[len(archive)/2] ^= 1 // Same length, original signature.
		}
		if mode == "cancel-download" {
			_, _ = w.Write(archive[:4096])
			w.(http.Flusher).Flush()
			select {
			case <-request.Context().Done():
			case <-time.After(20 * time.Second):
			}
			return
		}
		_, _ = w.Write(archive)
	default:
		http.NotFound(w, request)
	}
}

func child(mode string) error {
	if _, err := guardedTarget(); err != nil {
		return err
	}
	mygo.App.SetName("Fuwa Update QA")
	mygo.App.SetVersion("1.0.0")
	if !mygo.Updater.Enabled() {
		return errors.New("real updater is disabled in the QA child")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	update, err := mygo.Updater.Check(ctx)
	if mode == "offline" {
		if err == nil || update != nil || errors.Is(err, mygo.ErrUpdatesDisabled) || errors.Is(err, context.DeadlineExceeded) {
			return fmt.Errorf("offline check did not report a connection failure: %v", err)
		}
		fmt.Println("PASS updater child: offline Check failed without changing the application")
		return nil
	}
	if err != nil || update == nil || update.Version != "2.0.0" {
		return fmt.Errorf("real Check returned %+v, %v", update, err)
	}
	var downloaded, total int64
	cancelled := false
	err = update.Install(ctx, func(n, size int64) {
		downloaded, total = n, size
		if mode == "cancel-download" && n > 0 && n < size || mode == "cancel-final-byte" && n > 0 && n == size {
			cancelled = true
			cancel()
		}
	})
	switch mode {
	case "valid":
		if err != nil || downloaded != total || total <= 0 {
			return fmt.Errorf("valid Install failed: bytes=%d/%d, error=%v", downloaded, total, err)
		}
	case "tampered":
		if err == nil || !strings.Contains(err.Error(), "not signed with the app's key") {
			return fmt.Errorf("same-length tampered archive was not rejected by signature verification: %v", err)
		}
	case "cancel-download", "cancel-final-byte":
		if !cancelled || !errors.Is(err, context.Canceled) {
			return fmt.Errorf("cancellation was not honored: mode=%s bytes=%d/%d cancelled=%t Install=%v", mode, downloaded, total, cancelled, err)
		}
	default:
		return fmt.Errorf("unknown fixture case %q", mode)
	}
	fmt.Printf("PASS updater child: %s; downloaded %d/%d bytes\n", mode, downloaded, total)
	return nil
}

func installed() error {
	target, err := guardedTarget()
	if err != nil {
		return err
	}
	version, err := os.ReadFile(fixtureMarker(target))
	if err != nil || string(version) != "2.0.0\n" {
		return fmt.Errorf("newly installed executable could not confirm its replacement resources: %q, %v", version, err)
	}
	fmt.Println("PASS updater child: the installed replacement executable launches with version 2.0.0 resources")
	return nil
}

func guardedTarget() (string, error) {
	root := os.Getenv("FUWA_UPDATE_QA_ROOT")
	if root == "" || !strings.HasPrefix(filepath.Base(root), "fuwa-update-qa-") {
		return "", errors.New("updater fixture requires its temporary QA root")
	}
	temporary, err := filepath.EvalSymlinks(os.TempDir())
	if err != nil || filepath.Dir(root) != temporary {
		return "", errors.New("updater fixture root must be a temporary directory")
	}
	if marker, err := os.ReadFile(filepath.Join(root, ".fuwa-update-qa")); err != nil || string(marker) != "temporary fixture only\n" {
		return "", errors.New("temporary QA root marker is missing")
	}
	executable, err := os.Executable()
	if err != nil {
		return "", err
	}
	executable, err = filepath.EvalSymlinks(executable)
	if err != nil {
		return "", err
	}
	target := filepath.Dir(executable)
	if runtime.GOOS == "darwin" {
		target = filepath.Dir(filepath.Dir(target))
	}
	inside, err := filepath.Rel(filepath.Join(root, "cases"), target)
	if err != nil || inside == "." || inside == ".." || strings.HasPrefix(inside, ".."+string(filepath.Separator)) || filepath.Base(target) != fixtureName {
		return "", errors.New("refusing to update any application outside this temporary fixture")
	}
	return target, nil
}

func fixtureTarget(parent string) string { return filepath.Join(parent, fixtureName) }

func fixtureExe(target string) string {
	if runtime.GOOS == "darwin" {
		return filepath.Join(target, "Contents", "MacOS", fixtureExecutable)
	}
	return filepath.Join(target, fixtureExecutable)
}

func fixtureMarker(target string) string {
	if runtime.GOOS == "darwin" {
		return filepath.Join(target, "Contents", "Resources", markerName)
	}
	return filepath.Join(target, markerName)
}

func makeFixture(target, binary, version string) error {
	executable, marker := fixtureExe(target), fixtureMarker(target)
	for _, path := range []string{executable, marker} {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return err
		}
	}
	contents, err := os.ReadFile(binary)
	if err != nil {
		return err
	}
	if err := os.WriteFile(executable, contents, 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(marker, []byte(version+"\n"), 0o644); err != nil {
		return err
	}
	if runtime.GOOS == "darwin" {
		info := `<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FuwaUpdateQA</string>
<key>CFBundleIdentifier</key><string>app.yuxino.fuwa.mygo.updateqa</string>
<key>CFBundleName</key><string>Fuwa Update QA</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>` + version + `</string>
<key>CFBundleVersion</key><string>` + version + `</string>
<key>LSMinimumSystemVersion</key><string>14.0</string></dict></plist>`
		if err := os.WriteFile(filepath.Join(target, "Contents", "Info.plist"), []byte(info), 0o644); err != nil {
			return err
		}
		command := exec.Command("codesign", "--force", "--sign", "-", "--timestamp=none", target)
		if output, err := command.CombinedOutput(); err != nil {
			return fmt.Errorf("ad-hoc sign temporary updater fixture: %w\n%s", err, output)
		}
		return verifySignature(target)
	}
	return nil
}

func verifySignature(target string) error {
	output, err := exec.Command("codesign", "--verify", "--all-architectures", "--strict", target).CombinedOutput()
	if err != nil {
		return fmt.Errorf("verify temporary fixture signature: %w\n%s", err, output)
	}
	return nil
}

func runChild(root, target string, arguments ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	command := exec.CommandContext(ctx, fixtureExe(target), arguments...)
	command.Env = append(os.Environ(), "FUWA_UPDATE_QA_ROOT="+root, "XDG_DATA_HOME="+filepath.Join(root, "xdg"))
	output, err := command.CombinedOutput()
	fmt.Print(string(output))
	if err != nil {
		return fmt.Errorf("updater child: %w", err)
	}
	return nil
}

func copyTree(source, destination string) error {
	return filepath.WalkDir(source, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		relative, err := filepath.Rel(source, path)
		if err != nil {
			return err
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		target := filepath.Join(destination, relative)
		if entry.IsDir() {
			return os.MkdirAll(target, info.Mode().Perm())
		}
		if !info.Mode().IsRegular() {
			return fmt.Errorf("fixture unexpectedly contains a non-regular file: %s", path)
		}
		contents, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(target, contents, info.Mode().Perm())
	})
}

func treeDigest(root string) (string, error) {
	digest := sha256.New()
	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		_, _ = fmt.Fprintf(digest, "%s\x00%o\x00", filepath.ToSlash(relative), info.Mode())
		if entry.IsDir() {
			return nil
		}
		if !info.Mode().IsRegular() {
			return fmt.Errorf("fixture unexpectedly contains a non-regular file: %s", path)
		}
		file, err := os.Open(path)
		if err != nil {
			return err
		}
		defer file.Close()
		_, err = io.Copy(digest, file)
		return err
	})
	return hex.EncodeToString(digest.Sum(nil)), err
}

func fixtureArchive(target string) ([]byte, error) {
	var buffer bytes.Buffer
	gz := gzip.NewWriter(&buffer)
	tw := tar.NewWriter(gz)
	base := target
	if runtime.GOOS == "darwin" {
		base = filepath.Dir(target)
	}
	err := filepath.WalkDir(target, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		relative, err := filepath.Rel(base, path)
		if err != nil || relative == "." {
			return err
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		header, err := tar.FileInfoHeader(info, "")
		if err != nil {
			return err
		}
		header.Name = filepath.ToSlash(relative)
		if err := tw.WriteHeader(header); err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}
		file, err := os.Open(path)
		if err != nil {
			return err
		}
		defer file.Close()
		_, err = io.Copy(tw, file)
		return err
	})
	if err != nil {
		return nil, err
	}
	if err := tw.Close(); err != nil {
		return nil, err
	}
	if err := gz.Close(); err != nil {
		return nil, err
	}
	return buffer.Bytes(), nil
}
