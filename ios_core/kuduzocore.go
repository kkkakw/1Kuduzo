// Package kuduzocore — тонкая обёртка над Xray-core для iOS Network Extension.
// Собирается gomobile в Kuduzocore.xcframework (см. .github/workflows/build.yml).
package kuduzocore

import (
	"bufio"
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"os"
	"runtime"
	"runtime/debug"
	"strconv"
	"strings"
	"sync"
	"time"

	xlog "github.com/xtls/xray-core/common/log"
	xnet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/stats"
	"github.com/xtls/xray-core/infra/conf/serial"
	_ "github.com/xtls/xray-core/main/distro/all"
	"golang.org/x/net/icmp"
	"golang.org/x/net/ipv4"
	"golang.org/x/net/ipv6"
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
	stopControl()
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

// ---------- Команды приложения ----------

// HandleMessage — команды приложения. Приходят двумя путями: сообщением iOS (sendProviderMessage)
// и по локальному каналу 127.0.0.1 (если подпись приложения не даёт iOS передавать сообщения).
//
//	stats                                  → «отправлено,получено,память»
//	logs                                   → журнал ядра
//	ping\n<мс>\n<id адрес порт>…          → TCP-пинг
//	icmp\n<мс>\n<id адрес порт>…          → ICMP-пинг
//	proxy\n<мс>\n<GET|HEAD>\n<url>\n<JSON> → пинг через прокси, JSON: [{"id":…,"config":{…}}]
func HandleMessage(msg string) string {
	cmd, rest, _ := strings.Cut(msg, "\n")
	cmd = strings.TrimSpace(cmd)
	switch cmd {
	case "stats":
		return QueryTraffic() + "," + strconv.FormatInt(MemoryUsage(), 10)
	case "logs":
		return Logs()
	case "ping", "icmp":
		t, list, _ := strings.Cut(rest, "\n")
		ms, _ := strconv.Atoi(strings.TrimSpace(t))
		if cmd == "ping" {
			return PingTCP(list, ms)
		}
		return PingICMP(list, ms)
	case "proxy":
		f := strings.SplitN(rest, "\n", 4)
		if len(f) < 4 {
			return ""
		}
		ms, _ := strconv.Atoi(strings.TrimSpace(f[0]))
		// В расширении VPN память ограничена — по два сервера одновременно.
		return ProxyPing(f[3], f[2], f[1], ms, 2)
	}
	return ""
}

// ---------- Локальный канал 127.0.0.1 ----------

var (
	ctlMu sync.Mutex
	ctlLn net.Listener
)

// ServeControl открывает канал для приложения на 127.0.0.1:port. Запрос: первая строка — секретный
// ключ, дальше команда HandleMessage, последняя строка «<<end>>». При неверном ключе соединение
// просто закрывается, без ответа. Порт и ключ случайные и меняются при каждом подключении.
func ServeControl(port int, token string) error {
	stopControl()
	if port <= 0 || len(token) < 16 {
		return errors.New("нет порта или ключа")
	}
	ln, err := net.Listen("tcp", "127.0.0.1:"+strconv.Itoa(port))
	if err != nil {
		coreLog.add("[Warning] локальный канал: " + err.Error())
		return err
	}
	ctlMu.Lock()
	ctlLn = ln
	ctlMu.Unlock()
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go serveCtl(c, token)
		}
	}()
	return nil
}

func stopControl() {
	ctlMu.Lock()
	defer ctlMu.Unlock()
	if ctlLn != nil {
		_ = ctlLn.Close()
		ctlLn = nil
	}
}

func serveCtl(c net.Conn, token string) {
	defer c.Close()
	_ = c.SetReadDeadline(time.Now().Add(10 * time.Second))
	r := bufio.NewReader(io.LimitReader(c, 4<<20))
	first, err := r.ReadString('\n')
	if err != nil || subtle.ConstantTimeCompare([]byte(strings.TrimSpace(first)), []byte(token)) != 1 {
		return
	}
	var b strings.Builder
	for {
		line, err := r.ReadString('\n')
		if strings.TrimRight(line, "\r\n") == "<<end>>" {
			break
		}
		b.WriteString(line)
		if err != nil {
			return
		}
	}
	_ = c.SetDeadline(time.Now().Add(5 * time.Minute))
	_, _ = io.WriteString(c, HandleMessage(strings.TrimSuffix(b.String(), "\n")))
}

// ---------- ICMP ----------

// PingICMP — ICMP-эхо до серверов (без прав root: датаграммный сокет ICMP, как в Apple SimplePing).
// list — строки «id адрес [порт]». Ответ — строки «id мс» (-1 — нет ответа).
func PingICMP(list string, timeoutMs int) string {
	type job struct{ id, host string }
	var jobs []job
	for _, line := range strings.Split(list, "\n") {
		f := strings.Fields(line)
		if len(f) >= 2 {
			jobs = append(jobs, job{f[0], f[1]})
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
			res[i] = j.id + " " + strconv.FormatInt(icmpDelay(j.host, uint16(i+1), timeout), 10)
		}(i, j)
	}
	wg.Wait()
	return strings.Join(res, "\n")
}

