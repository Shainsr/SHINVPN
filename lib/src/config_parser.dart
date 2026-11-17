part of '../main.dart';

class ParsedRoutingRuleset {
  final String name;
  final List<String> directIps;
  final List<String> directDomains;

  const ParsedRoutingRuleset({
    required this.name,
    required this.directIps,
    required this.directDomains,
  });
}

ParsedRoutingRuleset? parseRoutingInput(String rawInput) {
  final text = rawInput.trim();
  if (text.isEmpty) return null;

  final ips = <String>{};
  final domains = <String>{};
  var name = 'قوانین روتینگ سفارشی';

  String? jsonText;
  if (text.toLowerCase().startsWith('happ://routing/')) {
    var payload = text.substring('happ://routing/'.length);
    if (payload.toLowerCase().startsWith('add/')) {
      payload = payload.substring(4);
    }
    final hashIdx = payload.indexOf('#');
    if (hashIdx >= 0) {
      final frag = LinkParser.safeDecode(payload.substring(hashIdx + 1)).trim();
      if (frag.isNotEmpty) name = frag;
      payload = payload.substring(0, hashIdx);
    }
    final qIdx = payload.indexOf('?');
    if (qIdx >= 0) payload = payload.substring(0, qIdx);
    jsonText = LinkParser.decodeBase64Loose(LinkParser.safeDecode(payload));
  } else if (text.startsWith('{')) {
    jsonText = text;
  } else {
    final decoded = LinkParser.decodeBase64Loose(text);
    if (decoded != null && decoded.trim().startsWith('{')) {
      jsonText = decoded;
    }
  }

  void addIpCandidate(String raw) {
    final s = raw.trim().replaceAll(r'\/', '/');
    if (s.isEmpty) return;
    final lower = s.toLowerCase();
    if (lower.startsWith('geoip:')) {
      if (RegExp(r'^geoip:[a-z0-9_-]+$').hasMatch(lower)) ips.add(lower);
      return;
    }
    final slash = s.indexOf('/');
    final hostPart = slash > 0 ? s.substring(0, slash) : s;
    final prefixPart = slash > 0 ? int.tryParse(s.substring(slash + 1)) : null;
    if (slash > 0 &&
        (prefixPart == null || prefixPart < 0 || prefixPart > 128)) {
      return;
    }
    if (InternetAddress.tryParse(hostPart) != null) {
      ips.add(s);
    }
  }

  void addDomainCandidate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return;
    final lower = s.toLowerCase();
    if (lower.startsWith('geosite:')) {
      if (RegExp(r'^geosite:[a-z0-9_.-]+$').hasMatch(lower)) {
        domains.add(lower);
      }
      return;
    }
    if (lower.startsWith('regexp:') ||
        lower.startsWith('domain:') ||
        lower.startsWith('full:') ||
        lower.startsWith('keyword:')) {
      domains.add(s);
      return;
    }
    if (s.contains('.') && !s.contains(' ') && !s.contains('/')) {
      domains.add('domain:$s');
    }
  }

  if (jsonText != null) {
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is Map) {
        final rawName =
            (decoded['Name'] ?? decoded['name'] ?? '').toString().trim();
        if (rawName.isNotEmpty) name = rawName;

        for (final key in [
          'DirectIp', 'directIp', 'direct_ip', 'ip',
          'DirectIP', 'directIps', 'direct_ips'
        ]) {
          final list = decoded[key];
          if (list is List) {
            for (final item in list) {
              addIpCandidate(item.toString());
            }
          }
        }
        for (final key in [
          'DirectSites',
          'directSites',
          'direct_sites',
          'DirectDomain',
          'directDomain',
          'directDomains',
          'direct_domains',
          'domain',
        ]) {
          final list = decoded[key];
          if (list is List) {
            for (final item in list) {
              addDomainCandidate(item.toString());
            }
          }
        }
      }
    } catch (_) {
      return null;
    }
  } else {
    for (final token in text.split(RegExp(r'[\r\n,;]+'))) {
      final t = token.trim();
      if (t.isEmpty || t.startsWith('#')) continue;
      final before = ips.length;
      addIpCandidate(t);
      if (ips.length == before) {
        addDomainCandidate(t);
      }
    }
  }

  if (ips.isEmpty && domains.isEmpty) return null;
  return ParsedRoutingRuleset(
    name: name,
    directIps: ips.toList(),
    directDomains: domains.toList(),
  );
}

