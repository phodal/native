import UIKit
import WebKit

final class ZeroNativeHostViewController: UIViewController {
    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let statusLabel = UILabel()
    private let backButton = UIButton(type: .system)
    private let refreshButton = UIButton(type: .system)
    private let webView = WKWebView(frame: .zero)
    private var webViewBottomConstraint: NSLayoutConstraint?
    private var nativeApp: UnsafeMutableRawPointer?
    private var keyboardBottomInset: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground
        configureHeader()

        headerView.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)
        view.addSubview(webView)
        let webViewBottomConstraint = webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        self.webViewBottomConstraint = webViewBottomConstraint
        NSLayoutConstraint.activate([
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 104),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            webViewBottomConstraint,
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardFrameWillChange), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)

        nativeApp = zero_native_app_create()
        if let nativeApp {
            zero_native_app_start(nativeApp)
        }

        webView.loadHTMLString(Self.html, baseURL: nil)
    }

    func activateNativeApp() {
        guard let nativeApp else { return }
        zero_native_app_activate(nativeApp)
    }

    func deactivateNativeApp() {
        guard let nativeApp else { return }
        zero_native_app_deactivate(nativeApp)
    }

    private func configureHeader() {
        headerView.backgroundColor = .secondarySystemBackground

        titleLabel.text = "Mobile Shell"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.text = "Native header with WebView workspace"
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.adjustsFontForContentSizeCategory = true

        statusLabel.text = "System WebView"
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textColor = .secondaryLabel
        statusLabel.backgroundColor = .tertiarySystemFill
        statusLabel.layer.cornerRadius = 11
        statusLabel.layer.masksToBounds = true
        statusLabel.textAlignment = .center

        backButton.setTitle("Back", for: .normal)
        backButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        backButton.addTarget(self, action: #selector(sendBackCommand), for: .touchUpInside)

        refreshButton.setTitle("Refresh", for: .normal)
        refreshButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        refreshButton.addTarget(self, action: #selector(sendRefreshCommand), for: .touchUpInside)

        [titleLabel, subtitleLabel, statusLabel, backButton, refreshButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 18),
            statusLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -20),
            statusLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 112),
            statusLabel.heightAnchor.constraint(equalToConstant: 24),
            refreshButton.trailingAnchor.constraint(equalTo: statusLabel.trailingAnchor),
            refreshButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            backButton.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -12),
            backButton.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: backButton.leadingAnchor, constant: -16),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
        ])
    }

    @objc private func sendBackCommand() {
        dispatchNativeCommand("mobile.back")
    }

    @objc private func sendRefreshCommand() {
        dispatchNativeCommand("mobile.refresh")
    }

    private func dispatchNativeCommand(_ command: String) {
        guard let nativeApp else { return }
        command.withCString { pointer in
            zero_native_app_command(nativeApp, pointer, UInt(command.utf8.count))
        }
        let count = zero_native_app_last_command_count(nativeApp)
        let name = String(cString: zero_native_app_last_command_name(nativeApp))
        statusLabel.text = "\(name) #\(count)"
        zero_native_app_frame(nativeApp)
    }

    @objc private func keyboardFrameWillChange(_ notification: Notification) {
        guard let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else { return }
        let keyboardFrame = view.convert(frameValue.cgRectValue, from: nil)
        let overlap = max(0, view.bounds.maxY - keyboardFrame.minY)
        keyboardBottomInset = overlap
        webViewBottomConstraint?.constant = -overlap
        animateKeyboardLayout(notification)
        sendViewportUpdate()
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        keyboardBottomInset = 0
        webViewBottomConstraint?.constant = 0
        animateKeyboardLayout(notification)
        sendViewportUpdate()
    }

    private func animateKeyboardLayout(_ notification: Notification) {
        let userInfo = notification.userInfo ?? [:]
        let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curve = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 0
        let options = UIView.AnimationOptions(rawValue: curve << 16)
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.view.layoutIfNeeded()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sendViewportUpdate()
    }

    private func sendViewportUpdate() {
        guard let nativeApp else { return }
        let scale = Float(view.window?.screen.scale ?? UIScreen.main.scale)
        let safe = view.safeAreaInsets
        zero_native_app_viewport(
            nativeApp,
            Float(webView.bounds.width),
            Float(webView.bounds.height),
            scale,
            nil,
            Float(safe.top),
            Float(safe.right),
            Float(safe.bottom),
            Float(safe.left),
            0,
            0,
            Float(keyboardBottomInset),
            0
        )
        zero_native_app_frame(nativeApp)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        guard let nativeApp else { return }
        zero_native_app_stop(nativeApp)
        zero_native_app_destroy(nativeApp)
    }

    private static let html = """
    <!doctype html>
    <html>
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <body style="margin:0;font-family:-apple-system,system-ui;background:#f7f8fa;color:#171717;">
        <main style="padding:28px 22px;display:grid;gap:16px;">
          <h1 style="margin:0;font-size:30px;letter-spacing:0;">Workspace</h1>
          <p style="margin:0;color:#5f6672;line-height:1.5;">This content is rendered by WKWebView while the header remains native UIKit.</p>
          <section style="display:grid;gap:10px;">
            <div style="padding:14px;border:1px solid #e1e5ea;border-radius:8px;background:white;">Inbox review</div>
            <div style="padding:14px;border:1px solid #e1e5ea;border-radius:8px;background:white;">Sync queue</div>
            <div style="padding:14px;border:1px solid #e1e5ea;border-radius:8px;background:white;">Offline cache</div>
          </section>
        </main>
      </body>
    </html>
    """
}
