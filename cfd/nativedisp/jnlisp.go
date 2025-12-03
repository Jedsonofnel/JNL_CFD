//go:build !wasm

package nativedisp

import (
	_ "embed"
	"image/color"
	"sync"

	"github.com/Jedsonofnel/jnlcfd/fvm"
	"github.com/Jedsonofnel/jnlcfd/geometry"
	"github.com/hajimehoshi/ebiten/v2"
	"github.com/hajimehoshi/ebiten/v2/inpututil"
	jnl "jedn.dev/jnlisp"
)

var NS *jnl.Namespace

//go:embed nativedisp.jnl
var nsSrc string

//
// Unified viewer that can display different content types
//

type ViewerContent interface {
	Draw(screen *ebiten.Image)
	Layout(outsideWidth, outsideHeight int) (int, int)
}

type UnifiedViewer struct {
	content     ViewerContent
	mu          sync.RWMutex
	width       int
	height      int
	shouldClose bool
}

func NewUnifiedViewer(width, height int) *UnifiedViewer {
	return &UnifiedViewer{
		width:  width,
		height: height,
	}
}

func (v *UnifiedViewer) SetContent(content ViewerContent) {
	v.mu.Lock()
	defer v.mu.Unlock()
	v.content = content
	v.shouldClose = false // reset close flag when showing new
}

func (v *UnifiedViewer) Update() error {
	// Handle window close button - just clear content instead of closing
	if ebiten.IsWindowBeingClosed() {
		v.mu.Lock()
		v.content = nil
		v.shouldClose = false
		v.mu.Unlock()
	}

	// ESC key also clears content
	if inpututil.IsKeyJustPressed(ebiten.KeyEscape) {
		v.mu.Lock()
		v.content = nil
		v.mu.Unlock()
	}

	return nil
}

func (v *UnifiedViewer) Draw(screen *ebiten.Image) {
	v.mu.RLock()
	content := v.content
	v.mu.RUnlock()

	if content != nil {
		content.Draw(screen)
	} else {
		// Blank screen when no content
		screen.Fill(color.RGBA{240, 240, 240, 255})
	}
}

func (v *UnifiedViewer) Layout(outsideWidth, outsideHeight int) (int, int) {
	v.mu.RLock()
	content := v.content
	v.mu.RUnlock()

	if content != nil {
		return content.Layout(outsideWidth, outsideHeight)
	}
	return v.width, v.height
}

//
// Viewer manager - runs single persistent window
//

type viewerManager struct {
	viewer  *UnifiedViewer
	started bool
	mu      sync.Mutex
}

var globalManager *viewerManager
var managerOnce sync.Once

func getManager() *viewerManager {
	managerOnce.Do(func() {
		globalManager = &viewerManager{
			viewer: NewUnifiedViewer(800, 600),
		}
	})
	return globalManager
}

func (vm *viewerManager) ensureStarted() {
	vm.mu.Lock()
	defer vm.mu.Unlock()

	if !vm.started {
		vm.started = true
		go func() {
			ebiten.SetWindowTitle("JNLisp CFD Viewer")
			ebiten.SetWindowResizingMode(ebiten.WindowResizingModeEnabled)
			ebiten.SetWindowClosingHandled(true) // Intercept close button

			if err := ebiten.RunGame(vm.viewer); err != nil {
				// Window was closed by user, reset started flag
				vm.mu.Lock()
				vm.started = false
				vm.mu.Unlock()
			}
		}()
	}
}

func (vm *viewerManager) showContent(content ViewerContent) {
	vm.ensureStarted()
	vm.viewer.SetContent(content)
}

//
// Adapt existing viewers to ViewerContent interface
//

type domainViewerAdapter struct {
	*DomainViewer
}

func (d *domainViewerAdapter) Draw(screen *ebiten.Image) {
	d.DomainViewer.Draw(screen)
}