func icmpDelay(host string, seq uint16, timeout time.Duration) int64 {
	ip := net.ParseIP(host)
	if ip == nil {
		ctx, cancel := context.WithTimeout(context.Background(), timeout)
		addrs, err := net.DefaultResolver.LookupIPAddr(ctx, host)
		cancel()
		if err != nil || len(addrs) == 0 {
			return -1
		}
		ip = addrs[0].IP
	}
	v4 := ip.To4() != nil
	network, listen, proto := "udp6", "::", 58
	var typ icmp.Type = ipv6.ICMPTypeEchoRequest
	if v4 {
		network, listen, proto, typ = "udp4", "0.0.0.0", 1, ipv4.ICMPTypeEcho
	}
	c, err := icmp.ListenPacket(network, listen)
	if err != nil {
		return -1
	}
	defer c.Close()
	id := int(time.Now().UnixNano() & 0xffff)
	msg := icmp.Message{Type: typ, Body: &icmp.Echo{ID: id, Seq: int(seq), Data: []byte("kuduzo-ping")}}
	b, err := msg.Marshal(nil)
	if err != nil {
		return -1
	}
	start := time.Now()
	if _, err := c.WriteTo(b, &net.UDPAddr{IP: ip}); err != nil {
		return -1
	}
	_ = c.SetReadDeadline(start.Add(timeout))
	buf := make([]byte, 1500)
	for {
		n, peer, err := c.ReadFrom(buf)
		if err != nil {
			return -1
		}
		rm, err := icmp.ParseMessage(proto, buf[:n])
		if err != nil {
			continue
		}
		if rm.Type != ipv4.ICMPTypeEchoReply && rm.Type != ipv6.ICMPTypeEchoReply {
			continue
		}
		if e, ok := rm.Body.(*icmp.Echo); !ok || e.Seq != int(seq) {
			continue
		}
		if u, ok := peer.(*net.UDPAddr); ok && !u.IP.Equal(ip) {
			continue
		}
		ms := time.Since(start).Milliseconds()
		if ms < 1 {
			ms = 1
		}
		return ms
	}
}

// ---------- Пинг через прокси ----------

// ProxyPing — HTTP-запрос к url через каждый сервер (временное ядро Xray с одним исходящим).
// batch — JSON [{"id":"…","config":{…}}]. Ответ — строки «id мс» (-1 — нет ответа).
func ProxyPing(batch, url, method string, timeoutMs, parallel int) string {
	var items []struct {
		ID     string          `json:"id"`
		Config json.RawMessage `json:"config"`
	}
	if err := json.Unmarshal([]byte(batch), &items); err != nil {
		return ""
	}
	if parallel <= 0 {
		parallel = 2
	}
	if timeoutMs <= 0 {
		timeoutMs = 7000
	}
	if url == "" {
		url = "https://www.gstatic.com/generate_204"
	}
	if method != "HEAD" {
		method = "GET"
	}
	res := make([]string, len(items))
	sem := make(chan struct{}, parallel)
	var wg sync.WaitGroup
	for i, it := range items {
		wg.Add(1)
		go func(i int, id string, cfg []byte) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			res[i] = id + " " + strconv.FormatInt(proxyDelay(string(cfg), url, method, time.Duration(timeoutMs)*time.Millisecond), 10)
		}(i, it.ID, it.Config)
	}
	wg.Wait()
	debug.FreeOSMemory()
	return strings.Join(res, "\n")
}

func proxyDelay(configJSON, url, method string, timeout time.Duration) int64 {
	cfg, err := serial.LoadJSONConfig(strings.NewReader(configJSON))
	if err != nil {
		return -1
	}
	// Только исходящие: без входящих, журнала и статистики (журнал ядра VPN не трогаем).
	cfg.Inbound = nil
	apps := cfg.App[:0]
	for _, a := range cfg.App {
		if a.Type == "xray.app.proxyman.OutboundConfig" || a.Type == "xray.app.dispatcher.Config" {
			apps = append(apps, a)
		}
	}
	cfg.App = apps
	inst, err := core.New(cfg)
	if err != nil {
		return -1
	}
	if err := inst.Start(); err != nil {
		_ = inst.Close()
		return -1
	}
	defer inst.Close()

	tr := &http.Transport{
		TLSHandshakeTimeout: timeout,
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			dest, err := xnet.ParseDestination(network + ":" + addr)
			if err != nil {
				return nil, err
			}
			return core.Dial(ctx, inst, dest)
		},
	}
	defer tr.CloseIdleConnections()
	client := &http.Client{Transport: tr, Timeout: timeout}
	req, err := http.NewRequest(method, url, nil)
	if err != nil {
		return -1
	}
	req.Header.Set("User-Agent", "Kuduzo")
	start := time.Now()
	resp, err := client.Do(req)
	if err != nil {
		return -1
	}
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
	_ = resp.Body.Close()
	if resp.StatusCode >= 500 {
		return -1
	}
	ms := time.Since(start).Milliseconds()
	if ms < 1 {
		ms = 1
	}
	return ms
}
