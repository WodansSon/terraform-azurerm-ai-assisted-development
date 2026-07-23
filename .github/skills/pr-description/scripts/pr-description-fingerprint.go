package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"unicode/utf8"
)

type fingerprintResult struct {
	Algorithm   string `json:"algorithm"`
	Fingerprint string `json:"fingerprint"`
}

var commitPattern = regexp.MustCompile(`^[0-9a-f]{40,64}$`)

func main() {
	repositoryRoot := flag.String("repository-root", ".", "path to the Git repository root")
	flag.Parse()

	result, err := fingerprint(*repositoryRoot)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	encoder := json.NewEncoder(os.Stdout)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(result); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func fingerprint(repositoryRoot string) (fingerprintResult, error) {
	repositoryPath, err := filepath.Abs(repositoryRoot)
	if err != nil {
		return fingerprintResult{}, fmt.Errorf("resolving repository root: %w", err)
	}

	insideWorktree, err := runGitOutput(repositoryPath, "rev-parse", "--is-inside-work-tree")
	if err != nil || strings.TrimSpace(string(insideWorktree)) != "true" {
		return fingerprintResult{}, fmt.Errorf("repository root is not a Git worktree: %s", repositoryPath)
	}

	headOutput, err := runGitOutput(repositoryPath, "rev-parse", "HEAD")
	if err != nil {
		return fingerprintResult{}, err
	}

	head := strings.ToLower(strings.TrimSpace(string(headOutput)))
	if !commitPattern.MatchString(head) {
		return fingerprintResult{}, errors.New("Git returned an invalid HEAD commit SHA")
	}

	stagedHash, err := runGitHash(repositoryPath, "diff", "--cached", "--binary", "--full-index", "--no-ext-diff", "--no-textconv", "--no-color", "HEAD", "--")
	if err != nil {
		return fingerprintResult{}, err
	}

	unstagedHash, err := runGitHash(repositoryPath, "diff", "--binary", "--full-index", "--no-ext-diff", "--no-textconv", "--no-color", "--")
	if err != nil {
		return fingerprintResult{}, err
	}

	untrackedHash, err := hashUntrackedFiles(repositoryPath)
	if err != nil {
		return fingerprintResult{}, err
	}

	manifest := fmt.Sprintf("head=%s\nstaged=%s\nunstaged=%s\nuntracked=%s\n", head, stagedHash, unstagedHash, untrackedHash)
	fingerprintHash := sha256.Sum256([]byte(manifest))

	return fingerprintResult{
		Algorithm:   "sha256-v1",
		Fingerprint: hex.EncodeToString(fingerprintHash[:]),
	}, nil
}

func hashUntrackedFiles(repositoryPath string) (string, error) {
	output, err := runGitOutput(repositoryPath, "-c", "core.quotepath=false", "ls-files", "--others", "--exclude-standard", "-z")
	if err != nil {
		return "", err
	}

	paths, err := parseNullTerminatedPaths(output)
	if err != nil {
		return "", err
	}

	sort.Slice(paths, func(left, right int) bool {
		return bytes.Compare(paths[left], paths[right]) < 0
	})

	manifestHash := sha256.New()
	for _, pathBytes := range paths {
		if !utf8.Valid(pathBytes) {
			return "", errors.New("Git returned an untracked path that is not valid UTF-8")
		}

		relativePath := string(pathBytes)
		fullPath := filepath.Join(repositoryPath, filepath.FromSlash(relativePath))
		info, err := os.Lstat(fullPath)
		if err != nil {
			return "", fmt.Errorf("inspecting untracked path %q: %w", relativePath, err)
		}

		kind := "file"
		var contentHash string

		if info.Mode()&os.ModeSymlink != 0 {
			kind = "symlink"
			target, err := os.Readlink(fullPath)
			if err != nil {
				return "", fmt.Errorf("reading untracked symbolic link %q: %w", relativePath, err)
			}
			contentHash = hashBytes([]byte(target))
		} else {
			if !info.Mode().IsRegular() {
				return "", fmt.Errorf("unsupported untracked path type: %s", relativePath)
			}

			contentHash, err = hashFile(fullPath)
			if err != nil {
				return "", fmt.Errorf("hashing untracked file %q: %w", relativePath, err)
			}
		}

		fmt.Fprintf(manifestHash, "path=%d:", len(pathBytes))
		manifestHash.Write(pathBytes)
		fmt.Fprintf(manifestHash, "\nkind=%s\ncontent=%s\n", kind, contentHash)
	}

	return hex.EncodeToString(manifestHash.Sum(nil)), nil
}

func parseNullTerminatedPaths(output []byte) ([][]byte, error) {
	if len(output) == 0 {
		return nil, nil
	}
	if output[len(output)-1] != 0 {
		return nil, errors.New("Git returned an unterminated untracked path list")
	}

	parts := bytes.Split(output[:len(output)-1], []byte{0})
	paths := make([][]byte, 0, len(parts))
	for _, part := range parts {
		if len(part) == 0 {
			continue
		}
		paths = append(paths, bytes.Clone(part))
	}

	return paths, nil
}

func runGitOutput(repositoryPath string, arguments ...string) ([]byte, error) {
	commandArguments := append([]string{"-C", repositoryPath}, arguments...)
	command := exec.Command("git", commandArguments...)
	var stderr bytes.Buffer
	command.Stderr = &stderr

	output, err := command.Output()
	if err != nil {
		return nil, gitError(arguments, stderr.String(), err)
	}

	return output, nil
}

func runGitHash(repositoryPath string, arguments ...string) (string, error) {
	commandArguments := append([]string{"-C", repositoryPath}, arguments...)
	command := exec.Command("git", commandArguments...)
	outputHash := sha256.New()
	var stderr bytes.Buffer
	command.Stdout = outputHash
	command.Stderr = &stderr

	if err := command.Run(); err != nil {
		return "", gitError(arguments, stderr.String(), err)
	}

	return hex.EncodeToString(outputHash.Sum(nil)), nil
}

func gitError(arguments []string, stderr string, err error) error {
	detail := strings.TrimSpace(stderr)
	if detail == "" {
		detail = err.Error()
	}
	return fmt.Errorf("Git command failed (git %s): %s", strings.Join(arguments, " "), detail)
}

func hashFile(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()

	return hashReader(file)
}

func hashReader(reader io.Reader) (string, error) {
	value := sha256.New()
	if _, err := io.Copy(value, reader); err != nil {
		return "", err
	}
	return hex.EncodeToString(value.Sum(nil)), nil
}

func hashBytes(value []byte) string {
	result := sha256.Sum256(value)
	return hex.EncodeToString(result[:])
}
