//
//  KeyboardViewController.swift
//  BanPhimTrungKeyboard
//

import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()

    var textBeforeCursor: String {
        textDocumentProxy.documentContextBeforeInput ?? ""
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        model.controller = self

        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let height = view.heightAnchor.constraint(equalToConstant: 310)
        height.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.hasFullAccess = hasFullAccess
        model.needsGlobeKey = needsInputModeSwitchKey
        model.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.stop()
    }

    func insert(_ text: String) {
        textDocumentProxy.insertText(text)
    }

    func deleteBackward() {
        textDocumentProxy.deleteBackward()
    }

    func moveCursor(by offset: Int) {
        guard offset != 0 else { return }
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    /// Keyboard extension không có UIApplication.shared, nên tìm UIApplication qua responder chain.
    func openContainingApp() {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                Self.open(AppGroup.activationURL, with: application)
                return
            }
            responder = current.next
        }
    }

    private static func open(_ url: URL, with application: UIApplication) {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        guard let method = class_getInstanceMethod(UIApplication.self, selector) else { return }
        typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
        let openURL = unsafeBitCast(method_getImplementation(method), to: OpenURL.self)
        openURL(application, selector, url as NSURL, NSDictionary(), nil)
    }
}
