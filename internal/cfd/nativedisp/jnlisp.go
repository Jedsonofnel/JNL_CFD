//go:build !wasm

package nativedisp

import (
	_ "embed"
	"sync"

	"github.com/Jedsonofnel/jnlcfd/internal/cfd/geometry"
	"github.com/hajimehoshi/ebiten/v2"
	jnl "jedn.dev/jnlisp"
)

var NS *jnl.Namespace

//go:embed nativedisp.jnl
var nsSrc string

//
// Viewer manager - runs ebiten in goroutine with command channel
//

type viewerCommand struct {
	viewer ebiten.Game
	done   chan struct{}
}

type viewerManager struct {
	commandChan chan viewerCommand
	closeChan   chan struct{}
	running     bool
	mu          sync.Mutex
}

var globalManager *viewerManager
var managerMu sync.Mutex

func getOrCreateManager() *viewerManager {
	managerMu.Lock()
	defer managerMu.Unlock()

	if globalManager == nil {
		globalManager = &viewerManager{
			commandChan: make(chan viewerCommand, 1),
			closeChan:   make(chan struct{}),
		}
	}
	return globalManager
}

func (vm *viewerManager) start() {
	vm.mu.Lock()
	if vm.running {
		vm.mu.Unlock()
		return
	}
	vm.running = true
	vm.mu.Unlock()

	go vm.runLoop()
}

func (vm *viewerManager) runLoop() {
	var currentViewer ebiten.Game
	var gameRunning bool
	var gameErrChan chan error

	for {
		select {
		case cmd := <-vm.commandChan:
			// If game is running, let it finish first
			if gameRunning {
				<-gameErrChan
				gameRunning = false
			}

			currentViewer = cmd.viewer
			gameErrChan = make(chan error, 1)
			gameRunning = true

			// Start new game in goroutine
			go func(g ebiten.Game, errChan chan error) {
				errChan <- ebiten.RunGame(g)
			}(currentViewer, gameErrChan)

			close(cmd.done)

		case <-vm.closeChan:
			vm.mu.Lock()
			vm.running = false
			vm.mu.Unlock()
			return
		}
	}
}

func (vm *viewerManager) showViewer(viewer ebiten.Game) {
	vm.start()

	done := make(chan struct{})
	select {
	case vm.commandChan <- viewerCommand{viewer: viewer, done: done}:
		<-done
	default:
		// Channel full, skip
	}
}

func (vm *viewerManager) close() {
	vm.mu.Lock()
	if !vm.running {
		vm.mu.Unlock()
		return
	}
	vm.mu.Unlock()

	select {
	case vm.closeChan <- struct{}{}:
	default:
	}
}

//
// JNLisp bindings
//

func init() {
	NS = jnl.NewNamespace("jnl.cfd.nativedisp", nsSrc)

	// Domain viewer
	jnl.CreatePredicate[*DomainViewer](NS, "domain-viewer")
	NS.BindNativeFn(".show-domain",
		jnl.PosArity("domain", "width", "height"),
		showDomain)

	// Mesh viewer
	jnl.CreatePredicate[*MeshViewer](NS, "mesh-viewer")
	NS.BindNativeFn(".show-mesh",
		jnl.PosArity("mesh", "width", "height"),
		showMesh)

	// Viewer control
	NS.BindNativeFn(".viewer-close", jnl.ZeroArity(), closeViewer)
}

// Sexp implementations

func (dv *DomainViewer) String() string {
	return jnl.FormatNonReadable("cfd", "domain-viewer")
}

func (dv *DomainViewer) Type() string {
	return "domain-viewer"
}

func (mv *MeshViewer) String() string {
	return jnl.FormatNonReadable("cfd", "mesh-viewer")
}

func (mv *MeshViewer) Type() string {
	return "mesh-viewer"
}

func showDomain(ctx *jnl.CallContext) (jnl.Sexp, error) {
	domain := jnl.GetArg[*geometry.Domain](ctx)
	width := jnl.GetArg[jnl.Int](ctx)
	height := jnl.GetArg[jnl.Int](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	viewer := NewDomainViewer(domain, int(width), int(height))
	mgr := getOrCreateManager()
	mgr.showViewer(viewer)

	return viewer, nil
}

func showMesh(ctx *jnl.CallContext) (jnl.Sexp, error) {
	mesh := jnl.GetArg[*geometry.Mesh](ctx)
	width := jnl.GetArg[jnl.Int](ctx)
	height := jnl.GetArg[jnl.Int](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	viewer := NewMeshViewer(mesh, int(width), int(height))
	mgr := getOrCreateManager()
	mgr.showViewer(viewer)

	return viewer, nil
}

func closeViewer(ctx *jnl.CallContext) (jnl.Sexp, error) {
	if err := ctx.Validate(); err != nil {
		return nil, err
	}
	mgr := getOrCreateManager()
	mgr.close()
	return jnl.Nil{}, nil
}
