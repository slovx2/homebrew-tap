# 从源码构建，运行时使用 Homebrew 的 node@24；后台常驻由 brew services 管理。
class CodexHarnessAdapter < Formula
  desc "Use the Codex desktop app to drive Claude Code and Pi over local SSH"
  homepage "https://github.com/slovx2/litch"
  url "https://github.com/slovx2/litch/archive/refs/tags/v0.8.1.tar.gz"
  sha256 "13cff6307c5a77d257daf6eaa515b6c31dda7809e316a4e429bd4bdaf6cdf169"
  license "MIT"

  bottle do
    root_url "https://github.com/slovx2/homebrew-tap/releases/download/codex-harness-adapter-0.8.1"
    sha256 cellar: :any_skip_relocation, arm64_tahoe: "84583b1a894992e3413606bd8cf9bb37966345588f500d6846416dbfc3809f73"
  end

  depends_on "go" => :build
  depends_on :macos
  depends_on "node@24"

  def install
    ENV.prepend_path "PATH", formula_opt_bin("node@24")
    npm_flags = %w[--no-audit --no-fund]
    system "npm", "ci", *npm_flags
    system "npm", "ci", "--prefix", "packages/claude", *npm_flags
    system "npm", "ci", "--prefix", "packages/pi", *npm_flags
    system "npm", "ci", "--prefix", "packages/dsh", *npm_flags
    system "npm", "run", "build"
    # Claude SDK 的可选平台包自带 CLI，适配器只使用用户安装的 claude。
    system "npm", "prune", "--omit=dev", *npm_flags
    system "npm", "prune", "--omit=dev", "--omit=optional", "--prefix", "packages/claude", *npm_flags
    # Pi 本体只是开发依赖（类型与测试），运行时使用用户安装的 pi；裁剪后只留适配器自带的插件。
    system "npm", "prune", "--omit=dev", "--prefix", "packages/pi", *npm_flags
    # prune 会留下空的作用域目录，按内容判断。
    odie "Pi 本体不应随适配器分发" unless Dir["packages/pi/node_modules/@earendil-works/*"].empty?
    # 实验性的 DeepSeek Harness 入口同样只带适配器自己的依赖，dsh 本体由用户安装。
    system "npm", "prune", "--omit=dev", "--prefix", "packages/dsh", *npm_flags
    odie "dsh 本体不应随适配器分发" unless Dir["packages/dsh/node_modules/@deepseek-ai/*"].empty?

    libexec.install "bin", "packages", "scripts", "protocol", "package.json", "node_modules"
    # 包装脚本把 node@24 放到 PATH 最前，doctor 等命令无需 --node。
    (bin/"codex-harness-adapter").write_env_script libexec/"bin/codex-harness-adapter",
                                                   PATH: "#{formula_opt_bin("node@24")}:$PATH"
    prefix.install "LICENSE", "THIRD_PARTY_NOTICES.md"
  end

  def caveats
    <<~EOS
      后台启动（登录后自动运行，崩溃自动重启）：
        brew services start codex-harness-adapter
      日志：#{var}/log/codex-harness-adapter.log
      查看 SSH 连接参数：
        codex-harness-adapter ssh-config
      Claude Code 或 Pi 需单独安装并登录；未安装的引擎只告警，不影响另一个。
      Pi 需用 npm 安装（npm install -g @earendil-works/pi-coding-agent），适配器直接加载这份安装。
      实验性：装有 DeepSeek Harness（npm install -g @deepseek-ai/dsh）时会一并启动 dsh 入口（端口 7333），没装时不提示；
      密钥 DEEPSEEK_API_KEY 写入下面的环境文件。
      环境变量（CHA_CLAUDE_*、PI_CLI、CHA_DSH_CLI、代理等）写入 ~/.codex-harness-adapter/env，每行 KEY=VALUE，修改后重启服务。
    EOS
  end

  service do
    run [opt_bin/"codex-harness-adapter", "start"]
    keep_alive true
    environment_variables PATH: std_service_path_env
    log_path var/"log/codex-harness-adapter.log"
    error_log_path var/"log/codex-harness-adapter.log"
  end

  test do
    assert_match "start|init|serve|ssh-config|doctor", shell_output("#{bin}/codex-harness-adapter --help")
    assert_path_exists libexec/"packages/claude/dist/claude/src/adapter.mjs"
    assert_path_exists libexec/"packages/pi/dist/pi/src/adapter.mjs"
    refute_path_exists libexec/"packages/pi/node_modules/@earendil-works/pi-coding-agent"
    assert_path_exists libexec/"packages/dsh/dist/dsh/src/adapter.mjs"
    refute_path_exists libexec/"packages/dsh/node_modules/@deepseek-ai/dsh"
    assert_path_exists libexec/"packages/device/dist/device/src/main.mjs"
    assert_match version.to_s, shell_output("#{bin}/codex-harness-adapter version")
  end
end
