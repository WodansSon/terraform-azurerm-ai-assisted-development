package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestFingerprintDetectsRepositoryChanges(t *testing.T) {
	repositoryPath := newTestRepository(t)

	initial := requireFingerprint(t, repositoryPath)
	repeated := requireFingerprint(t, repositoryPath)
	if initial != repeated {
		t.Fatal("fingerprint changed without a repository change")
	}

	writeTestFile(t, repositoryPath, "tracked.txt", "staged")
	runTestGit(t, repositoryPath, "add", "--", "tracked.txt")
	staged := requireFingerprint(t, repositoryPath)
	if staged == initial {
		t.Fatal("staged change did not change the fingerprint")
	}

	writeTestFile(t, repositoryPath, "tracked.txt", "staged\nunstaged")
	unstaged := requireFingerprint(t, repositoryPath)
	if unstaged == staged {
		t.Fatal("unstaged change did not change the fingerprint")
	}

	writeTestFile(t, repositoryPath, "space file.txt", "untracked")
	untracked := requireFingerprint(t, repositoryPath)
	if untracked == unstaged {
		t.Fatal("untracked file did not change the fingerprint")
	}

	writeTestFile(t, repositoryPath, "space file.txt", "changed untracked content")
	changedUntracked := requireFingerprint(t, repositoryPath)
	if changedUntracked == untracked {
		t.Fatal("untracked content change did not change the fingerprint")
	}

	writeTestFile(t, repositoryPath, "caf\u00e9.txt", "utf-8 path")
	utf8Path := requireFingerprint(t, repositoryPath)
	if utf8Path == changedUntracked {
		t.Fatal("UTF-8 untracked path did not change the fingerprint")
	}
}

func TestFingerprintDetectsUntrackedSymlinkTarget(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("creating symbolic links can require additional Windows privileges")
	}

	repositoryPath := newTestRepository(t)
	linkPath := filepath.Join(repositoryPath, "untracked-link")

	if err := os.Symlink("target-one", linkPath); err != nil {
		t.Fatalf("creating first symbolic link: %v", err)
	}
	first := requireFingerprint(t, repositoryPath)

	if err := os.Remove(linkPath); err != nil {
		t.Fatalf("removing first symbolic link: %v", err)
	}
	if err := os.Symlink("target-two", linkPath); err != nil {
		t.Fatalf("creating second symbolic link: %v", err)
	}
	second := requireFingerprint(t, repositoryPath)

	if first == second {
		t.Fatal("symbolic-link target change did not change the fingerprint")
	}
}

func TestFingerprintRejectsNonRepository(t *testing.T) {
	_, err := fingerprint(t.TempDir())
	if err == nil {
		t.Fatal("expected a non-repository error")
	}
}

func requireFingerprint(t *testing.T, repositoryPath string) string {
	t.Helper()

	statusBefore := runTestGit(t, repositoryPath, "status", "--porcelain=v1", "-z")
	result, err := fingerprint(repositoryPath)
	if err != nil {
		t.Fatalf("computing fingerprint: %v", err)
	}
	statusAfter := runTestGit(t, repositoryPath, "status", "--porcelain=v1", "-z")

	if statusBefore != statusAfter {
		t.Fatal("fingerprint computation changed repository status")
	}
	if result.Algorithm != "sha256-v1" {
		t.Fatalf("unexpected algorithm: %s", result.Algorithm)
	}
	if len(result.Fingerprint) != 64 {
		t.Fatalf("unexpected fingerprint length: %d", len(result.Fingerprint))
	}

	return result.Fingerprint
}

func newTestRepository(t *testing.T) string {
	t.Helper()

	repositoryPath := t.TempDir()
	runTestGit(t, repositoryPath, "init", "--quiet")
	runTestGit(t, repositoryPath, "config", "user.email", "fingerprint@example.invalid")
	runTestGit(t, repositoryPath, "config", "user.name", "Fingerprint Test")
	runTestGit(t, repositoryPath, "config", "commit.gpgsign", "false")
	runTestGit(t, repositoryPath, "config", "core.autocrlf", "false")
	writeTestFile(t, repositoryPath, "tracked.txt", "initial")
	runTestGit(t, repositoryPath, "add", "--", "tracked.txt")
	runTestGit(t, repositoryPath, "commit", "--quiet", "-m", "initial")

	return repositoryPath
}

func runTestGit(t *testing.T, repositoryPath string, arguments ...string) string {
	t.Helper()

	commandArguments := append([]string{"-C", repositoryPath}, arguments...)
	command := exec.Command("git", commandArguments...)
	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("git %s failed: %v\n%s", strings.Join(arguments, " "), err, output)
	}

	return string(output)
}

func writeTestFile(t *testing.T, repositoryPath string, relativePath string, content string) {
	t.Helper()

	path := filepath.Join(repositoryPath, filepath.FromSlash(relativePath))
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("creating parent directory: %v", err)
	}
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatalf("writing %s: %v", relativePath, err)
	}
}