class ParsedLink {
  final String scheme;
  final String userInfo;
  final String host;
  final int port;
  final StringMap params;
  final String fragment;

  ParsedLink(
    this.scheme,
    this.userInfo,
    this.host,
    this.port,
    this.params,
    this.fragment,
  );
}

class ConvertedConfig {
  final String remark;
  final String protocol;
  final JsonMap config;

  ConvertedConfig(this.remark, this.protocol, this.config);
}

class LinkParser {
  static String safeDecode(String s) {
    try {
      return Uri.decodeComponent(s);
    } catch (_) {
      return s;
    }
  }

  static String? decodeBase64Loose(String input) {
    var s = input.trim().replaceAll(RegExp(r'\s+'), '');
    if (s.isEmpty) return null;
    s = s.replaceAll('-', '+').replaceAll('_', '/').replaceAll('=', '');
    final mod = s.length % 4;
    if (mod == 1) return null;
    if (mod == 2) s += '==';
    if (mod == 3) s += '=';
    try {
      return utf8.decode(base64.decode(s), allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  static ServerEndpoint? parseHostPort(String input) {
    final s = input.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('[')) {
      final close = s.indexOf(']');
      if (close <= 0) return null;
      final host = s.substring(1, close);
      final after = s.substring(close + 1);
      if (!after.startsWith(':')) return null;
      final port = int.tryParse(after.substring(1));
      if (port == null || port <= 0 || port > 65535) return null;
      return ServerEndpoint(host, port);
    }
    final colon = s.lastIndexOf(':');
    if (colon <= 0) return null;
    final port = int.tryParse(s.substring(colon + 1));
    if (port == null || port <= 0 || port > 65535) return null;
    return ServerEndpoint(s.substring(0, colon), port);
  }

  static ParsedLink? splitLink(String link) {
    final schemeEnd = link.indexOf('://');
    if (schemeEnd <= 0) return null;
    final scheme = link.substring(0, schemeEnd).toLowerCase();
    var rest = link.substring(schemeEnd + 3);

    var fragment = '';
    final hashIdx = rest.indexOf('#');
    if (hashIdx >= 0) {
      fragment = safeDecode(rest.substring(hashIdx + 1)).trim();
      rest = rest.substring(0, hashIdx);
    }

    var query = '';
    final qIdx = rest.indexOf('?');
    if (qIdx >= 0) {
      query = rest.substring(qIdx + 1);
      rest = rest.substring(0, qIdx);
    }

    final slashIdx = rest.indexOf('/');
    if (slashIdx >= 0) rest = rest.substring(0, slashIdx);

    var userInfo = '';
    final atIdx = rest.lastIndexOf('@');
    if (atIdx >= 0) {
      userInfo = safeDecode(rest.substring(0, atIdx));
      rest = rest.substring(atIdx + 1);
    }

    final hp = parseHostPort(rest);
    if (hp == null) return null;

    final StringMap params = {};
    if (query.isNotEmpty) {
      for (final pair in query.split('&')) {
        if (pair.isEmpty) continue;
        final eq = pair.indexOf('=');
        final key = (eq <= 0 ? pair : pair.substring(0, eq)).toLowerCase();
        final value = eq <= 0 ? '' : safeDecode(pair.substring(eq + 1));
        params[key] = value;
      }
    }
    return ParsedLink(scheme, userInfo, hp.host, hp.port, params, fragment);
  }

  static String _p(StringMap p, String key, [String fallback = '']) {
    final v = p[key];
    return (v == null || v.isEmpty) ? fallback : v;
  }

  static bool _truthy(String? v) {
    if (v == null) return false;
    final l = v.toLowerCase();
    return l == '1' || l == 'true' || l == 'yes';
  }

  static JsonMap _wrap(JsonMap outbound) => {
        'log': {'loglevel': 'none'},
        'inbounds': standardInbounds(),
        'outbounds': [
          outbound,
          {
            'tag': 'direct',
            'protocol': 'freedom',
            'settings': {'domainStrategy': 'UseIP'}
          },
          {'tag': 'blackhole', 'protocol': 'blackhole', 'settings': {}},
        ],
      };

  static List<JsonMap> standardInbounds() => [
        {
          'tag': 'socks',
          'port': 10808,
          'protocol': 'socks',
          'listen': '127.0.0.1',
          'settings': {'auth': 'noauth', 'udp': true, 'userLevel': 8},
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
            'routeOnly': false,
          },
        },
        {
          'tag': 'http',
          'port': 10809,
          'protocol': 'http',
          'listen': '127.0.0.1',
          'settings': {'userLevel': 8},
          'sniffing': {
            'enabled': true,
            'destOverride': ['http', 'tls', 'quic'],
            'routeOnly': false,
          },
        }
      ];

  static JsonMap _stream(
    StringMap p, {
    required String host,
    String defaultSecurity = 'none',
  }) {
    var net = _p(p, 'type', _p(p, 'net', 'tcp')).toLowerCase();
    if (net == 'raw') net = 'tcp';
    if (net == 'splithttp') net = 'xhttp';
    if (net == 'mkcp') net = 'kcp';
    if (net == 'http') net = 'h2';

    final path = _p(p, 'path');
    final hostHeader = _p(p, 'host');
    final JsonMap stream = {'network': net};

    switch (net) {
      case 'ws':
        final JsonMap ws = {'path': path.isEmpty ? '/' : path};
        if (hostHeader.isNotEmpty) ws['headers'] = {'Host': hostHeader};
        stream['wsSettings'] = ws;
        break;
      case 'grpc':
        stream['grpcSettings'] = {
          'serviceName': _p(p, 'servicename', path),
          'multiMode': _p(p, 'mode') == 'multi',
        };
        break;
      case 'httpupgrade':
        stream['httpupgradeSettings'] = {
          'path': path.isEmpty ? '/' : path,
          'host': hostHeader,
        };
        break;
      case 'xhttp':
        final JsonMap x = {
          'path': path.isEmpty ? '/' : path,
          'host': hostHeader,
          'mode': _p(p, 'mode', 'auto'),
        };
        final extra = _p(p, 'extra');
        if (extra.isNotEmpty) {
          try {
            final decoded = jsonDecode(extra);
            if (decoded is Map) x['extra'] = decoded;
          } catch (_) {}
        }
        stream['xhttpSettings'] = x;
        break;
      case 'kcp':
        final JsonMap kcp = {
          'header': {'type': _p(p, 'headertype', 'none')},
        };
        final seed = _p(p, 'seed');
        if (seed.isNotEmpty) kcp['seed'] = seed;
        stream['kcpSettings'] = kcp;
        break;
      case 'h2':
        stream['httpSettings'] = {
          'path': path.isEmpty ? '/' : path,
          'host': hostHeader.isEmpty ? <String>[] : hostHeader.split(','),
        };
        break;
      case 'tcp':
      default:
        if (_p(p, 'headertype') == 'http') {
          stream['tcpSettings'] = {
            'header': {
              'type': 'http',
              'request': {
                'version': '1.1',
                'method': 'GET',
                'path': [path.isEmpty ? '/' : path],
                'headers': {
                  'Host':
                      hostHeader.isEmpty ? <String>[] : hostHeader.split(','),
                  'Connection': ['keep-alive'],
                },
              },
            },
          };
        }
        break;
    }

    final sec = _p(p, 'security', defaultSecurity).toLowerCase();
    if (sec == 'tls') {
      stream['security'] = 'tls';
      final JsonMap tls = {
        'serverName': _p(
            p, 'sni', _p(p, 'peer', hostHeader.isNotEmpty ? hostHeader : host)),
        'allowInsecure':
            _truthy(p['allowinsecure']) || _truthy(p['insecure']),
      };
      final fp = _p(p, 'fp');
      if (fp.isNotEmpty) tls['fingerprint'] = fp;
      final alpn = _p(p, 'alpn');
      if (alpn.isNotEmpty) tls['alpn'] = alpn.split(',');
      stream['tlsSettings'] = tls;
    } else if (sec == 'reality') {
      stream['security'] = 'reality';
      stream['realitySettings'] = {
        'serverName': _p(p, 'sni', host),
        'fingerprint': _p(p, 'fp', 'chrome'),
        'publicKey': _p(p, 'pbk'),
        'shortId': _p(p, 'sid'),
        'spiderX': _p(p, 'spx'),
      };
    }
    return stream;
  }

  static ConvertedConfig? convert(String link) {
    final l = link.trim();
    final lower = l.toLowerCase();
    try {
      if (lower.startsWith('vless://')) return _vless(l);
      if (lower.startsWith('vmess://')) return _vmess(l);
      if (lower.startsWith('trojan://')) return _trojan(l);
      if (lower.startsWith('ss://')) return _shadowsocks(l);
      if (lower.startsWith('socks://') || lower.startsWith('socks5://')) {
        return _socks(l);
      }
    } catch (_) {}
    return null;
  }

  static String _remarkOrDefault(ParsedLink p) =>
      p.fragment.isNotEmpty ? p.fragment : '${p.host}:${p.port}';

  static ConvertedConfig? _vless(String link) {
    final p = splitLink(link);
    if (p == null || p.userInfo.isEmpty) return null;
    final JsonMap user = {
      'id': p.userInfo,
      'encryption': _p(p.params, 'encryption', 'none'),
      'level': 8,
    };
    final flow = _p(p.params, 'flow');
    if (flow.isNotEmpty) user['flow'] = flow;

    final JsonMap outbound = {
      'tag': 'proxy',
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {
            'address': p.host,
            'port': p.port,
            'users': [user],
          }
        ],
      },
      'streamSettings': _stream(p.params, host: p.host),
    };
    return ConvertedConfig(_remarkOrDefault(p), 'VLESS', _wrap(outbound));
  }

  static ConvertedConfig? _trojan(String link) {
    final p = splitLink(link);
    if (p == null || p.userInfo.isEmpty) return null;
    final JsonMap outbound = {
      'tag': 'proxy',
      'protocol': 'trojan',
      'settings': {
        'servers': [
          {
            'address': p.host,
            'port': p.port,
            'password': p.userInfo,
            'level': 8
          }
        ],
      },
      'streamSettings':
          _stream(p.params, host: p.host, defaultSecurity: 'tls'),
    };
    return ConvertedConfig(_remarkOrDefault(p), 'TROJAN', _wrap(outbound));
  }

  static ConvertedConfig? _vmess(String link) {
    var payload = link.substring('vmess://'.length).trim();
    var fragment = '';
    final hashIdx = payload.indexOf('#');
    if (hashIdx >= 0) {
      fragment = safeDecode(payload.substring(hashIdx + 1)).trim();
      payload = payload.substring(0, hashIdx);
    }

    final decoded = decodeBase64Loose(payload);
    if (decoded != null && decoded.trim().startsWith('{')) {
      final j = jsonDecode(decoded);
      if (j is! Map) return null;
      String s(String k) => (j[k] ?? '').toString();

      final host = s('add');
      final port = int.tryParse(s('port'));
      final id = s('id');
      if (host.isEmpty || port == null || id.isEmpty) return null;

      final net = s('net').isEmpty ? 'tcp' : s('net');
      final StringMap params = {
        'type': net,
        'headertype':
            s('type') == 'multi' || s('type') == 'gun' ? '' : s('type'),
        'host': s('host'),
        'path': s('path'),
        'security': s('tls') == 'tls'
            ? 'tls'
            : (s('tls') == 'reality' ? 'reality' : 'none'),
        'sni': s('sni'),
        'fp': s('fp'),
        'alpn': s('alpn'),
        'allowinsecure': s('allowInsecure'),
      };
      if (net == 'grpc') {
        params['servicename'] = s('path');
        params['mode'] = s('type') == 'multi' ? 'multi' : '';
      }

      final JsonMap outbound = {
        'tag': 'proxy',
        'protocol': 'vmess',
        'settings': {
          'vnext': [
            {
              'address': host,
              'port': port,
              'users': [
                {
                  'id': id,
                  'alterId': int.tryParse(s('aid')) ?? 0,
                  'security': s('scy').isEmpty ? 'auto' : s('scy'),
                  'level': 8,
                }
              ],
            }
          ],
        },
        'streamSettings': _stream(params, host: host),
      };
      final remark = s('ps').isNotEmpty
          ? s('ps')
          : (fragment.isNotEmpty ? fragment : '$host:$port');
      return ConvertedConfig(remark, 'VMESS', _wrap(outbound));
    }

    final p = splitLink(link);
    if (p == null || p.userInfo.isEmpty) return null;
    final JsonMap outbound = {
      'tag': 'proxy',
      'protocol': 'vmess',
      'settings': {
        'vnext': [
          {
            'address': p.host,
            'port': p.port,
            'users': [
              {
                'id': p.userInfo,
                'alterId': 0,
                'security': _p(p.params, 'encryption', 'auto'),
                'level': 8
              }
            ],
          }
        ],
      },
      'streamSettings': _stream(p.params, host: p.host),
    };
    return ConvertedConfig(_remarkOrDefault(p), 'VMESS', _wrap(outbound));
  }

  static ConvertedConfig? _shadowsocks(String link) {
    var rest = link.substring('ss://'.length).trim();
    var fragment = '';
    final hashIdx = rest.indexOf('#');
    if (hashIdx >= 0) {
      fragment = safeDecode(rest.substring(hashIdx + 1)).trim();
      rest = rest.substring(0, hashIdx);
    }
    final qIdx = rest.indexOf('?');
    if (qIdx >= 0) rest = rest.substring(0, qIdx);
    while (rest.endsWith('/')) {
      rest = rest.substring(0, rest.length - 1);
    }

    String? creds;
    String? hostPart;

    if (rest.contains('@')) {
      final at = rest.lastIndexOf('@');
      final userPart = rest.substring(0, at);
      hostPart = rest.substring(at + 1);
      creds = userPart.contains(':')
          ? safeDecode(userPart)
          : decodeBase64Loose(userPart);
    } else {
      final decoded = decodeBase64Loose(rest);
      if (decoded == null) return null;
      final at = decoded.lastIndexOf('@');
      if (at <= 0) return null;
      creds = decoded.substring(0, at);
      hostPart = decoded.substring(at + 1);
    }

    if (creds == null) return null;
    final colon = creds.indexOf(':');
    if (colon <= 0) return null;
    final method = creds.substring(0, colon);
    final password = creds.substring(colon + 1);

    final hp = parseHostPort(hostPart);
    if (hp == null) return null;

    final JsonMap outbound = {
      'tag': 'proxy',
      'protocol': 'shadowsocks',
      'settings': {
        'servers': [
          {
            'address': hp.host,
            'port': hp.port,
            'method': method,
            'password': password,
            'level': 8,
          }
        ],
      },
    };
    final remark =
        fragment.isNotEmpty ? fragment : '${hp.host}:${hp.port}';
    return ConvertedConfig(remark, 'SHADOWSOCKS', _wrap(outbound));
  }

  static ConvertedConfig? _socks(String link) {
    final p = splitLink(link);
    if (p == null) return null;

    String? user;
    String? pass;
    if (p.userInfo.isNotEmpty) {
      var cred = p.userInfo;
      if (!cred.contains(':')) {
        cred = decodeBase64Loose(cred) ?? cred;
      }
      final idx = cred.indexOf(':');
      if (idx > 0) {
        user = cred.substring(0, idx);
        pass = cred.substring(idx + 1);
      }
    }

    final JsonMap serverObj = {
      'address': p.host,
      'port': p.port,
    };
    if (user != null && user.isNotEmpty) {
      serverObj['users'] = [
        {'user': user, 'pass': pass ?? '', 'level': 8}
      ];
    }

    final JsonMap outbound = {
      'tag': 'proxy',
      'protocol': 'socks',
      'settings': {
        'servers': [serverObj],
      },
    };
    return ConvertedConfig(_remarkOrDefault(p), 'SOCKS', _wrap(outbound));
  }
}