func (d *domainViewerAdapter) Layout(w, h int) (int, int) {
	return d.DomainViewer.Layout(w, h)
}

type meshViewerAdapter struct {
	*MeshViewer
}

func (m *meshViewerAdapter) Draw(screen *ebiten.Image) {
	m.MeshViewer.Draw(screen)
}

func (m *meshViewerAdapter) Layout(w, h int) (int, int) {
	return m.MeshViewer.Layout(w, h)
}

type solutionViewerAdapter struct {
	*SolutionViewer
}

func (s *solutionViewerAdapter) Draw(screen *ebiten.Image) {
	s.SolutionViewer.Draw(screen)
}

func (s *solutionViewerAdapter) Layout(w, h int) (int, int) {
	return s.SolutionViewer.Layout(w, h)
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

func (sv *SolutionViewer) String() string {
	return jnl.FormatNonReadable("cfd", "solution-viewer")
}

func (sv *SolutionViewer) Type() string {
	return "solution-viewer"
}

//
// jnlisp bindings
//

func init() {
	NS = jnl.NewNamespace("jnl.cfd.nativedisp", nsSrc)

	// Viewer functions
	NS.BindNativeFn(".show-domain",
		jnl.PosRestArity("domain", "width", "height"),
		showDomain)
	NS.BindNativeFn(".show-mesh",
		jnl.PosRestArity("mesh", "width", "height"),
		showMesh)
	NS.BindNativeFn(".show-solution",
		jnl.PosRestArity("mesh", "field", "width", "height"),
		showSolution)
	NS.BindNativeFn(".clear-viewer", jnl.ZeroArity(), clearViewer)
}

// Native functions

func showDomain(ctx *jnl.CallContext) (jnl.Sexp, error) {
	domain := jnl.GetArg[*geometry.Domain](ctx)
	widthArgs := jnl.GetVariadic[jnl.Int](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	width, height := 800, 600
	if len(widthArgs) >= 2 {
		width = int(widthArgs[0])
		height = int(widthArgs[1])
	}

	dv := NewDomainViewer(domain, width, height)
	adapter := &domainViewerAdapter{dv}

	mgr := getManager()
	mgr.showContent(adapter)

	return jnl.Nil{}, nil
}

func showMesh(ctx *jnl.CallContext) (jnl.Sexp, error) {
	mesh := jnl.GetArg[*geometry.Mesh](ctx)
	sizeArgs := jnl.GetVariadic[jnl.Int](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	width, height := 800, 600
	if len(sizeArgs) >= 2 {
		width = int(sizeArgs[0])
		height = int(sizeArgs[1])
	}

	mv := NewMeshViewer(mesh, width, height)
	adapter := &meshViewerAdapter{mv}

	mgr := getManager()
	mgr.showContent(adapter)

	return jnl.Nil{}, nil
}

func showSolution(ctx *jnl.CallContext) (jnl.Sexp, error) {
	mesh := jnl.GetArg[*geometry.Mesh](ctx)
	field := jnl.GetArg[*fvm.Field](ctx)
	sizeArgs := jnl.GetVariadic[jnl.Int](ctx)
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	width, height := 800, 600
	if len(sizeArgs) >= 2 {
		width = int(sizeArgs[0])
		height = int(sizeArgs[1])
	}

	if field.IsScalar() {
		return nil, jnl.NewRuntimeError(
			jnl.ErrArgType,
			"cannot visualize constant field",
		)
	}

	sv := NewSolutionViewer(mesh, field.Values, width, height)
	adapter := &solutionViewerAdapter{sv}

	mgr := getManager()
	mgr.showContent(adapter)

	return jnl.Nil{}, nil
}

func clearViewer(ctx *jnl.CallContext) (jnl.Sexp, error) {
	if err := ctx.Validate(); err != nil {
		return nil, err
	}

	mgr := getManager()
	mgr.viewer.SetContent(nil)

	return jnl.Nil{}, nil
}
