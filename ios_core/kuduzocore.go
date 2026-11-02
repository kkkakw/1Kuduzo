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

	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/stats"
	"github.com/xtls/xray-core/infra/conf/serial"
	_ "github.com/xtls/xray-core/main/distro/all"
)

var (
	mu       sync.Mutex
	instance *core.Instance
)

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

	cfg, err := serial.LoadJSONConfig(strings.NewReader(configJSON))
	if err != nil {
		return errors.New("ошибка конфига: " + err.Error())
	}
	inst, err := core.New(cfg)
	if err != nil {
		return errors.New("ошибка ядра: " + err.Error())
	}
	if err := inst.Start(); err != nil {
		_ = inst.Close()
		return errors.New("не удалось запустить ядро: " + err.Error())
	}
	instance = inst
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
	return err
}

// Version — версия Xray-core.
func Version() string {
	return core.Version()
}

// QueryTraffic — «отправлено,получено» байт через сервер с прошлого вызова (счётчики обнуляются).
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
		up = c.Set(0)
	}
	if c := m.GetCounter("outbound>>>proxy>>>traffic>>>downlink"); c != nil {
		down = c.Set(0)
	}
	return strconv.FormatInt(up, 10) + "," + strconv.FormatInt(down, 10)
}

// MemoryUsage — сколько памяти (байт) занимает ядро Go в расширении VPN.
func MemoryUsage() int64 {
	var ms runtime.MemStats
	runtime.ReadMemStats(&ms)
	return int64(ms.Sys - ms.HeapReleased)
}