class ExtractedEntries {
  final List<String> links = [];
  final List<JsonMap> jsonConfigs = [];
  bool looksLikeHtml = false;
  bool looksLikeClash = false;
}

ExtractedEntries extractEntries(String body, {int depth = 0}) {
  final out = ExtractedEntries();
  final text = body.replaceAll('\uFEFF', '').trim();
  if (text.isEmpty) return out;

  if (text.startsWith('{') || text.startsWith('[')) {
    try {
      final j = jsonDecode(text);
      final list = j is List ? j : [j];
      for (final e in list) {
        if (e is Map && e['outbounds'] is List) {
          out.jsonConfigs.add(JsonMap.from(e));
        }
      }
      if (out.jsonConfigs.isNotEmpty) return out;
    } catch (_) {}
  }

  final head = text.substring(0, min(300, text.length)).toLowerCase();
  if (head.contains('html') || head.contains('doctype')) {
    out.looksLikeHtml = true;
    return out;
  }

  if (RegExp(r'^\s*proxies\s*:', multiLine: true).hasMatch(text)) {
    out.looksLikeClash = true;
    return out;
  }

  if (text.contains('://')) {
    final schemeChars = RegExp(r'[A-Za-z0-9+.\-]');
    for (final raw in text.split(RegExp(r'[\r\n]+'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final count = '://'.allMatches(line).length;
      if (count == 0) continue;

      if (count == 1) {
        final idx = line.indexOf('://');
        var start = idx;
        while (start > 0 && schemeChars.hasMatch(line[start - 1])) {
          start--;
        }
        if (start != idx) out.links.add(line.substring(start));
      } else {
        for (final m in RegExp(r'[A-Za-z][A-Za-z0-9+.\-]*://\S+')
            .allMatches(line)) {
          out.links.add(m.group(0)!);
        }
      }
    }
    if (out.links.isNotEmpty) return out;
  }

  if (depth <= 1) {
    final decoded = LinkParser.decodeBase64Loose(text);
    if (decoded != null && decoded.trim().isNotEmpty) {
      return extractEntries(decoded, depth: depth + 1);
    }
  }
  return out;
}

class ImportReport {
  final List<ServerItem> servers = [];
  int failed = 0;
  final IntMap unsupported = {};
  bool looksLikeHtml = false;
  bool looksLikeClash = false;
  String rawPreview = '';
  int httpStatus = 0;
  String? error;

  int get added => servers.length;
  bool get hasProblems =>
      error != null ||
      failed > 0 ||
      unsupported.isNotEmpty ||
      looksLikeHtml ||
      looksLikeClash ||
      added == 0;
}

String _schemeOf(String link) {
  final i = link.indexOf('://');
  return i <= 0 ? '' : link.substring(0, i).toLowerCase();
}

ImportReport buildImport(
  String body, {
  required String subId,
  required String subName,
}) {
  final report = ImportReport();
  final trimmed = body.trim();
  report.rawPreview =
      trimmed.length > 600 ? trimmed.substring(0, 600) : trimmed;

  final extracted = extractEntries(body);
  report.looksLikeHtml = extracted.looksLikeHtml;
  report.looksLikeClash = extracted.looksLikeClash;

  final stamp = DateTime.now().microsecondsSinceEpoch;
  var index = 0;

  for (final cfg in extracted.jsonConfigs) {
    try {
      final outbounds = cfg['outbounds'] as List;
      Map? main;
      for (final o in outbounds) {
        if (o is Map && o['tag'] == 'proxy') main = o;
      }
      main ??= outbounds.firstWhere(
        (o) =>
            o is Map &&
            !['freedom', 'blackhole', 'dns'].contains(o['protocol']),
        orElse: () => null,
      ) as Map?;

      if (cfg['inbounds'] == null || (cfg['inbounds'] as List).isEmpty) {
        cfg['inbounds'] = LinkParser.standardInbounds();
      }
      final remark =
          (cfg['remarks'] ?? cfg['remark'] ?? cfg['ps'] ?? '').toString().trim();
      final finalRemark = remark.isEmpty ? 'Custom JSON ${index + 1}' : remark;
      final protocol = (main?['protocol'] ?? 'JSON').toString().toUpperCase();
      index++;
      final item = ServerItem(
        id: '${subId}_${stamp}_$index',
        rawUrl: '',
        remark: finalRemark,
        protocol: protocol,
        subId: subId,
        subName: subName,
        fullJsonConfig: jsonEncode(cfg),
      );
      item.countryCode = detectCountryFromText(finalRemark);
      report.servers.add(item);
    } catch (_) {
      report.failed++;
    }
  }

  final seen = <String>{};
  for (final link in extracted.links) {
    if (!seen.add(link)) continue;
    final scheme = _schemeOf(link);
    if (scheme == 'http' || scheme == 'https') continue;

    if (!kSupportedSchemes.contains(scheme)) {
      report.unsupported[scheme] = (report.unsupported[scheme] ?? 0) + 1;
      continue;
    }

    String? fullConfig;
    String remark = '';
    String protocol = scheme.toUpperCase();

    final preferOwn = RegExp(
      r'(type|net)=(xhttp|splithttp|httpupgrade|raw)|^socks',
      caseSensitive: false,
    ).hasMatch(link);

    void tryPlugin() {
      if (fullConfig != null) return;
      try {
        final parser = V2ray.parseFromURL(link);
        fullConfig = parser.getFullConfiguration();
        remark = parser.remark.trim();
      } catch (_) {}
    }

    void tryOwn() {
      if (fullConfig != null) return;
      final c = LinkParser.convert(link);
      if (c != null) {
        fullConfig = jsonEncode(c.config);
        remark = c.remark;
        protocol = c.protocol;
      }
    }

    if (preferOwn) {
      tryOwn();
      tryPlugin();
    } else {
      tryPlugin();
      tryOwn();
    }

    if (fullConfig == null) {
      report.failed++;
      continue;
    }

    index++;
    final finalRemark = remark.isEmpty ? '$protocol $index' : remark;
    final item = ServerItem(
      id: '${subId}_${stamp}_$index',
      rawUrl: link,
      remark: finalRemark,
      protocol: protocol == 'SS'
          ? 'SHADOWSOCKS'
          : (protocol == 'SOCKS5' ? 'SOCKS' : protocol),
      subId: subId,
      subName: subName,
      fullJsonConfig: fullConfig!,
    );
    item.countryCode = detectCountryFromText(finalRemark);
    report.servers.add(item);
  }
  return report;
}

class FetchResult {
  int status = 0;
  String body = '';
  StringMap headers = {};
  String? error;
  String? resolvedUrl;
}

List<String> resolveSubscriptionCandidateUrls(
  String primaryUrl,
  String? fallbackUrl,
) {
  final candidates = <String>[];
  try {
    final uri = Uri.parse(primaryUrl.trim());
    final newUrlParam =
        uri.queryParameters['new-url'] ?? uri.queryParameters['new_url'];
    if (newUrlParam != null && newUrlParam.startsWith('http')) {
      candidates.add(newUrlParam);
    }
    candidates.add(primaryUrl.trim());
    final queryFallback = uri.queryParameters['fallback-url'] ??
        uri.queryParameters['fallback_url'];
    if (queryFallback != null && queryFallback.startsWith('http')) {
      candidates.add(queryFallback);
    }
  } catch (_) {
    candidates.add(primaryUrl.trim());
  }
  if (fallbackUrl != null && fallbackUrl.trim().startsWith('http')) {
    if (!candidates.contains(fallbackUrl.trim())) {
      candidates.add(fallbackUrl.trim());
    }
  }
  return candidates;
}

