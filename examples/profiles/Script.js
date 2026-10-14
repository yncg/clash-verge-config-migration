// ============================================================
// 脱敏示例文件 —— Script.js（全局脚本模板）
// ============================================================
// Clash Verge 支持「脚本」型增强：在订阅配置被加载前，
// 用 JavaScript 对它做一次加工，然后返回处理后的 config。
//
// 这个文件是所有订阅共享的全局脚本（uid: Script）。
// 下面演示在规则列表最前面插入自定义规则。
// ============================================================

// 脚本入口：Clash Verge 会调用它，并把订阅配置作为 config 传入
function main(config, profileName) {
  if (!config.rules) {
    config.rules = [];
  }

  // unshift 插到规则列表最前面 —— 越靠前优先级越高
  config.rules.unshift(
    "DOMAIN-SUFFIX,adobe.com,REJECT",        // 拦截 Adobe 相关域名
    "DOMAIN-SUFFIX,puds.ucweb.com,REJECT",   // 拦截 UC 浏览器推送
    "DOMAIN-SUFFIX,puds.quark.com,REJECT",   // 拦截夸克浏览器推送
    "IP-CIDR,192.168.1.0/24,DIRECT",         // 局域网直连，不走代理
    "GEOIP,CN,DIRECT"                        // 国内流量直连
  );

  return config;
}
