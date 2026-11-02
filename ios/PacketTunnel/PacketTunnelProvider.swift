import Kuduzocore
import NetworkExtension

/// Системный VPN-модуль Kuduzo: iOS отдаёт utun, Xray-core читает из него пакеты.
/// Собственные соединения расширения в туннель не попадают — так устроен iOS.
class PacketTunnelProvider: NEPacketTunnelProvider {

  override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
    var config = options?["config"] as? String
    if config == nil || config!.isEmpty {
      // Включили из «Настроек» iOS — берём сохранённый конфиг.
      config = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration?["config"] as? String
    }
    guard let json = config, !json.isEmpty else {
      completionHandler(Self.error("Нет настроек подключения. Включите VPN из приложения Kuduzo"))
      return
    }

    let mtu = Self.mtu(from: json)
    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
    let ipv4 = NEIPv4Settings(addresses: ["10.10.14.1"], subnetMasks: ["255.255.255.252"])
    ipv4.includedRoutes = [NEIPv4Route.default()]
    settings.ipv4Settings = ipv4
    let ipv6 = NEIPv6Settings(addresses: ["fd66:6b75:6475::1"], networkPrefixLengths: [126])
    ipv6.includedRoutes = [NEIPv6Route.default()]
    settings.ipv6Settings = ipv6
    let dns = NEDNSSettings(servers: ["1.1.1.1"])
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
      KuduzocoreSetMemoryLimit(40)
      var err: NSError?
      KuduzocoreStart(json, Int(fd), Bundle.main.resourcePath ?? "", &err)
      completionHandler(err)
    }
  }

  override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
    var err: NSError?
    KuduzocoreStop(&err)
    completionHandler()
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
