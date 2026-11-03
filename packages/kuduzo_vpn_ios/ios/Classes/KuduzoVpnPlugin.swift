import Flutter
import Kuduzocore
import NetworkExtension
import UIKit

/// Связь Flutter ↔ системный VPN iOS.
/// Методы: prepare → Bool, start {config, name}, stop. События: connecting / connected / disconnected / error:текст.
public class KuduzoVpnPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var manager: NETunnelProviderManager?
  private var observer: NSObjectProtocol?
  private var wasConnecting = false

  private static var extensionId: String {
    (Bundle.main.bundleIdentifier ?? "ru.kuduzo.kuduzo") + ".PacketTunnel"
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = KuduzoVpnPlugin()
    let channel = FlutterMethodChannel(name: "kuduzo/vpn", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    let events = FlutterEventChannel(name: "kuduzo/vpn/events", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
  }

  // MARK: - FlutterStreamHandler

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    loadManager { [weak self] m, _ in
      guard let self = self, let m = m else { return }
      self.manager = m
      self.observe(m)
      self.emitStatus(m.connection.status)
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  // MARK: - Методы

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "prepare":
      loadManager { [weak self] m, error in
        guard let self = self, let m = m, error == nil else {
          DispatchQueue.main.async { result(Self.flutterError(error)) }
          return
        }
        self.configure(m, config: nil, options: nil) { err in
          DispatchQueue.main.async {
            if let err = err {
              result(Self.flutterError(err))
            } else {
              self.manager = m
              self.observe(m)
              result(true)
            }
          }
        }
      }

    case "configure":
      let args = call.arguments as? [String: Any] ?? [:]
      loadManager { [weak self] m, _ in
        guard let self = self, let m = m else {
          DispatchQueue.main.async { result(nil) }
          return
        }
        self.configure(m, config: nil, options: args) { _ in
          DispatchQueue.main.async { result(nil) }
        }
      }

    case "message":
      // Команда расширению VPN (stats, logs, ping…). Ответ — текст или «err:причина».
      let args = call.arguments as? [String: Any] ?? [:]
      ask(args["text"] as? String ?? "") { result($0) }

    // Ядро Xray внутри самого приложения: пинг при выключенном VPN и версия ядра.
    case "coreVersion":
      result(KuduzocoreVersion())

    case "coreIcmp", "coreProxy":
      let args = call.arguments as? [String: Any] ?? [:]
      let timeout = args["timeoutMs"] as? Int ?? 5000
      let method = call.method
      DispatchQueue.global(qos: .userInitiated).async {
        let reply: String
        if method == "coreIcmp" {
          reply = KuduzocorePingICMP(args["list"] as? String ?? "", timeout)
        } else {
          reply = KuduzocoreProxyPing(
            args["batch"] as? String ?? "[]",
            args["url"] as? String ?? "",
            args["method"] as? String ?? "GET",
            timeout,
            args["parallel"] as? Int ?? 6)
        }
        DispatchQueue.main.async { result(reply) }
      }

    case "start":
      let args = call.arguments as? [String: Any]
      let config = args?["config"] as? String ?? ""
      loadManager { [weak self] m, error in
        guard let self = self else { return }
        guard let m = m else {
          self.emit("error:" + (error?.localizedDescription ?? "VPN недоступен"))
          DispatchQueue.main.async { result(nil) }
          return
        }
        self.configure(m, config: config, options: args) { err in
          DispatchQueue.main.async {
            if let err = err {
              self.emit("error:" + err.localizedDescription)
              result(nil)
              return
            }
            self.manager = m
            self.observe(m)
            do {
              self.wasConnecting = true
              try m.connection.startVPNTunnel(options: ["config": config as NSString])
            } catch {
              self.emit("error:" + error.localizedDescription)
            }
            result(nil)
          }
        }
      }

    case "stop":
      wasConnecting = false
      // Ручное выключение: временно гасим On Demand, иначе iOS сразу подключит VPN снова.
      func stopIt(_ m: NETunnelProviderManager?) {
        guard let m = m else {
          DispatchQueue.main.async { result(nil) }
          return
        }
        if m.isOnDemandEnabled {
          m.isOnDemandEnabled = false
          m.saveToPreferences { _ in
            m.connection.stopVPNTunnel()
            DispatchQueue.main.async { result(nil) }
          }
        } else {
          m.connection.stopVPNTunnel()
          DispatchQueue.main.async { result(nil) }
        }
      }
      if let m = manager {
        stopIt(m)
      } else {
        loadManager { m, _ in stopIt(m) }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Помощники

  /// Сессия туннеля, если он сейчас работает.
  private static func activeSession(_ m: NETunnelProviderManager?) -> NETunnelProviderSession? {
    guard let s = m?.connection as? NETunnelProviderSession else { return nil }
    switch s.status {
    case .connected, .reasserting: return s
    default: return nil
    }
  }

  /// Вопрос расширению VPN. Ответ — текст или «err:причина».
  /// Если сохранённый менеджер устарел (например, после изменения настроек), находим работающий туннель заново.
  private func ask(_ command: String, _ done: @escaping (String) -> Void) {
    func send(_ session: NETunnelProviderSession) {
      do {
        try session.sendProviderMessage(Data(command.utf8)) { reply in
          let text = reply.flatMap { String(data: $0, encoding: .utf8) } ?? "err:расширение VPN не ответило"
          DispatchQueue.main.async { done(text) }
        }
      } catch {
        let ns = error as NSError
        DispatchQueue.main.async { done("err:\(ns.domain) \(ns.code): \(ns.localizedDescription)") }
      }
    }
    if let s = Self.activeSession(manager) {
      send(s)
      return
    }
    NETunnelProviderManager.loadAllFromPreferences { [weak self] list, error in
      DispatchQueue.main.async {
        guard let self = self else { return }
        let all = list ?? []
        if let m = all.first(where: { Self.activeSession($0) != nil }), let s = Self.activeSession(m) {
          self.manager = m
          self.observe(m)
          send(s)
        } else {
          let status = self.manager.map { "\($0.connection.status.rawValue)" } ?? "нет"
          let extra = error.map { ", \($0.localizedDescription)" } ?? ""
          done("err:работающий туннель не найден (профилей VPN: \(all.count), статус \(status)\(extra))")
        }
      }
    }
  }

  private func loadManager(_ done: @escaping (NETunnelProviderManager?, Error?) -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { list, error in
      if let error = error {
        done(nil, error)
        return
      }
      let mine = list?.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == KuduzoVpnPlugin.extensionId }
      done(mine ?? list?.first ?? NETunnelProviderManager(), nil)
    }
  }

  private static let tunnelKeys = [
    "dns", "mtu", "excludedRoutes", "includedRoutes", "memoryLimit", "allowLan",
    "includeAllNetworks", "disconnectOnSleep", "ctlPort", "ctlToken",
  ]

  private func configure(
    _ m: NETunnelProviderManager, config: String?, options: [String: Any]?,
    _ done: @escaping (Error?) -> Void
  ) {
    let proto = (m.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
    proto.providerBundleIdentifier = KuduzoVpnPlugin.extensionId
    proto.serverAddress = "Kuduzo VPN"
    var stored = proto.providerConfiguration ?? [:]
    if let config = config, !config.isEmpty {
      // Сохраняем конфиг, чтобы VPN можно было включить и из «Настроек» iOS или по On Demand.
      stored["config"] = config
    }
    if let o = options {
      for key in Self.tunnelKeys {
        if let v = o[key] { stored[key] = v }
      }
      if #available(iOS 14.0, *) {
        proto.includeAllNetworks = o["includeAllNetworks"] as? Bool ?? false
      }
      if #available(iOS 14.2, *) {
        proto.excludeLocalNetworks = o["allowLan"] as? Bool ?? true
      }
      proto.disconnectOnSleep = o["disconnectOnSleep"] as? Bool ?? false
      applyOnDemand(m, o)
    }
    proto.providerConfiguration = stored
    m.protocolConfiguration = proto
    m.localizedDescription = "Kuduzo VPN"
    m.isEnabled = true
    m.saveToPreferences { error in
      if let error = error {
        done(error)
        return
      }
      m.loadFromPreferences { done($0) }
    }
  }

  /// Правила On Demand: подключаться в Wi‑Fi / мобильной сети, кроме указанных Wi‑Fi сетей.
  private func applyOnDemand(_ m: NETunnelProviderManager, _ o: [String: Any]) {
    let enabled = o["onDemand"] as? Bool ?? false
    guard enabled else {
      m.isOnDemandEnabled = false
      m.onDemandRules = nil
      return
    }
    var rules: [NEOnDemandRule] = []
    let excluded = (o["onDemandExcludedSsids"] as? [String] ?? []).filter { !$0.isEmpty }
    if !excluded.isEmpty {
      let r = NEOnDemandRuleDisconnect()
      r.interfaceTypeMatch = .wiFi
      r.ssidMatch = excluded
      rules.append(r)
    }
    let wifi: NEOnDemandRule = (o["onDemandWifi"] as? Bool ?? true) ? NEOnDemandRuleConnect() : NEOnDemandRuleIgnore()
    wifi.interfaceTypeMatch = .wiFi
    rules.append(wifi)
    let cell: NEOnDemandRule = (o["onDemandCellular"] as? Bool ?? true) ? NEOnDemandRuleConnect() : NEOnDemandRuleIgnore()
    cell.interfaceTypeMatch = .cellular
    rules.append(cell)
    m.onDemandRules = rules
    m.isOnDemandEnabled = true
  }

  private static func flutterError(_ error: Error?) -> FlutterError {
    let ns = error as NSError?
    let text = ns.map { "\($0.domain) \($0.code): \($0.localizedDescription)" } ?? "нет ответа от системы"
    return FlutterError(code: "vpn_prepare", message: text, details: nil)
  }

  private func observe(_ m: NETunnelProviderManager) {
    if let o = observer { NotificationCenter.default.removeObserver(o) }
    observer = NotificationCenter.default.addObserver(
      forName: .NEVPNStatusDidChange, object: m.connection, queue: .main
    ) { [weak self] _ in
      self?.emitStatus(m.connection.status)
    }
  }

  private func emitStatus(_ status: NEVPNStatus) {
    switch status {
    case .connected:
      wasConnecting = false
      emit("connected")
    case .connecting, .reasserting:
      emit("connecting")
    case .disconnected, .invalid:
      if wasConnecting, #available(iOS 16.0, *), let m = manager {
        wasConnecting = false
        m.connection.fetchLastDisconnectError { [weak self] error in
          DispatchQueue.main.async {
            if let error = error {
              self?.emit("error:" + error.localizedDescription)
            } else {
              self?.emit("disconnected")
            }
          }
        }
      } else {
        wasConnecting = false
        emit("disconnected")
      }
    case .disconnecting:
      break
    @unknown default:
      break
    }
  }

  private func emit(_ s: String) {
    DispatchQueue.main.async { [weak self] in self?.sink?(s) }
  }
}
