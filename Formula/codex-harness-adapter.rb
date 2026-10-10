# 从源码构建，运行时使用 Homebrew 的 node@24；后台常驻由 brew services 管理。
class CodexHarnessAdapter < Formula
  desc "Use the Codex desktop app to drive Claude Code and Pi over local SSH"
  homepage "https://github.com/slovx2/codex-harness-adapter"
  url "https://github.com/slovx2/codex-harness-adapter/archive/refs/tags/v0.4.4.tar.gz"
  sha256 "059048de403ffd5b0c4c9d9ed2906a9e7483969c115849a270ba98cf21869487"
  license "MIT"

  bottle do
    root_url "https://github.com/slovx2/homebrew-tap/releases/download/codex-harness-adapter-0.4.4"
    sha256 cellar: :any_skip_relocation, arm64_tahoe: "0b6410be5da6551e19785c949eaeb5ef180a1d6b6a18414a5b3a31f06a01d213"
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
    system "npm", "run", "build"
    # Claude SDK 的可选平台包自带 CLI，适配器只使用用户安装的 claude；Pi 的可选依赖需保留。
    system "npm", "prune", "--omit=dev", *npm_flags
    system "npm", "prune", "--omit=dev", "--omit=optional", "--prefix", "packages/claude", *npm_flags
    system "npm", "prune", "--omit=dev", "--prefix", "packages/pi", *npm_flags
    # Pi 依赖会带上所有平台的 esbuild，只保留本机平台。
    cpu = Hardware::CPU.arm? ? "arm64" : "x64"
    system "node", "scripts/pi-runtime-platforms.mjs", "prune", "packages/pi/node_modules", "darwin", cpu
    system "node", "scripts/pi-runtime-platforms.mjs", "check", "packages/pi/node_modules", "darwin", cpu
    # pi-tui 在包内同时附带两种 macOS 架构的原生模块，删除非本机架构的一份。
    other = Hardware::CPU.arm? ? "darwin-x64" : "darwin-arm64"
    rm_r Dir["packages/pi/node_modules/**/prebuilds/#{other}"]

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
      环境变量（CHA_CLAUDE_*、PI_CLI、代理等）写入 ~/.codex-harness-adapter/env，每行 KEY=VALUE，修改后重启服务。
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
    assert_match "用法", shell_output("#{bin}/codex-harness-adapter --help")
    assert_path_exists libexec/"packages/claude/dist/claude/src/adapter.mjs"
    assert_path_exists libexec/"packages/pi/dist/pi/src/adapter.mjs"
  end
end
