import UIKit
import ObjectiveC
import UniformTypeIdentifiers

/// Presents the document picker straight from the top view controller,
/// without any SwiftUI sheet in between. Sheets that open and instantly
/// close again are a known failure mode - this avoids it entirely.
enum PickerPresenter {
    private static var delegateKey: UInt8 = 0

    static func present(
        types: [UTType],
        allowsMultiple: Bool,
        onPick: @escaping ([URL]) -> Void
    ) {
        dismissKeyboard()
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = allowsMultiple
        let delegate = PickerDelegate(onPick: onPick)
        picker.delegate = delegate
        objc_setAssociatedObject(
            picker,
            &delegateKey,
            delegate,
            .OBJC_ASSOCIATION_RETAIN
        )
        guard let top = topController() else { return }
        if top.presentedViewController != nil {
            top.dismiss(animated: false)
        }
        top.present(picker, animated: true)
    }

    private static func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
    }

    private static func topController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController
    ) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topController(base: presented)
        }
        return base
    }
}

private final class PickerDelegate: NSObject, UIDocumentPickerDelegate {
    var onPick: ([URL]) -> Void

    init(onPick: @escaping ([URL]) -> Void) {
        self.onPick = onPick
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        onPick(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
}
