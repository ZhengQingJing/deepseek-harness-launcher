import Cocoa

// MARK: - Embedded robust launch script
//
// Self-contained: discovers Node.js (PATH → common locations → nvm), starts
// DeepSeek Harness via `npx @deepseek-ai/dsh web`, waits for the Web UI on
// 127.0.0.1:3080, then opens the default browser. No hardcoded user paths.
let LAUNCH_SCRIPT = #"""
#!/bin/bash
set -u

UI_URL="http://127.0.0.1:3080"
PKG="@deepseek-ai/dsh"
LOG_DIR="$HOME/Library/Logs/DS-H-Launcher"
LOG_FILE="$LOG_DIR/dsh-web.log"
mkdir -p "$LOG_DIR"

echo "DS-H 启动器 — 启动 DeepSeek Harness"
echo "目标地址: $UI_URL"
echo "日志文件: $LOG_FILE"
echo ""

# ---- [1/5] 查找 Node.js ----
echo "[1/5] 查找 Node.js..."
NODE=""
if command -v node >/dev/null 2>&1; then
    NODE="$(command -v node)"
fi
if [ -z "$NODE" ] || [ ! -x "$NODE" ]; then
    for cand in \
        /opt/homebrew/bin/node \
        /usr/local/bin/node \
        /usr/bin/node \
        "$HOME/.local/bin/node" \
        "$HOME/.n/bin/node" \
        "$HOME/.volta/bin/node" \
        "$HOME/.asdf/shims/node"; do
        if [ -x "$cand" ]; then NODE="$cand"; break; fi
    done
