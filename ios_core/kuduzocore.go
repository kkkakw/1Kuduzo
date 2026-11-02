// Package kuduzocore — тонкая обёртка над Xray-core для iOS Network Extension.
// Собирается gomobile в Kuduzocore.xcframework (см. .github/workflows/build.yml).
package kuduzocore

import (
	"errors"
	"os"
	"runtime"
	"runtime/debug"
	"strconv"
	"strings"
	"sync"
	"time"

	xlog "github.com/xtls/xray-core/common/log"
	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/stats"
	"github.com/xtls/xray-core/infra/conf/serial"
	_ "github.com/xtls/xray-core/main/distro/all"
)

var (
	mu       sync.Mutex
	instance *core.Instance
	coreLog  = &ringLog{}
)

// ringLog — последние строки журнала ядра (предупреждения и ошибки) для экрана «Журнал».
type ringLog struct {
	mu    sync.Mutex
	lines []string
}

func (r *ringLog) Handle(msg xlog.Message) {
	g, ok := msg.(*xlog.GeneralMessage)
	if !ok || g.Severity > xlog.Severity_Warning {
		return
	}
	r.add(msg.String())
}

// Severity — ядро не собирает отладочные сообщения, которые всё равно не покажем.
func (r *ringLog) Severity() xlog.Severity { return xlog.Severity_Warning }

func (r *ringLog) add(s string) {
	r.mu.Lock()
	r.lines = append(r.lines, time.Now().Format("15:04:05")+"  "+s)
	if len(r.lines) > 300 {
		r.lines = append([]string(nil), r.lines[len(r.lines)-300:]...)
	}
	r.mu.Unlock()
}

// Logs — журнал ядра, строки через перевод строки.
func Logs() string {
	coreLog.mu.Lock()
	defer coreLog.mu.Unlock()
	return strings.Join(coreLog.lines, "\n")
}

// SetMemoryLimit задаёт мягкий лимит памяти Go в мегабайтах.
// Network Extension на iOS завершается системой примерно при 50 МБ.
func SetMemoryLimit(mb int) {
	if mb <= 0 {
		return
	}
	debug.SetMemoryLimit(int64(mb) << 20)
	debug.SetGCPercent(20)
}

// Start запускает Xray с конфигом JSON. fd — дескриптор utun от NetworkExtension,
// assetDir — папка с geoip.dat (ресурсы расширения).
func Start(configJSON string, fd int, assetDir string) error {
	mu.Lock()
	defer mu.Unlock()
	if instance != nil {
		_ = instance.Close()
		instance = nil
	}
	if assetDir != "" {
		_ = os.Setenv("xray.location.asset", assetDir)
	}
	if fd <= 0 {
		return errors.New("не получен дескриптор туннеля")
	}
	_ = os.Setenv("xray.tun.fd", strconv.Itoa(fd))

	fail := func(text string) error {
		coreLog.add("[Error] " + text)
		return errors.New(text)
	}
	cfg, err := serial.LoadJSONConfig(strings.NewReader(configJSON))
	if err != nil {
		return fail("ошибка конфига: " + err.Error())
	}
	inst, err := core.New(cfg)
	if err != nil {
		return fail("ошибка ядра: " + err.Error())
	}
	if err := inst.Start(); err != nil {
		_ = inst.Close()
		return fail("не удалось запустить ядро: " + err.Error())
	}
	instance = inst
	// Ядро на iPhone пишет журнал в память: stdout расширения никто не видит.
	xlog.RegisterHandler(coreLog)
	coreLog.add("[Info] ядро Xray " + core.Version() + " запущено")
	debug.FreeOSMemory()
	return nil
}

// Stop останавливает ядро.
func Stop() error {
	mu.Lock()
	defer mu.Unlock()
	if instance == nil {
		return nil
	}
	err := instance.Close()
	instance = nil
	debug.FreeOSMemory()
	coreLog.add("[Info] ядро остановлено")
	return err
}

// Version — версия Xray-core.
func Version() string {
	return core.Version()
}

// QueryTraffic — «отправлено,получено» байт через сервер с момента подключения.
// Счётчики не обнуляются: если ответ потеряется, итог всё равно будет верным.
func QueryTraffic() string {
	mu.Lock()
	defer mu.Unlock()
	if instance == nil {
		return "0,0"
	}
	m, ok := instance.GetFeature(stats.ManagerType()).(stats.Manager)
	if !ok || m == nil {
		return "0,0"
	}
	var up, down int64
	if c := m.GetCounter("outbound>>>proxy>>>traffic>>>uplink"); c != nil {
		up = c.Value()
	}
	if c := m.GetCounter("outbound>>>proxy>>>traffic>>>downlink"); c != nil {
		down = c.Value()
	}
	return strconv.FormatInt(up, 10) + "," + strconv.FormatInt(down, 10)
}

// MemoryUsage — сколько памяти (байт) занимает ядро Go в расширении VPN.
func MemoryUsage() int64 {
	var ms runtime.MemStats
	runtime.ReadMemStats(&ms)
	return int64(ms.Sys - ms.HeapReleased)
}
