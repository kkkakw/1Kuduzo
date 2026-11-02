import Flutter
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
          DispatchQueue.main.async { result(false) }
          return
        }
        self.configure(m, config: nil) { err in
          DispatchQueue.main.async {
            if err != nil {
              result(false)
            } else {
              self.manager = m
              self.observe(m)
              result(true)
            }
          }
        }
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
        self.configure(m, config: config) { err in
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
      if let m = manager {
        m.connection.stopVPNTunnel()
        result(nil)
      } else {
        loadManager { m, _ in
          m?.connection.stopVPNTunnel()
          DispatchQueue.main.async { result(nil) }
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Помощники

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

  private func configure(_ m: NETunnelProviderManager, config: String?, _ done: @escaping (Error?) -> Void) {
    let proto = (m.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
    proto.providerBundleIdentifier = KuduzoVpnPlugin.extensionId
    proto.serverAddress = "Kuduzo VPN"
    if let config = config, !config.isEmpty {
      // Сохраняем конфиг, чтобы VPN можно было включить и из «Настроек» iOS.
      proto.providerConfiguration = ["config": config]
    }
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
