import Kuduzocore
import NetworkExtension

/// Системный VPN-модуль Kuduzo: iOS отдаёт utun, Xray-core читает из него пакеты.
/// Собственные соединения расширения в туннель не попадают — так устроен iOS.
class PacketTunnelProvider: NEPacketTunnelProvider {

  override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
    let saved = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
    func value(_ key: String) -> Any? { options?[key] ?? saved[key] }

    var config = options?["config"] as? String
    if config == nil || config!.isEmpty {
      // Включили из «Настроек» iOS или по правилу On Demand — берём сохранённый конфиг.
      config = saved["config"] as? String
    }
    guard let json = config, !json.isEmpty else {
      completionHandler(Self.error("Нет настроек подключения. Включите VPN из приложения Kuduzo"))
      return
    }

    let mtu = (value("mtu") as? NSNumber)?.intValue ?? Self.mtu(from: json)
    let dnsServer = (value("dns") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "1.1.1.1"
    let included = value("includedRoutes") as? [String] ?? []
    let excluded = value("excludedRoutes") as? [String] ?? []
    let memoryLimit = (value("memoryLimit") as? NSNumber)?.intValue ?? 40

    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

    let (in4, in6) = Self.routes(included)
    let (ex4, ex6) = Self.routes(excluded)

    let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.252"])
    ipv4.includedRoutes = in4.isEmpty && in6.isEmpty ? [NEIPv4Route.default()] : in4
    ipv4.excludedRoutes = ex4
    settings.ipv4Settings = ipv4

    let ipv6 = NEIPv6Settings(addresses: ["fd66:6b75:6475::1"], networkPrefixLengths: [126])
    ipv6.includedRoutes = in4.isEmpty && in6.isEmpty ? [NEIPv6Route.default()] : in6
    ipv6.excludedRoutes = ex6
    settings.ipv6Settings = ipv6

    let dns = NEDNSSettings(servers: [dnsServer])
    dns.matchDomains = [""]
    settings.dnsSettings = dns
    settings.mtu = NSNumber(value: mtu)

    setTunnelNetworkSettings(settings) { [weak self] error in
      guard let self = self else { return }
      if let error = error {
        completionHandler(error)
        return
      }
      guard let fd = self.tunnelFileDescriptor else {
        completionHandler(Self.error("Не найден системный туннель"))
        return
      }
      KuduzocoreSetMemoryLimit(max(20, min(50, memoryLimit)))
      var err: NSError?
      KuduzocoreStart(json, Int(fd), Bundle.main.resourcePath ?? "", &err)
      if err == nil,
         let port = (value("ctlPort") as? NSNumber)?.intValue, port > 0,
         let token = value("ctlToken") as? String, !token.isEmpty {
        // Запасной канал к приложению через 127.0.0.1: сообщения iOS доходят не при любой подписи.
        var ctlErr: NSError?
        KuduzocoreServeControl(port, token, &ctlErr)
      }
      completionHandler(err)
    }
  }

  override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
    var err: NSError?
    KuduzocoreStop(&err)
    completionHandler()
  }

  /// Сообщения от приложения (stats, logs, ping, icmp, proxy) — разбирает ядро, см. HandleMessage.
  /// Долгие команды (пинг) выполняются не в очереди расширения, чтобы не задерживать остальные.
  override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
    let command = String(data: messageData, encoding: .utf8) ?? ""
    DispatchQueue.global(qos: .userInitiated).async {
      let reply = KuduzocoreHandleMessage(command)
      completionHandler?(reply.data(using: .utf8))
    }
  }

  // MARK: - Помощники

  /// Номер дескриптора utun (способ из документации Xray-core для iOS).
  private var tunnelFileDescriptor: Int32? {
    var buf = [CChar](repeating: 0, count: Int(IFNAMSIZ))
    for fd: Int32 in 0...1024 {
      var len = socklen_t(buf.count)
      if getsockopt(fd, 2 /* SYSPROTO_CONTROL */, 2 /* UTUN_OPT_IFNAME */, &buf, &len) == 0,
         String(cString: buf).hasPrefix("utun") {
        return fd
      }
    }
    return packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32
  }

  /// «10.0.0.0/8», «2001:db8::/32», «1.2.3.4» → маршруты iOS.
  private static func routes(_ list: [String]) -> ([NEIPv4Route], [NEIPv6Route]) {
    var v4: [NEIPv4Route] = []
    var v6: [NEIPv6Route] = []
    for item in list {
      let parts = item.split(separator: "/", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
      guard let addr = parts.first, !addr.isEmpty else { continue }
      if addr.contains(":") {
        let len = parts.count > 1 ? (Int(parts[1]) ?? 128) : 128
        v6.append(NEIPv6Route(destinationAddress: addr, networkPrefixLength: NSNumber(value: max(0, min(128, len)))))
      } else if addr.split(separator: ".").count == 4 {
        let len = parts.count > 1 ? (Int(parts[1]) ?? 32) : 32
        v4.append(NEIPv4Route(destinationAddress: addr, subnetMask: mask(len)))
      }
    }
    return (v4, v6)
  }

  private static func mask(_ len: Int) -> String {
    let l = max(0, min(32, len))
    let m: UInt32 = l == 0 ? 0 : ~UInt32(0) << UInt32(32 - l)
    return "\((m >> 24) & 255).\((m >> 16) & 255).\((m >> 8) & 255).\(m & 255)"
  }

  private static func mtu(from json: String) -> Int {
    guard let data = json.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let inbounds = root["inbounds"] as? [[String: Any]] else { return 1500 }
    for inbound in inbounds where (inbound["protocol"] as? String) == "tun" {
      if let s = inbound["settings"] as? [String: Any], let m = s["mtu"] as? Int { return m }
    }
    return 1500
  }

  private static func error(_ text: String) -> NSError {
    NSError(domain: "Kuduzo", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
  }
}
