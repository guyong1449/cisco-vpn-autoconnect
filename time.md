现在脚本里和 GUI 里能看到/影响到的等待时间，完整清单如下。

**连接主流程**
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:1974) 一段：

- 启动 `vpncli` 后，先等 `1 s`
- 发送 `connect <server>` 后，等 `3s`
- 选 group 后，等 `1 s`
- 发 username 后，等 1`s`
- 发 password 后，等 `3s`
- 进入 MFA 前，再固定等 `3s`

**MFA / DUO 相关**

- 删掉: 等待抓 DUO push 菜单：  
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:2009)
- DUO 批准和隧道建立等待：最多 `50s`
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:2043)
- 上面这 `50s` 期间，轮询间隔是 `300ms`
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:1859)
- 证书/banner 自动确认第一次发送是在 DUO 后第 2`s`  
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:1860)
- 之后每隔 1`s` 重发一次 `y`
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:1861)

**vpncli 退出后的二次确认**

- 如果 `vpncli` 在 MFA/banner 阶段提前退出，还会继续查 VPN IP 最多 `5 s`  
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:1870)
- 这段二次查 IP 的轮询间隔也是 `300ms`
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:1845)

**输出读取 / 进程收尾**

- `Read-VpnCliOutputFinal` 默认最多等 `15s`
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:1892)
- 连接成功几条收尾路径分别会用：
  - `6s`
  - `8s`
  - `10s`
  在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:2036), [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:2040), [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:2045)
- 密码后若 `vpncli` 已退出，额外读输出最多 5`s`  
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:1994)
- 早退诊断路径里再读一次最多 `3s`
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:2179)
- 停掉失败中的 `vpncli` 后，最多等 `3s`
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:1909)
- 成功后给 `exit` 收尾最多等 `3s`
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:2057)

**disconnect 相关**

- 启动断开流程后，先等 `2s` 再发 `disconnect`
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:841)
- 发完 `disconnect` / `exit` 后，最多等 `5s`
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:845)
- 关闭 blocker 的循环里，每轮后等 `2s`
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:888)
- blocker 全部结束后，再补等 `1s`
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:894)

**一些通用辅助等待**

- `Wait-ForVpnPrompt` 默认超时 `30s`，轮询 `200ms`
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:1623)
- `Wait-VpnStepOrDelay` 的轮询间隔是 `200ms`
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:1819)
- `删掉 Wait-ForDuoPushOptions` 这个函数
在 [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:1827), [vpn-auto-connect.ps1](/mnt/c/Users/27538/tools/vpn-auto-connect/vpn-auto-connect.ps1:1837)

**GUI 层等待**
在 [tools/vpn-gui.py](/mnt/c/Users/27538/tools/vpn-auto-connect/tools/vpn-gui.py:1391) 一段：

- GUI 发起连接时，PowerShell Stage 1 超时：`240s`
在 [tools/vpn-gui.py](/mnt/c/Users/27538/tools/vpn-auto-connect/tools/vpn-gui.py:1473)
- GUI 发起断开时，PowerShell Stage 1 超时：`30s`
在 [tools/vpn-gui.py](/mnt/c/Users/27538/tools/vpn-auto-connect/tools/vpn-gui.py:1477)
- GUI Stage 2 轮询 VPN IP：最多 `20s`，每 0.5 `s` 轮询一次  
在 [tools/vpn-gui.py](/mnt/c/Users/27538/tools/vpn-auto-connect/tools/vpn-gui.py:1336), [tools/vpn-gui.py](/mnt/c/Users/27538/tools/vpn-auto-connect/tools/vpn-gui.py:1421)
- 连接成功后延迟 1`500ms` 再刷新 connected stats  
在 [tools/vpn-gui.py](/mnt/c/Users/27538/tools/vpn-auto-connect/tools/vpn-gui.py:1323)
- GUI 里几类 PowerShell / vpncli 查询超时基本都是 `10s`
包括：
  - session timing 查询
  - VPN IP 查询
  - `vpncli stats`
  在 [tools/vpn-gui.py](/mnt/c/Users/27538/tools/vpn-auto-connect/tools/vpn-gui.py:1228), [tools/vpn-gui.py](/mnt/c/Users/27538/tools/vpn-auto-connect/tools/vpn-gui.py:1261), [tools/vpn-gui.py](/mnt/c/Users/27538/tools/vpn-auto-connect/tools/vpn-gui.py:1284)
- GUI `_stream_process` 在超时 kill 后，再补等 `5s`
在 [tools/vpn-gui.py](/mnt/c/Users/27538/tools/vpn-auto-connect/tools/vpn-gui.py:1382)
- GUI stdout/stderr 线程 join 各等 `2s`
在 [tools/vpn-gui.py](/mnt/c/Users/27538/tools/vpn-auto-connect/tools/vpn-gui.py:1386)

如果你愿意，我下一步可以把这些整理成一个“总连接时间预算表”，按阶段算一遍理论最长耗时。