fi
if [ -z "$NODE" ] || [ ! -x "$NODE" ]; then
    for cand in "$HOME"/.nvm/versions/node/*/bin/node; do
        if [ -x "$cand" ]; then NODE="$cand"; break; fi
    done
fi

if [ -z "$NODE" ] || [ ! -x "$NODE" ]; then
    echo "[1/5] ✗ 未检测到 Node.js"
    echo ""
    echo "DeepSeek Harness 需要 Node.js 22.19 或更高版本。"
    echo "正在打开 Node.js 官方下载页，请安装 LTS 版本后重新启动本 App。"
    /usr/bin/open "https://nodejs.org/"
    echo "NODE_MISSING"
    exit 2
fi
NODE_DIR="$(cd "$(dirname "$NODE")" 2>/dev/null && pwd)"
echo "[1/5] ✓ Node.js: $NODE"
echo "      版本: $("$NODE" --version 2>/dev/null || echo 未知)"
echo ""

# ---- [2/5] 检查服务是否已在运行 ----
echo "[2/5] 检查服务是否已在运行..."
if /usr/bin/curl -s -o /dev/null --max-time 3 "$UI_URL"; then
    echo "      ✓ 服务已在运行，直接打开浏览器"
    /usr/bin/open "$UI_URL"
    echo "DONE"
    exit 0
fi
echo "      未运行，继续启动流程"
echo ""

# ---- [3/5] 清理可能残留的旧进程（兜底） ----
# 注意：pkill -f 模式用 [b]/[d] 这种正则写法，避免匹配到本脚本自身的命令行（会自杀）。
echo "[3/5] 清理可能残留的旧进程..."
/usr/bin/pkill -9 -f "apps/cli/src/[b]in.ts web" 2>/dev/null
/usr/bin/pkill -9 -f "@deepseek-ai/[d]sh" 2>/dev/null
sleep 1
echo "      清理完成"
echo ""

# ---- [4/5] 启动服务 ----
echo "[4/5] 启动 DeepSeek Harness..."
# 若用户未自定义 npm 镜像，默认走国内镜像，加速 npx 首次下载
if [ -z "${npm_config_registry:-}" ] && [ ! -f "$HOME/.npmrc" ]; then
    export npm_config_registry="https://registry.npmmirror.com/"
fi
export PATH="$NODE_DIR:$PATH"
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

# 本地加速：若存在本地源码构建，直接用 node+tsx 跑（秒开）；否则走 npx（通用）。
LOCAL_DIR="$HOME/Documents/deepseek-harness"
if [ -d "$LOCAL_DIR/node_modules/tsx" ] && [ -f "$LOCAL_DIR/package.json" ]; then
    echo "      检测到本地源码构建，使用本地版本（秒开）"
    cd "$LOCAL_DIR"
    /usr/bin/nohup "$NODE" --import tsx/esm apps/cli/src/bin.ts web > "$LOG_FILE" 2>&1 &
    LAUNCH_PID=$!
    echo "      本地进程已启动 (PID $LAUNCH_PID)"
else
    echo "      使用 npx $PKG web"
    echo "      ⚠ 首次运行需要下载依赖，可能需要几分钟，请耐心等待。"
    /usr/bin/nohup "$NODE_DIR/npx" -y "$PKG" web > "$LOG_FILE" 2>&1 &
    LAUNCH_PID=$!
    echo "      npx 进程已启动 (PID $LAUNCH_PID)"
fi
echo ""

# ---- [5/5] 等待就绪 ----
echo "[5/5] 等待服务就绪（最多 300 秒）..."
ready=0
for i in $(seq 1 150); do
    if /usr/bin/curl -s -o /dev/null --max-time 2 "$UI_URL"; then
        ready=1
        echo "      ✓ 服务已就绪（约 $((i*2)) 秒）"
        break
    fi
    if [ $((i % 15)) -eq 0 ]; then
        echo "      仍在等待... 已 $((i*2)) 秒（首次下载依赖较慢）"
    fi
    sleep 2
done

if [ "$ready" -eq 1 ]; then
    echo ""
    echo "打开浏览器: $UI_URL"
    /usr/bin/open "$UI_URL"
    echo "DONE"
    exit 0
else
    echo "      ✗ 等待超时（300 秒）"
    echo ""
    echo "请检查日志: $LOG_FILE"
    echo "常见原因：网络问题 / Node 版本过低 / 依赖下载失败"
    exit 1
fi
"""#

// MARK: - App delegate
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var statusLabel: NSTextField!
    var logTextView: NSTextView!
    var launchButton: NSButton!
    var openButton: NSButton!
    var quitButton: NSButton!
    var scriptTask: Process?
    var isBusy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.runLaunchScript()
        }
    }

    func setupWindow() {
        let initial = NSRect(x: 0, y: 0, width: 580, height: 480)
        let win = NSWindow(
            contentRect: initial,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "DS-H 启动器"
        win.center()
        win.isReleasedWhenClosed = false

        let content = NSView(frame: initial)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        content.autoresizingMask = [.width, .height]

        let iconView = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.frame = NSRect(x: 20, y: 412, width: 48, height: 48)
        iconView.autoresizingMask = [.minYMargin]
        content.addSubview(iconView)

        let title = NSTextField(labelWithString: "DeepSeek Harness 启动器")
        title.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        title.frame = NSRect(x: 78, y: 432, width: 480, height: 22)
        title.autoresizingMask = [.minYMargin, .width]
        content.addSubview(title)

        statusLabel = NSTextField(labelWithString: "正在启动…")
        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.frame = NSRect(x: 78, y: 412, width: 480, height: 20)
        statusLabel.autoresizingMask = [.minYMargin, .width]
        content.addSubview(statusLabel)

        let scroll = NSScrollView(frame: NSRect(x: 20, y: 80, width: 540, height: 320))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autoresizingMask = [.width, .height]

        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.backgroundColor = NSColor(white: 0.96, alpha: 1)
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.autoresizingMask = [.width, .height]
        scroll.documentView = tv
        logTextView = tv
        content.addSubview(scroll)

        launchButton = NSButton(title: "重新启动", target: self, action: #selector(onLaunch))
        launchButton.bezelStyle = .rounded
        launchButton.frame = NSRect(x: 20, y: 24, width: 110, height: 32)
        launchButton.autoresizingMask = [.minYMargin]
        content.addSubview(launchButton)

        openButton = NSButton(title: "重新打开 Web UI", target: self, action: #selector(onOpenBrowser))
        openButton.bezelStyle = .rounded
        openButton.frame = NSRect(x: 140, y: 24, width: 170, height: 32)
        openButton.autoresizingMask = [.minYMargin]
        openButton.isEnabled = false
        content.addSubview(openButton)

        let revealButton = NSButton(title: "查看日志", target: self, action: #selector(onRevealLog))
        revealButton.bezelStyle = .rounded
        revealButton.frame = NSRect(x: 320, y: 24, width: 110, height: 32)
        revealButton.autoresizingMask = [.minYMargin]
        content.addSubview(revealButton)

        quitButton = NSButton(title: "退出", target: self, action: #selector(onQuit))
        quitButton.bezelStyle = .rounded
        quitButton.frame = NSRect(x: 460, y: 24, width: 100, height: 32)
        quitButton.autoresizingMask = [.minYMargin]
        content.addSubview(quitButton)

        win.contentView = content
        win.makeKeyAndOrderFront(nil)
        window = win
    }

    func appendLog(_ s: String) {
        let prefixed = s.hasSuffix("\n") ? s : s + "\n"
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let storage = self.logTextView.textStorage else { return }
            let attr = NSAttributedString(
                string: prefixed,
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                             .foregroundColor: NSColor.labelColor]
            )
            storage.append(attr)
            self.logTextView.scrollToEndOfDocument(nil)
        }
    }

    func setStatus(_ text: String, color: NSColor? = nil) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.stringValue = text
            if let c = color { self?.statusLabel.textColor = c }
        }
    }

    func setBusy(_ busy: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.isBusy = busy
            self?.launchButton.isEnabled = !busy
        }
    }

    @objc func onLaunch() { runLaunchScript() }

    @objc func onOpenBrowser() {
        guard let url = URL(string: "http://127.0.0.1:3080") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func onRevealLog() {
        let dir = NSHomeDirectory() + "/Library/Logs/DS-H-Launcher"
        let file = dir + "/dsh-web.log"
        if FileManager.default.fileExists(atPath: file) {
            NSWorkspace.shared.open(URL(fileURLWithPath: file))
        } else {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(URL(fileURLWithPath: dir))
        }
    }

    @objc func onQuit() { NSApp.terminate(nil) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Run launch script

    func runLaunchScript() {
        if isBusy { return }
        guard scriptTask == nil || scriptTask!.isRunning == false else { return }

        setBusy(true)
        setStatus("正在启动 DeepSeek Harness…", color: .secondaryLabelColor)
        openButton.isEnabled = false
        logTextView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        appendLog("---- DS-H 启动器 开始执行 ----\n")

        let task = Process()
        scriptTask = task
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", LAUNCH_SCRIPT]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
            self?.appendLog(s)
        }

        task.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            let code = proc.terminationStatus
            DispatchQueue.main.async {
                self?.setBusy(false)
                self?.openButton.isEnabled = true
                switch code {
                case 0:
                    self?.setStatus("✅ 已启动并在浏览器打开 Web UI", color: NSColor.systemGreen)
                    self?.appendLog("\n---- 完成 ----\n")
                case 2:
                    self?.setStatus("⚠️ 未检测到 Node.js，请安装后重试", color: NSColor.systemOrange)
                    self?.appendLog("\n---- 需要安装 Node.js ----\n")
                default:
                    self?.setStatus("❌ 启动失败（点击「查看日志」排查）", color: NSColor.systemRed)
                    self?.appendLog("\n---- 失败 ----\n")
                }
            }
        }

        do {
            try task.run()
        } catch {
            appendLog("无法执行脚本: \(error)\n")
            setStatus("❌ 启动失败", color: NSColor.systemRed)
            setBusy(false)
        }
    }
}

// MARK: - App entry
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.activate(ignoringOtherApps: true)
app.run()