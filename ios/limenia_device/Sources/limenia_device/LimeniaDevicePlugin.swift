import DeviceCheck
import Flutter

/// DeviceCheck tokens for the device connector of Limenia. Never logs tokens.
public class LimeniaDevicePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "eu.limenia/limenia_device", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(LimeniaDevicePlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(DCDevice.current.isSupported)
    case "requestToken":
      // The request hash is not used: DeviceCheck has no binding to a request.
      guard DCDevice.current.isSupported else {
        result(FlutterError(code: "unsupported", message: "DeviceCheck is not supported on this device", details: nil))
        return
      }
      DCDevice.current.generateToken { token, error in
        DispatchQueue.main.async {
          if let token = token {
            result(token.base64EncodedString())
          } else if let error = error as? DCError, error.code == .featureUnsupported {
            result(FlutterError(code: "unsupported", message: error.localizedDescription, details: error.code.rawValue))
          } else {
            let nsError = error as NSError?
            result(FlutterError(
              code: "failed", message: nsError?.localizedDescription ?? "DeviceCheck returned no token",
              details: nsError?.code))
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
