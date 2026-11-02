// Package kuduzocore — тонкая обёртка над Xray-core для iOS Network Extension.
// Собирается gomobile в Kuduzocore.xcframework (см. .github/workflows/build.yml).
package kuduzocore

import (
	"context"
	"errors"
	"net"
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

// PingTCP — время TCP-соединения до серверов прямо из расширения VPN: его сокеты идут мимо туннеля,
// поэтому замер честный и при включённом VPN (из приложения туннель отвечал бы сам за 1–2 мс).
// list — строки «id адрес порт» через перевод строки. Ответ — строки «id мс» (-1 — нет ответа).
// DNS разрешается заранее и в замер не входит.
func PingTCP(list string, timeoutMs int) string {
	type job struct{ id, host, port string }
	var jobs []job
	for _, line := range strings.Split(list, "\n") {
		f := strings.Fields(line)
		if len(f) == 3 {
			jobs = append(jobs, job{f[0], f[1], f[2]})
		}
	}
	if timeoutMs <= 0 {
		timeoutMs = 3000
	}
	timeout := time.Duration(timeoutMs) * time.Millisecond
	res := make([]string, len(jobs))
	sem := make(chan struct{}, 8)
	var wg sync.WaitGroup
	for i, j := range jobs {
		wg.Add(1)
		go func(i int, j job) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			res[i] = j.id + " " + strconv.FormatInt(tcpDelay(j.host, j.port, timeout), 10)
		}(i, j)
	}
	wg.Wait()
	return strings.Join(res, "\n")
}

func tcpDelay(host, port string, timeout time.Duration) int64 {
	ip := host
	if net.ParseIP(host) == nil {
		ctx, cancel := context.WithTimeout(context.Background(), timeout)
		addrs, err := net.DefaultResolver.LookupIPAddr(ctx, host)
		cancel()
		if err != nil || len(addrs) == 0 {
			return -1
		}
		ip = addrs[0].IP.String()
	}
	start := time.Now()
	c, err := net.DialTimeout("tcp", net.JoinHostPort(ip, port), timeout)
	if err != nil {
		return -1
	}
	ms := time.Since(start).Milliseconds()
	_ = c.Close()
	if ms < 1 {
		ms = 1
	}
	return ms
}
